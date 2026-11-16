import Foundation
import CoreData

/// Core Data access for weigh-ins, plus the diary reads the Dashboard needs.
/// Local only: `NutritionRepository` queues the cloud writes; restore uses `restoreWeighIns` (never queues).
extension LocalStorageService {

    private func dayBounds(_ day: Date) -> (Date, Date) {
        let start = day.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    // MARK: - Weigh-ins

    private func weighInEntity(id: UUID) -> CDWeighIn? {
        let request: NSFetchRequest<CDWeighIn> = CDWeighIn.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchWeighIn(id: UUID) -> WeighIn? {
        weighInEntity(id: id).map { WeighIn(from: $0) }
    }

    /// The weigh-in of one local day (the most recently edited if a bad merge ever left two).
    func fetchWeighIn(userId: UUID, on day: Date) -> WeighIn? {
        let (start, end) = dayBounds(day)
        let request: NSFetchRequest<CDWeighIn> = CDWeighIn.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@",
                                        userId as CVarArg, start as CVarArg, end as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first.map { WeighIn(from: $0) }
    }

    /// Weigh-ins from `range.lowerBound`'s day through `range.upperBound`'s day, oldest first.
    func fetchWeighIns(userId: UUID, in range: ClosedRange<Date>) -> [WeighIn] {
        let (start, _) = dayBounds(range.lowerBound)
        let (_, end) = dayBounds(range.upperBound)
        let request: NSFetchRequest<CDWeighIn> = CDWeighIn.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@",
                                        userId as CVarArg, start as CVarArg, end as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { WeighIn(from: $0) }
    }

    /// Newest first.
    func fetchAllWeighIns(userId: UUID) -> [WeighIn] {
        let request: NSFetchRequest<CDWeighIn> = CDWeighIn.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false), NSSortDescriptor(key: "updatedAt", ascending: false)]
        return ((try? context.fetch(request)) ?? []).map { WeighIn(from: $0) }
    }

    func fetchLatestWeighIn(userId: UUID) -> WeighIn? {
        let request: NSFetchRequest<CDWeighIn> = CDWeighIn.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false), NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first.map { WeighIn(from: $0) }
    }

    /// Upsert by id.
    func saveWeighIn(_ weighIn: WeighIn) {
        let entity = weighInEntity(id: weighIn.id) ?? CDWeighIn(context: context)
        weighIn.apply(to: entity)
        save()
    }

    @discardableResult
    func deleteWeighIns(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = weighInEntity(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        if count > 0 { save() }
        return count
    }

    // MARK: - Restore (local only, never queues)

    func restoreWeighIns(_ weighIns: [WeighIn]) {
        guard !weighIns.isEmpty else { return }
        performBatch {
            for weighIn in weighIns {
                let entity = weighInEntity(id: weighIn.id) ?? CDWeighIn(context: context)
                weighIn.apply(to: entity)
            }
        }
    }

    // MARK: - Dashboard reads

    /// Diary entries from `range.lowerBound`'s day through `range.upperBound`'s day.
    func fetchFoodEntries(userId: UUID, in range: ClosedRange<Date>) -> [FoodEntry] {
        let (start, _) = dayBounds(range.lowerBound)
        let (_, end) = dayBounds(range.upperBound)
        let request: NSFetchRequest<CDFoodEntry> = CDFoodEntry.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@",
                                        userId as CVarArg, start as CVarArg, end as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { FoodEntry(from: $0) }
    }

    /// Every distinct day that has at least one diary entry (cheap: one column, no row objects). For streaks.
    func fetchLoggedFoodDays(userId: UUID) -> Set<Date> {
        let request = NSFetchRequest<NSDictionary>(entityName: "CDFoodEntry")
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["date"]
        request.returnsDistinctResults = true
        let rows = (try? context.fetch(request)) ?? []
        return Set(rows.compactMap { ($0["date"] as? Date)?.startOfDay })
    }
}
