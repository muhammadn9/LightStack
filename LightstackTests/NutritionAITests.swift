import XCTest
import CoreData
import Supabase
@testable import Lightstack

/// Nutrition phase 4: AI meal logging. Restaurant detection, prompt and request shape, lenient parsing,
/// grounding sources, servings maths, persistence, sync, Core Data v8 -> v9 and the view model.
@MainActor
final class NutritionAITests: XCTestCase {

    private let user = UUID()

    // MARK: - Restaurant detection

    func testRestaurantSignalDetectsChainsKeywordsAndCapitalisedNames() {
        let yes = [
            "half a burrito bowl from Chipotle", "had a big mac at mcdonald's", "a latte from starbucks",
            "dinner at Joe's Pizza", "takeout from the thai place", "a salad from Sweetgreen",
            "lunch at Olive Garden", "Wendy's frosty", "went to a restaurant and had pasta", "KFC bucket 2 pieces"
        ]
        for text in yes { XCTAssertTrue(RestaurantSignal.mentionsRestaurant(text), text) }
        let no = [
            "1 cup greek yogurt, 2 strawberries, a handful of almonds", "chicken breast and rice", "a bowl from home",
            "snack at lunch", "Mom's lasagna", "2 eggs and toast at 8am", "cavatappi pasta", "oatmeal from the pantry"
        ]
        for text in no { XCTAssertFalse(RestaurantSignal.mentionsRestaurant(text), text) }
    }

    // MARK: - Prompt and request shape

    func testSearchToolOnlyWhenRestaurantMentioned() {
        let plain = NutritionAIPrompt.build(text: "1 cup greek yogurt", imageJPEG: nil, context: nil)
        XCTAssertFalse(plain.options.googleSearch)
        XCTAssertFalse(plain.systemPrompt.contains("Google Search"))
        let chain = NutritionAIPrompt.build(text: "half a burrito bowl from Chipotle", imageJPEG: nil,
                                            context: AIMealContext(mealName: "Dinner"))
        XCTAssertTrue(chain.options.googleSearch)
        XCTAssertTrue(chain.systemPrompt.contains("Google Search"))
        XCTAssertTrue(chain.systemPrompt.contains("servings"))
        XCTAssertTrue(chain.messages[0].content.contains("Meal: Dinner."))
        XCTAssertEqual(chain.options.thinking, .low)
        XCTAssertEqual(chain.options.task, .nutrition)
    }

    func testProxyBodyShapeWithToolsAndImage() throws {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let req = NutritionAIPrompt.build(text: "from Chipotle", imageJPEG: jpeg, context: nil)
        let body = GeminiService().buildChatRequestBody(systemPrompt: req.systemPrompt, messages: req.messages,
                                                        expectsJSON: true, options: req.options)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(Array(tools[0].keys), ["google_search"])
        XCTAssertEqual((tools[0]["google_search"] as? [String: Any])?.count, 0)
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        XCTAssertNil(config["responseMimeType"], "JSON mode is dropped when search is on")
        let contents = try XCTUnwrap(body["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents[0]["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        let inline = try XCTUnwrap(parts[1]["inline_data"] as? [String: String])
        XCTAssertEqual(inline["mime_type"], "image/jpeg")
        XCTAssertEqual(inline["data"], jpeg.base64EncodedString())
        // The request serialises.
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testTextOnlyNoSearchKeepsJSONModeAndNoTools() throws {
        let req = NutritionAIPrompt.build(text: "2 eggs", imageJPEG: nil, context: nil)
        let body = GeminiService().buildChatRequestBody(systemPrompt: req.systemPrompt, messages: req.messages,
                                                        expectsJSON: true, options: req.options)
        XCTAssertNil(body["tools"])
        XCTAssertEqual((body["generationConfig"] as? [String: Any])?["responseMimeType"] as? String, "application/json")
        let parts = try XCTUnwrap((body["contents"] as? [[String: Any]])?[0]["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 1)
    }

    func testPhotoPreparerShrinksToLongEdge1024() throws {
        let size = 3000
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try XCTUnwrap(CGContext(data: nil, width: size, height: size / 2, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.8, green: 0.3, blue: 0.2, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size / 2))
        let image = try XCTUnwrap(ctx.makeImage())
        let data = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))

        let out = try NutritionPhotoPreparer.prepare(data as Data)
        let src = try XCTUnwrap(CGImageSourceCreateWithData(out as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        XCTAssertEqual(max(w, h), 1024)
        XCTAssertLessThan(out.count * 4 / 3, NutritionPhotoPreparer.maxBase64Chars)
        XCTAssertThrowsError(try NutritionPhotoPreparer.prepare(Data([1, 2, 3])))
    }

    // MARK: - Lenient parsing

    private let good = """
    {"items":[{"name":"Chicken Burrito Bowl","restaurant":"Chipotle","brand":null,"portion_text":"half","servings":0.5,
     "full_item":{"serving_label":"1 bowl","kcal":1000,"protein_g":60,"carbs_g":100,"fat_g":35,"fiber_g":14,"sugar_g":6,
     "sodium_mg":2100,"sat_fat_g":11},"confidence":"high","notes":"Published values."}],"clarifying_question":null}
    """

    func testParsesCleanJSON() throws {
        let est = try NutritionAIParser.parse(good, usedSearch: true)
        let item = try XCTUnwrap(est.items.first)
        XCTAssertEqual(item.name, "Chicken Burrito Bowl")
        XCTAssertEqual(item.restaurant, "Chipotle")
        XCTAssertNil(item.brand)
        XCTAssertEqual(item.servings, 0.5)
        XCTAssertEqual(item.fullItem.kcal, 1000)
        XCTAssertEqual(item.fullItem.micros[.sodium], 2100)
        XCTAssertEqual(item.confidence, .high)
        XCTAssertTrue(est.usedSearch)
        XCTAssertNil(est.clarifyingQuestion)
    }

    func testParsesFencedJSONWithTrailingProse() throws {
        let text = "Here you go:\n```json\n\(good)\n```\nHope that helps! {not json}"
        XCTAssertEqual(try NutritionAIParser.parse(text).items.count, 1)
        XCTAssertEqual(try NutritionAIParser.parse("```\(good)```").items.count, 1)
    }

    func testBracesInsideStringsDoNotBreakExtraction() throws {
        let text = #"{"items":[{"name":"Soup {daily}","servings":1,"full_item":{"kcal":100,"protein_g":5,"carbs_g":10,"fat_g":3},"notes":"a } b"}]} trailing"#
        let item = try XCTUnwrap(NutritionAIParser.parse(text).items.first)
        XCTAssertEqual(item.name, "Soup {daily}")
        XCTAssertEqual(item.notes, "a } b")
    }

    func testNumbersAsStringsMissingFieldsAndClamping() throws {
        let text = """
        {"items":[{"name":"Mystery","servings":"1/2","full_item":{"kcal":"1,200 kcal","protein_g":"30 g","carbs_g":-5,"fat_g":"40",
        "fiber_g":-2,"sodium_mg":"900"}},
        {"name":"Bare","full_item":{"protein_g":10,"carbs_g":20,"fat_g":5}},
        {"name":"Weird","servings":-3,"confidence":"SUPER","full_item":{"kcal":50}},
        {"nope":true}]}
        """
        let est = try NutritionAIParser.parse(text)
        XCTAssertEqual(est.items.count, 3, "an item without a name is skipped")
        let a = est.items[0]
        XCTAssertEqual(a.servings, 0.5)
        XCTAssertEqual(a.fullItem.kcal, 1200)
        XCTAssertEqual(a.fullItem.protein, 30)
        XCTAssertEqual(a.fullItem.carbs, 0, "negatives clamp to 0")
        XCTAssertEqual(a.fullItem.fat, 40)
        XCTAssertEqual(a.fullItem.micros[.fiber], 0)
        XCTAssertEqual(a.fullItem.micros[.sodium], 900)
        XCTAssertNil(a.fullItem.micros[.sugar], "unknown stays unknown")
        let bare = est.items[1]
        XCTAssertEqual(bare.servings, 1)
        XCTAssertEqual(bare.fullItem.kcal, 165, "kcal derived from 4/4/9 when missing")
        XCTAssertEqual(bare.servingLabel, "1 serving")
        XCTAssertEqual(bare.confidence, .medium)
        let weird = est.items[2]
        XCTAssertEqual(weird.servings, 1, "non-positive servings fall back to 1")
        XCTAssertEqual(weird.confidence, .medium)
    }

    func testCapsItemCountAndServings() throws {
        let items = (0..<20).map { #"{"name":"Item \#($0)","servings":99,"full_item":{"kcal":10,"protein_g":1,"carbs_g":1,"fat_g":0}}"# }
        let est = try NutritionAIParser.parse(#"{"items":[\#(items.joined(separator: ","))]}"#)
        XCTAssertEqual(est.items.count, NutritionAIParser.maxItems)
        XCTAssertEqual(est.items[0].servings, NutritionAIParser.maxServings)
    }

    func testClarifyingQuestionAndErrors() throws {
        let q = try NutritionAIParser.parse(#"{"items":[],"clarifying_question":"Which size?"}"#)
        XCTAssertTrue(q.items.isEmpty)
        XCTAssertEqual(q.clarifyingQuestion, "Which size?")
        XCTAssertThrowsError(try NutritionAIParser.parse("I think about 500 calories.")) {
            XCTAssertEqual($0 as? NutritionAIError, .unparseable)
        }
        XCTAssertThrowsError(try NutritionAIParser.parse(#"{"items":[{"name":"Broken","full_item":{"kcal":"#)) {
            XCTAssertEqual($0 as? NutritionAIError, .unparseable)
        }
        XCTAssertThrowsError(try NutritionAIParser.parse(#"{"items":[]}"#)) {
            XCTAssertEqual($0 as? NutritionAIError, .empty)
        }
        XCTAssertThrowsError(try NutritionAIParser.parse(#"{"hello":1}"#)) {
            XCTAssertEqual($0 as? NutritionAIError, .unparseable)
        }
    }

    func testKcalMismatchFlag() throws {
        var item = try XCTUnwrap(NutritionAIParser.parse(good).items.first)
        XCTAssertFalse(item.kcalLooksOff, "1000 vs 60*4+100*4+35*9 = 955")
        item.fullItem.kcal = 300
        XCTAssertTrue(item.kcalLooksOff)
        item.fullItem.kcal = 960
        XCTAssertFalse(item.kcalLooksOff)
    }

    // MARK: - Grounding sources

    func testGroundingSourcesComeFromMetadataNotText() throws {
        let response = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"items\\":[{\\"name\\":\\"X\\",\\"notes\\":\\"see https://fake.example/made-up\\",\\"full_item\\":{\\"kcal\\":10}}]}"}]},
         "groundingMetadata":{"groundingChunks":[
           {"web":{"uri":"https://www.chipotle.com/nutrition","title":"Chipotle Nutrition"}},
           {"web":{"uri":"https://www.chipotle.com/nutrition","title":"Duplicate"}},
           {"web":{"uri":"https://example.com/menu"}},
           {"retrievedContext":{"uri":"ignored"}},
           {"web":{"title":"No URI"}}]}}]}
        """
        let data = Data(response.utf8)
        let sources = GeminiService.groundingSources(from: data)
        XCTAssertEqual(sources, [AIFoodSource(title: "Chipotle Nutrition", url: "https://www.chipotle.com/nutrition"),
                                 AIFoodSource(title: "example.com", url: "https://example.com/menu")])
        let reply = try GeminiService().parseReply(data, task: .nutrition, expectsJSON: true)
        XCTAssertEqual(reply.sources, sources)
        let est = try NutritionAIParser.estimate(from: reply, usedSearch: true)
        XCTAssertEqual(est.items[0].sources, sources)
        XCTAssertEqual(est.sources, sources)
        XCTAssertTrue(GeminiService.groundingSources(from: Data(#"{"candidates":[{}]}"#.utf8)).isEmpty)
    }

    func testMultiPartReplyIsJoinedAndThoughtsSkipped() throws {
        let response = #"{"candidates":[{"content":{"parts":[{"text":"hidden","thought":true},{"text":"{\"items\":[{\"name\":\"A\","},{"text":"\"full_item\":{\"kcal\":5}}]}"}]}}]}"#
        let reply = try GeminiService().parseReply(Data(response.utf8), expectsJSON: true)
        XCTAssertEqual(try NutritionAIParser.parse(reply.text).items.first?.name, "A")
    }

    // MARK: - Error mapping

    func testErrorMapping() {
        let rate = GeminiService.proxyError(429, "Too many AI requests. Please wait a moment before trying again.")
        XCTAssertEqual(NutritionAIError.from(rate), .rateLimited("Too many AI requests. Please wait a moment before trying again."))
        XCTAssertEqual(NutritionAIError.from(GeminiService.proxyError(504, "slow")), .timeout)
        XCTAssertEqual(NutritionAIError.from(GeminiService.proxyError(401, "Please sign in to use the AI coach.")),
                       .failed("Please sign in to use the AI coach."))
        XCTAssertEqual(NutritionAIError.from(URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(NutritionAIError.from(URLError(.timedOut)), .timeout)
        for e in [NutritionAIError.offline, .timeout, .unparseable, .empty] { XCTAssertFalse(e.message.isEmpty) }
    }

    // MARK: - Servings maths

    func testHalfServingScalesAllNutrients() throws {
        let item = try XCTUnwrap(NutritionAIParser.parse(good).items.first)
        let eaten = item.eaten
        XCTAssertEqual(eaten.kcal, 500)
        XCTAssertEqual(eaten.protein, 30)
        XCTAssertEqual(eaten.carbs, 50)
        XCTAssertEqual(eaten.fat, 17.5)
        XCTAssertEqual(eaten.micros[.sodium], 1050)
        XCTAssertEqual(item.fullItem.kcal, 1000, "the full item is not mutated")
    }

    // MARK: - Fake

    func testFakeIsDeterministic() async throws {
        let fake = FakeNutritionAIService()
        let bowl = try await fake.estimate(text: "I ate half of a chicken bowl from Chipotle", image: nil, mealContext: nil)
        XCTAssertEqual(bowl.items.count, 1)
        XCTAssertEqual(bowl.items[0].name, "Chicken Burrito Bowl")
        XCTAssertEqual(bowl.items[0].restaurant, "Chipotle")
        XCTAssertEqual(bowl.items[0].servings, 0.5)
        XCTAssertEqual(bowl.items[0].fullItem.kcal, 1000)
        XCTAssertEqual(bowl.items[0].sources.count, 2)
        let yogurt = try await fake.estimate(text: "1 cup greek yogurt, 2 strawberries", image: nil, mealContext: nil)
        XCTAssertEqual(yogurt.items.count, 2)
        let photo = try await fake.estimate(text: "", image: Data([1]), mealContext: nil)
        XCTAssertEqual(photo.items.count, 1)
        do { _ = try await fake.estimate(text: "fail please", image: nil, mealContext: nil); XCTFail() } catch {}
    }

    // MARK: - Persistence, logging and sync

    private struct Device {
        let stack: OutboxTestStack
        let repo: NutritionRepository
        var storage: LocalStorageService { stack.storage }
    }

    private func makeDevice(remote: FakeRemote = FakeRemote()) -> Device {
        let stack = OutboxTestStack(userId: user, remote: remote)
        return Device(stack: stack, repo: NutritionRepository(localStorage: stack.storage, offlineQueueManager: stack.queue))
    }

    private func chipotleItem() throws -> AIMealItem {
        var item = try XCTUnwrap(NutritionAIParser.parse(good).items.first)
        item.sources = FakeNutritionAIService.chipotleSources
        return item
    }

    func testLoggingHalfBowlSavesFullFoodAndLogsHalf() throws {
        let d = makeDevice()
        let today = Date().startOfDay
        let entries = d.repo.logAIItems([try chipotleItem()], userId: user, mealSlotId: nil, on: today)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.servings, 0.5)
        XCTAssertEqual(entry.total.kcal, 500)
        XCTAssertEqual(entry.total.protein, 30)
        let food = try XCTUnwrap(d.repo.food(id: try XCTUnwrap(entry.foodId)))
        XCTAssertEqual(food.source, .ai)
        XCTAssertTrue(food.isAIEstimate)
        XCTAssertEqual(food.name, "Chicken Burrito Bowl")
        XCTAssertEqual(food.brand, "Chipotle")
        XCTAssertEqual(food.nutrients.kcal, 1000, "the saved food is the full item")
        XCTAssertEqual(food.aiConfidence, .high)
        XCTAssertEqual(food.aiSources, FakeNutritionAIService.chipotleSources)
        XCTAssertEqual(d.repo.recentFoods(userId: user).map(\.id), [food.id], "shows in Recent")
    }

    func testSameEstimateReusesTheSavedFoodAndEditedValuesDoNot() throws {
        let d = makeDevice()
        let item = try chipotleItem()
        let first = d.repo.saveAIFood(item, userId: user)
        XCTAssertEqual(d.repo.saveAIFood(item, userId: user).id, first.id)
        var edited = item
        edited.fullItem.kcal = 900
        XCTAssertNotEqual(d.repo.saveAIFood(edited, userId: user).id, first.id)
        XCTAssertEqual(d.storage.fetchFoods(userId: user).count, 2)
    }

    func testAIFoodUploadsWithSourcesAndRoundTripsLocally() async throws {
        let remote = FakeRemote()
        let d = makeDevice(remote: remote)
        let food = d.repo.saveAIFood(try chipotleItem(), userId: user)
        await d.stack.flushAll()
        let uploaded = try XCTUnwrap(remote.foods[food.id])
        XCTAssertEqual(uploaded.source, .ai)
        XCTAssertEqual(uploaded.aiSources.count, 2)
        XCTAssertEqual(uploaded.aiConfidence, .high)
        let local = try XCTUnwrap(d.storage.fetchFood(id: food.id))
        XCTAssertEqual(local.aiSources, food.aiSources)
        XCTAssertEqual(local.aiConfidence, .high)
        XCTAssertEqual(local.source, .ai)
    }

    private struct AnyEncodable: Encodable {
        let wrapped: Encodable
        func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
    }

    func testWireFormatCarriesAIColumns() throws {
        let food = NutritionFood.make(userId: user, name: "Bowl", nutrients: NutrientValues(kcal: 1, protein: 1, carbs: 1, fat: 1),
                                      source: .ai, aiSources: [AIFoodSource(title: "T", url: "https://x.example")],
                                      aiConfidence: .low)
        for forCloud in [true, false] {
            let data = try JSONEncoder().encode(forCloud ? AnyEncodable(wrapped: food.cloudRow()) : AnyEncodable(wrapped: food))
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(obj["source"] as? String, "ai")
            XCTAssertEqual(obj["ai_confidence"] as? String, "low")
            let sources = try XCTUnwrap(obj["ai_sources"] as? [[String: String]])
            XCTAssertEqual(sources, [["title": "T", "url": "https://x.example"]])
        }
        // Round trip.
        let decoded = try JSONDecoder().decode(NutritionFood.self, from: JSONEncoder().encode(AnyEncodable(wrapped: food)))
        XCTAssertEqual(decoded, food)
        // Non-AI foods write explicit nulls, and an old server row without the columns still decodes.
        var plain = food
        plain.source = .quick; plain.aiSources = []; plain.aiConfidence = nil
        let data = try JSONEncoder().encode(AnyEncodable(wrapped: plain.cloudRow()))
        var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(obj["ai_sources"] is NSNull)
        XCTAssertTrue(obj["ai_confidence"] is NSNull)
        obj.removeValue(forKey: "ai_sources"); obj.removeValue(forKey: "ai_confidence")
        let old = try JSONDecoder().decode(NutritionFood.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(old.aiSources.isEmpty)
        XCTAssertNil(old.aiConfidence)
        // A malformed value never breaks restore.
        obj["ai_sources"] = "garbage"; obj["ai_confidence"] = "extreme"
        let bad = try JSONDecoder().decode(NutritionFood.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertTrue(bad.aiSources.isEmpty)
        XCTAssertNil(bad.aiConfidence)
    }

    func testMissingAIColumnsOrSourceCheckRetryInsteadOfDeadLettering() async throws {
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "PGRST204", message: "Could not find the 'ai_sources' column"), opType: .upsertFood), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "42703", message: "column ai_confidence does not exist"), opType: .upsertFood), .dependency)
        XCTAssertEqual(SyncErrorClassifier.classify(PostgrestError(code: "23514", message: "foods_source_check"), opType: .upsertFood), .dependency)

        let remote = FakeRemote()
        remote.script = { type, _ in
            type == .upsertFood ? PostgrestError(code: "PGRST204", message: "Could not find the 'ai_sources' column") : nil
        }
        let d = makeDevice(remote: remote)
        _ = d.repo.saveAIFood(try chipotleItem(), userId: user)
        await d.stack.flushAll()
        let failed = await d.stack.queue.failedOperations()
        XCTAssertTrue(failed.isEmpty)
        let queued = await d.stack.queue.queuedOperations().map(\.type)
        XCTAssertTrue(queued.contains(.upsertFood), "stays queued until the migration is applied")
    }

    func testMigrationFileAllowsAISourceAndAddsColumns() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("supabase/migrations/20261104120000_nutrition_ai_foods.sql")
        let sql = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(sql.contains("'quick','scan','off','ai'"))
        XCTAssertTrue(sql.contains("ADD COLUMN IF NOT EXISTS ai_sources jsonb"))
        XCTAssertTrue(sql.contains("ADD COLUMN IF NOT EXISTS ai_confidence text"))
        XCTAssertTrue(sql.contains("DROP CONSTRAINT IF EXISTS foods_source_check"))
    }

    // MARK: - Core Data v8 -> v9

    func testMigratesV8StoreToV9AddsAIAttributesAndKeepsFoods() throws {
        let bundle = Bundle(for: LocalStorageService.self)
        let v8URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 8", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v9URL = try XCTUnwrap(bundle.url(forResource: "Lightstack 9", withExtension: "mom", subdirectory: "Lightstack.momd"))
        let v8Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v8URL))
        let v9Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: v9URL))
        XCTAssertNil(v8Model.entitiesByName["CDFood"]?.attributesByName["aiSources"])
        XCTAssertNotNil(v9Model.entitiesByName["CDFood"]?.attributesByName["aiSources"])
        XCTAssertNotNil(v9Model.entitiesByName["CDFood"]?.attributesByName["aiConfidence"])

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("Lightstack.sqlite")
        let foodId = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v8Model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            ctx.persistentStoreCoordinator = coordinator
            try ctx.performAndWait {
                let e = NSEntityDescription.insertNewObject(forEntityName: "CDFood", into: ctx)
                e.setValue(foodId, forKey: "id"); e.setValue(UUID(), forKey: "userId")
                e.setValue("Oats", forKey: "name"); e.setValue(150.0, forKey: "kcal")
                e.setValue("off", forKey: "source"); e.setValue("0123456789012", forKey: "barcode")
                e.setValue(Date(), forKey: "createdAt"); e.setValue(Date(), forKey: "updatedAt")
                try ctx.save()
            }
            try coordinator.remove(store)
        }

        let container = NSPersistentContainer(name: "Lightstack")
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.shouldMigrateStoreAutomatically = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        XCTAssertNil(loadError, "Migration failed: \(String(describing: loadError))")

        let ctx = container.viewContext
        let migrated = try XCTUnwrap(ctx.fetch(CDFood.fetchRequest() as NSFetchRequest<CDFood>).first)
        XCTAssertEqual(migrated.id, foodId)
        XCTAssertEqual(migrated.barcode, "0123456789012")
        XCTAssertNil(migrated.aiSources)
        XCTAssertNil(migrated.aiConfidence)
        migrated.aiSources = #"[{"title":"T","url":"https://x.example"}]"#
        migrated.aiConfidence = "high"
        try ctx.save()
        let reread = NutritionFood(from: try XCTUnwrap(ctx.fetch(CDFood.fetchRequest() as NSFetchRequest<CDFood>).first))
        XCTAssertEqual(reread.aiSources, [AIFoodSource(title: "T", url: "https://x.example")])
        XCTAssertEqual(reread.aiConfidence, .high)
    }

    // MARK: - View model

    private func makeViewModel(ai: NutritionAIServicing?) -> (NutritionViewModel, Device) {
        let d = makeDevice()
        let uid = user
        return (NutritionViewModel(repository: d.repo, userIdProvider: { uid }, nutritionAI: ai), d)
    }

    private func settle(_ vm: NutritionViewModel, until predicate: (AIEstimateState) -> Bool) async {
        for _ in 0..<200 where !predicate(vm.aiState) { try? await Task.sleep(nanoseconds: 10_000_000) }
    }

    func testViewModelEstimateThenLogHalf() async throws {
        let (vm, d) = makeViewModel(ai: FakeNutritionAIService())
        vm.reload()
        XCTAssertEqual(vm.aiState, .idle)
        vm.estimateMeal(text: "half a chicken bowl from Chipotle", image: nil)
        XCTAssertEqual(vm.aiState, .working)
        await settle(vm) { if case .result = $0 { return true } else { return false } }
        guard case .result(let estimate) = vm.aiState else { return XCTFail("\(vm.aiState)") }
        XCTAssertEqual(estimate.items.count, 1)

        var items = estimate.items
        items[0].servings = 0.25   // the user edits "half" to a quarter before logging
        let slot = try XCTUnwrap(vm.slots.first)
        let entries = vm.logAIItems(items, mealSlotId: slot.id)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].total.kcal, 250)
        XCTAssertEqual(vm.summary?.meal(for: slot.id)?.entries.count, 1)
        XCTAssertEqual(d.repo.recentFoods(userId: user).first?.source, .ai)
    }

    func testViewModelErrorsCancelAndPlate() async throws {
        let (vm, d) = makeViewModel(ai: FakeNutritionAIService(delay: 5))
        vm.reload()
        vm.estimateMeal(text: "lunch", image: nil)
        XCTAssertEqual(vm.aiState, .working)
        vm.cancelAIEstimate()
        XCTAssertEqual(vm.aiState, .idle)

        let (failing, _) = makeViewModel(ai: FakeNutritionAIService())
        failing.estimateMeal(text: "fail", image: nil)
        await settle(failing) { if case .error = $0 { return true } else { return false } }
        guard case .error(let message) = failing.aiState else { return XCTFail("\(failing.aiState)") }
        XCTAssertFalse(message.isEmpty)
        failing.estimateMeal(text: "   ", image: nil)
        XCTAssertEqual(failing.aiState, .error(NutritionAIError.empty.message))

        let (none, _) = makeViewModel(ai: nil)
        none.estimateMeal(text: "toast", image: nil)
        if case .error = none.aiState {} else { XCTFail("no service must report an error") }

        let item = try chipotleItem()
        let plate = vm.addAIItemsToPlate([item])
        XCTAssertEqual(plate.count, 1)
        XCTAssertEqual(plate[0].servings, 0.5)
        XCTAssertEqual(plate[0].food.source, .ai)
        XCTAssertEqual(d.repo.recentFoods(userId: user).count, 0, "plate does not log")
    }
}
