import XCTest
@testable import Lightstack

final class SupersetGroupTests: XCTestCase {

    private let workoutId = UUID()

    private func ex(_ name: String, _ idx: Int, group: UUID? = nil) -> Exercise {
        Exercise.create(
            workoutId: workoutId, name: name, muscleGroup: "Chest", orderIndex: idx,
            targetSets: 3, targetReps: "10", targetRir: nil, restSeconds: nil, coachNote: nil,
            supersetGroupId: group
        )
    }

    func testPagesGroupAdjacentMembers() {
        let g = UUID()
        let list = [ex("A", 0), ex("B", 1, group: g), ex("C", 2, group: g), ex("D", 3)]
        let pages = SupersetGroup.pages(from: list)
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[1].groupId, g)
        XCTAssertEqual(pages[1].exerciseIds, [list[1].id, list[2].id])
        XCTAssertFalse(pages[0].isSuperset)
    }

    func testSingleMemberGroupIsNotASuperset() {
        let list = [ex("A", 0, group: UUID()), ex("B", 1)]
        XCTAssertEqual(SupersetGroup.pages(from: list).filter(\.isSuperset).count, 0)
    }

    func testFiveMembersIsInvalid() {
        let g = UUID()
        let list = (0..<5).map { ex("E\($0)", $0, group: g) }
        XCTAssertEqual(SupersetGroup.pages(from: list).count, 5)
        XCTAssertFalse(SupersetGroup.isValid(groupId: g, in: list))
    }

    func testNonAdjacentMembersAreNotGrouped() {
        let g = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1), ex("C", 2, group: g)]
        XCTAssertEqual(SupersetGroup.pages(from: list).filter(\.isSuperset).count, 0)
    }

    func testLinkTwoPlainExercises() throws {
        let list = [ex("A", 0), ex("B", 1), ex("C", 2)]
        let out = try XCTUnwrap(SupersetGroup.link(current: list[0].id, withNext: list))
        XCTAssertNotNil(out[0].supersetGroupId)
        XCTAssertEqual(out[0].supersetGroupId, out[1].supersetGroupId)
        XCTAssertNil(out[2].supersetGroupId)
    }

    func testLinkExtendsExistingGroup() throws {
        let g = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1, group: g), ex("C", 2)]
        let out = try XCTUnwrap(SupersetGroup.link(current: list[1].id, withNext: list))
        XCTAssertTrue(out.allSatisfy { $0.supersetGroupId == g })
    }

    func testLinkRefusesOverFourAndLast() {
        let g = UUID()
        let full = [ex("A", 0, group: g), ex("B", 1, group: g), ex("C", 2, group: g), ex("D", 3, group: g), ex("E", 4)]
        XCTAssertNil(SupersetGroup.link(current: full[0].id, withNext: full))
        XCTAssertNil(SupersetGroup.link(current: full[4].id, withNext: full))
    }

    func testUnlinkClearsGroup() {
        let g = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1, group: g), ex("C", 2)]
        let out = SupersetGroup.unlink(groupId: g, in: list)
        XCTAssertTrue(out.allSatisfy { $0.supersetGroupId == nil })
    }

    func testDissolveSingletons() {
        let g = UUID(), h = UUID()
        let list = [ex("A", 0, group: g), ex("B", 1, group: h), ex("C", 2, group: h)]
        let out = SupersetGroup.dissolveSingletons(in: list)
        XCTAssertNil(out[0].supersetGroupId)
        XCTAssertEqual(out[1].supersetGroupId, h)
    }

    func testCodableRoundTripAndMissingKey() throws {
        let g = UUID()
        let e = ex("A", 0, group: g)
        let data = try JSONEncoder().encode(e)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("superset_group_id"))
        XCTAssertEqual(try JSONDecoder().decode(Exercise.self, from: data).supersetGroupId, g)
        let legacy = try JSONEncoder().encode(ex("B", 1))
        XCTAssertNil(try JSONDecoder().decode(Exercise.self, from: legacy).supersetGroupId)
    }

    func testCoreDataRoundTrip() {
        let storage = LocalStorageService(inMemory: true)
        let w = Workout.create(userId: UUID(), workoutType: "Push", energyLevel: nil, timeAvailableMinutes: nil)
        storage.saveWorkout(w)
        let g = UUID()
        let e = Exercise.create(workoutId: w.id, name: "A", muscleGroup: "Chest", orderIndex: 0,
                                targetSets: 3, targetReps: "10", targetRir: nil, restSeconds: nil,
                                coachNote: nil, supersetGroupId: g)
        storage.saveExercises([e], workoutId: w.id)
        XCTAssertEqual(storage.fetchExercises(workoutId: w.id).first.map { Exercise(from: $0).supersetGroupId }, g)
    }
}
