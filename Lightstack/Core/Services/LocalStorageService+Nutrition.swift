import Foundation
import CoreData

/// Core Data access for nutrition targets, foods and diary entries.
/// Local only: `NutritionRepository` queues the cloud writes, `SyncRestoreService` uses the restore* upserts
/// (which never queue anything).
extension LocalStorageService {

    // MARK: - Targets

    func fetchNutritionTargets(userId: UUID) -> [NutritionTarget] {
        let request: NSFetchRequest<CDNutritionTarget> = CDNutritionTarget.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "effectiveDate", ascending: false)]
        return ((try? context.fetch(request)) ?? []).map { NutritionTarget(from: $0) }
    }

    private func nutritionTargetEntity(id: UUID) -> CDNutritionTarget? {
        let request: NSFetchRequest<CDNutritionTarget> = CDNutritionTarget.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchNutritionTarget(id: UUID) -> NutritionTarget? {
        nutritionTargetEntity(id: id).map { NutritionTarget(from: $0) }
    }

    /// Upsert by id.
    func saveNutritionTarget(_ target: NutritionTarget) {
        let entity = nutritionTargetEntity(id: target.id) ?? CDNutritionTarget(context: context)
        target.apply(to: entity)
        save()
    }

    @discardableResult
    func deleteNutritionTargets(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = nutritionTargetEntity(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    // MARK: - Foods

    func fetchFoods(userId: UUID) -> [NutritionFood] {
        let request: NSFetchRequest<CDFood> = CDFood.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        return ((try? context.fetch(request)) ?? []).map { NutritionFood(from: $0) }
    }

    private func foodEntity(id: UUID) -> CDFood? {
        let request: NSFetchRequest<CDFood> = CDFood.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchFood(id: UUID) -> NutritionFood? {
        foodEntity(id: id).map { NutritionFood(from: $0) }
    }

    /// Upsert by id.
    func saveFood(_ food: NutritionFood) {
        let entity = foodEntity(id: food.id) ?? CDFood(context: context)
        food.apply(to: entity)
        save()
    }

    @discardableResult
    func deleteFoods(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = foodEntity(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    // MARK: - Entries

    func fetchFoodEntries(userId: UUID, on day: Date) -> [FoodEntry] {
        let start = day.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let request: NSFetchRequest<CDFoodEntry> = CDFoodEntry.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@",
                                        userId as CVarArg, start as CVarArg, end as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { FoodEntry(from: $0) }
    }

    func fetchAllFoodEntries(userId: UUID) -> [FoodEntry] {
        let request: NSFetchRequest<CDFoodEntry> = CDFoodEntry.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { FoodEntry(from: $0) }
    }

    private func foodEntryEntity(id: UUID) -> CDFoodEntry? {
        let request: NSFetchRequest<CDFoodEntry> = CDFoodEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchFoodEntry(id: UUID) -> FoodEntry? {
        foodEntryEntity(id: id).map { FoodEntry(from: $0) }
    }

    /// Upsert by id.
    func saveFoodEntry(_ entry: FoodEntry) {
        let entity = foodEntryEntity(id: entry.id) ?? CDFoodEntry(context: context)
        entry.apply(to: entity)
        save()
    }

    @discardableResult
    func deleteFoodEntries(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = foodEntryEntity(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    /// Detaches entries from a food (their `foodId` becomes nil). Returns the entries as they are now.
    func detachFoodEntries(foodIds: Set<UUID>, userId: UUID) -> [FoodEntry] {
        let request: NSFetchRequest<CDFoodEntry> = CDFoodEntry.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND foodId IN %@", userId as CVarArg, Array(foodIds))
        let found = (try? context.fetch(request)) ?? []
        for entity in found { entity.foodId = nil; entity.updatedAt = Date() }
        save()
        return found.map { FoodEntry(from: $0) }
    }

    // MARK: - Restore (local only, never queues)

    func restoreNutritionTargets(_ targets: [NutritionTarget]) {
        guard !targets.isEmpty else { return }
        performBatch {
            for target in targets {
                let entity = nutritionTargetEntity(id: target.id) ?? CDNutritionTarget(context: context)
                target.apply(to: entity)
            }
        }
    }

    func restoreFoods(_ foods: [NutritionFood]) {
        guard !foods.isEmpty else { return }
        performBatch {
            for food in foods {
                let entity = foodEntity(id: food.id) ?? CDFood(context: context)
                food.apply(to: entity)
            }
        }
    }

    func restoreFoodEntries(_ entries: [FoodEntry]) {
        guard !entries.isEmpty else { return }
        performBatch {
            for entry in entries {
                let entity = foodEntryEntity(id: entry.id) ?? CDFoodEntry(context: context)
                entry.apply(to: entity)
            }
        }
    }
}
