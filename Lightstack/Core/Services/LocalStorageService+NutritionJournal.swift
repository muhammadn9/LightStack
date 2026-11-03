import Foundation
import CoreData

/// Core Data access for meal slots, water entries and day notes.
/// Local only: `NutritionRepository` queues the cloud writes; restore uses the restore* upserts (never queue).
extension LocalStorageService {

    private func dayRange(_ day: Date) -> (Date, Date) {
        let start = day.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    // MARK: - Meal slots

    /// All of the user's slots (archived included), in display order.
    func fetchMealSlots(userId: UUID) -> [MealSlot] {
        let request: NSFetchRequest<CDMealSlot> = CDMealSlot.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { MealSlot(from: $0) }
    }

    private func mealSlotEntity(id: UUID) -> CDMealSlot? {
        let request: NSFetchRequest<CDMealSlot> = CDMealSlot.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchMealSlot(id: UUID) -> MealSlot? {
        mealSlotEntity(id: id).map { MealSlot(from: $0) }
    }

    /// Upsert by id.
    func saveMealSlot(_ slot: MealSlot) {
        let entity = mealSlotEntity(id: slot.id) ?? CDMealSlot(context: context)
        slot.apply(to: entity)
        save()
    }

    /// Upserts several slots with one save.
    func saveMealSlots(_ slots: [MealSlot]) {
        guard !slots.isEmpty else { return }
        performBatch {
            for slot in slots {
                let entity = mealSlotEntity(id: slot.id) ?? CDMealSlot(context: context)
                slot.apply(to: entity)
            }
        }
    }

    // MARK: - Water

    func fetchWaterEntries(userId: UUID, on day: Date) -> [WaterEntry] {
        let (start, end) = dayRange(day)
        let request: NSFetchRequest<CDWaterEntry> = CDWaterEntry.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@",
                                        userId as CVarArg, start as CVarArg, end as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { WaterEntry(from: $0) }
    }

    func fetchAllWaterEntries(userId: UUID) -> [WaterEntry] {
        let request: NSFetchRequest<CDWaterEntry> = CDWaterEntry.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { WaterEntry(from: $0) }
    }

    private func waterEntity(id: UUID) -> CDWaterEntry? {
        let request: NSFetchRequest<CDWaterEntry> = CDWaterEntry.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchWaterEntry(id: UUID) -> WaterEntry? {
        waterEntity(id: id).map { WaterEntry(from: $0) }
    }

    /// Upsert by id.
    func saveWaterEntry(_ entry: WaterEntry) {
        let entity = waterEntity(id: entry.id) ?? CDWaterEntry(context: context)
        entry.apply(to: entity)
        save()
    }

    @discardableResult
    func deleteWaterEntries(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = waterEntity(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    // MARK: - Day notes

    func fetchDayNote(userId: UUID, on day: Date) -> DayNote? {
        let (start, end) = dayRange(day)
        let request: NSFetchRequest<CDDayNote> = CDDayNote.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND date >= %@ AND date < %@",
                                        userId as CVarArg, start as CVarArg, end as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first.map { DayNote(from: $0) }
    }

    func fetchAllDayNotes(userId: UUID) -> [DayNote] {
        let request: NSFetchRequest<CDDayNote> = CDDayNote.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return ((try? context.fetch(request)) ?? []).map { DayNote(from: $0) }
    }

    private func dayNoteEntity(id: UUID) -> CDDayNote? {
        let request: NSFetchRequest<CDDayNote> = CDDayNote.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchDayNote(id: UUID) -> DayNote? {
        dayNoteEntity(id: id).map { DayNote(from: $0) }
    }

    /// Upsert by id.
    func saveDayNote(_ note: DayNote) {
        let entity = dayNoteEntity(id: note.id) ?? CDDayNote(context: context)
        note.apply(to: entity)
        save()
    }

    // MARK: - Restore (local only, never queues)

    func restoreMealSlots(_ slots: [MealSlot]) { saveMealSlots(slots) }

    func restoreWaterEntries(_ entries: [WaterEntry]) {
        guard !entries.isEmpty else { return }
        performBatch {
            for entry in entries {
                let entity = waterEntity(id: entry.id) ?? CDWaterEntry(context: context)
                entry.apply(to: entity)
            }
        }
    }

    func restoreDayNotes(_ notes: [DayNote]) {
        guard !notes.isEmpty else { return }
        performBatch {
            for note in notes {
                let entity = dayNoteEntity(id: note.id) ?? CDDayNote(context: context)
                note.apply(to: entity)
            }
        }
    }
}
