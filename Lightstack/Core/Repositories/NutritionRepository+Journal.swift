import Foundation

/// Journal data: meal slots, batch ("plate") logging, water, day notes and the day summary.
/// Same rules as the rest of the repository: local save first, then the cloud write goes through the queue.
extension NutritionRepository {

    // MARK: - Meal slots

    /// Queues a slot that nobody has edited yet (a seeded default) next to an entry that points at it, so the
    /// foreign key is satisfied even if the seed was never uploaded. Slots the user or the cloud already
    /// touched are left alone.
    func queueMealSlotIfNeeded(_ slotId: UUID?) {
        guard let slotId, let slot = localStorage.fetchMealSlot(id: slotId), slot.isUntouchedSeed else { return }
        offlineQueueManager.submit(.upsertMealSlot, payload: slot, recordKey: slot.id.uuidString)
    }

    private func queue(_ slot: MealSlot) {
        offlineQueueManager.submit(.upsertMealSlot, payload: slot, recordKey: slot.id.uuidString)
    }

    /// Seeds Breakfast, Lunch, Dinner and Snack once. Does nothing if the user has any slot (archived included).
    /// The default ids are derived from the user id, so a device that seeds before a restore ends up with the
    /// same rows as the cloud, never duplicates. Seeds are saved locally only: they upload when the user edits
    /// one or logs into it, or via the restore's repair step.
    @discardableResult
    func ensureDefaultMealSlots(userId: UUID) -> [MealSlot] {
        let existing = localStorage.fetchMealSlots(userId: userId)
        guard existing.isEmpty else { return existing.filter { !$0.isArchived } }
        let defaults = MealSlot.defaults(userId: userId)
        localStorage.saveMealSlots(defaults)
        return defaults
    }

    /// Meals in display order. Archived ones only when asked.
    func mealSlots(userId: UUID, includeArchived: Bool = false) -> [MealSlot] {
        let all = localStorage.fetchMealSlots(userId: userId)
        return includeArchived ? all : all.filter { !$0.isArchived }
    }

    /// Adds a meal at the end of the list.
    @discardableResult
    func addMealSlot(userId: UUID, name: String) -> MealSlot? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let stamp = now()
        let next = (localStorage.fetchMealSlots(userId: userId).map(\.sortOrder).max() ?? -1) + 1
        let slot = MealSlot(id: UUID(), userId: userId, name: trimmed, sortOrder: next, isArchived: false,
                            createdAt: stamp, updatedAt: stamp)
        localStorage.saveMealSlot(slot)
        queue(slot)
        return slot
    }

    @discardableResult
    func renameMealSlot(id: UUID, name: String) -> MealSlot? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var slot = localStorage.fetchMealSlot(id: id) else { return nil }
        slot.name = trimmed
        return saveSlot(slot)
    }

    /// Soft delete: the meal disappears from the Journal but old entries keep pointing at it.
    @discardableResult
    func archiveMealSlot(id: UUID) -> MealSlot? {
        guard var slot = localStorage.fetchMealSlot(id: id) else { return nil }
        slot.isArchived = true
        return saveSlot(slot)
    }

    @discardableResult
    func unarchiveMealSlot(id: UUID) -> MealSlot? {
        guard var slot = localStorage.fetchMealSlot(id: id) else { return nil }
        slot.isArchived = false
        return saveSlot(slot)
    }

    private func saveSlot(_ slot: MealSlot) -> MealSlot {
        var saved = slot
        saved.updatedAt = now()
        localStorage.saveMealSlot(saved)
        queue(saved)
        return saved
    }

    /// Puts the given active slots in this order (positions 0...n-1); other slots keep their relative order after them.
    func reorderMealSlots(userId: UUID, orderedIds: [UUID]) {
        let all = localStorage.fetchMealSlots(userId: userId)
        let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let first = orderedIds.compactMap { byId[$0] }
        let firstIds = Set(first.map(\.id))
        let rest = all.filter { !firstIds.contains($0.id) }
        let stamp = now()
        var changed: [MealSlot] = []
        for (index, slot) in (first + rest).enumerated() where slot.sortOrder != index {
            var updated = slot
            updated.sortOrder = index
            updated.updatedAt = stamp
            changed.append(updated)
        }
        localStorage.saveMealSlots(changed)
        changed.forEach { queue($0) }
    }

    // MARK: - Batch logging

    /// Logs several saved foods into one meal on one day with a single save and one queue pass.
    /// Each food's `lastUsedAt` is refreshed too. Returns the new entries in order.
    @discardableResult
    func logFoods(_ items: [PlateItem], mealSlotId: UUID?, on date: Date, source: EntrySource? = nil) -> [FoodEntry] {
        guard !items.isEmpty else { return [] }
        let stamp = now()
        var entries: [FoodEntry] = []
        var usedFoods: [NutritionFood] = []
        for item in items {
            let entry = FoodEntry.make(from: item.food, servings: max(0, item.servings), on: date,
                                       source: source ?? (item.food.source == .scan ? .scan : .saved),
                                       mealSlotId: mealSlotId, now: stamp)
            entries.append(entry)
            if var stored = localStorage.fetchFood(id: item.food.id) {
                stored.lastUsedAt = stamp
                stored.updatedAt = stamp
                usedFoods.append(stored)
            }
        }
        queueMealSlotIfNeeded(mealSlotId)
        localStorage.performBatch {
            localStorage.saveFoodEntries(entries)
            usedFoods.forEach { localStorage.saveFood($0) }
        }
        usedFoods.forEach { offlineQueueManager.submit(.upsertFood, payload: $0, recordKey: $0.id.uuidString) }
        entries.forEach { offlineQueueManager.submit(.upsertFoodEntry, payload: $0, recordKey: $0.id.uuidString) }
        return entries
    }

    /// Moves an entry to another meal (nil = unassigned).
    @discardableResult
    func moveEntry(id: UUID, toMealSlot slotId: UUID?, userId: UUID) -> FoodEntry? {
        guard var entry = localStorage.fetchFoodEntry(id: id), entry.userId == userId else { return nil }
        entry.mealSlotId = slotId
        return updateEntry(entry)
    }

    // MARK: - Water

    @discardableResult
    func addWater(userId: UUID, amountMl: Double, on date: Date) -> WaterEntry? {
        guard amountMl > 0 else { return nil }
        let entry = WaterEntry.make(userId: userId, date: date, amountMl: amountMl, now: now())
        localStorage.saveWaterEntry(entry)
        offlineQueueManager.submit(.upsertWaterEntry, payload: entry, recordKey: entry.id.uuidString)
        return entry
    }

    /// Changes the amount of an existing log.
    @discardableResult
    func updateWater(id: UUID, userId: UUID, amountMl: Double) -> WaterEntry? {
        guard amountMl > 0, var entry = localStorage.fetchWaterEntry(id: id), entry.userId == userId else { return nil }
        entry.amountMl = amountMl
        entry.updatedAt = now()
        localStorage.saveWaterEntry(entry)
        offlineQueueManager.submit(.upsertWaterEntry, payload: entry, recordKey: entry.id.uuidString)
        return entry
    }

    func deleteWater(id: UUID, userId: UUID) {
        guard let entry = localStorage.fetchWaterEntry(id: id), entry.userId == userId else { return }
        localStorage.deleteWaterEntries(ids: [id])
        offlineQueueManager.submit(.deleteWaterEntry, payload: DeleteNutritionRecordPayload(id: id))
        offlineQueueManager.submitTombstones(.waterEntry, ids: [id])
    }

    func waterEntries(userId: UUID, on date: Date) -> [WaterEntry] {
        localStorage.fetchWaterEntries(userId: userId, on: date)
    }

    /// Total millilitres logged on a day.
    func waterTotalMl(userId: UUID, on date: Date) -> Double {
        waterEntries(userId: userId, on: date).reduce(0) { $0 + $1.amountMl }
    }

    // MARK: - Day notes

    func dayNote(userId: UUID, on date: Date) -> DayNote? {
        localStorage.fetchDayNote(userId: userId, on: date)
    }

    /// Creates or updates the day's note (one per day). Empty text clears it but keeps the row.
    @discardableResult
    func setDayNote(userId: UUID, on date: Date, text: String) -> DayNote? {
        let day = date.startOfDay
        let stamp = now()
        var note: DayNote
        if var existing = localStorage.fetchDayNote(userId: userId, on: day) {
            guard existing.text != text else { return existing }
            existing.text = text
            existing.updatedAt = stamp
            note = existing
        } else {
            if text.isEmpty { return nil }
            note = DayNote(id: DayNote.id(userId: userId, date: day), userId: userId, date: day, text: text,
                           createdAt: stamp, updatedAt: stamp)
        }
        localStorage.saveDayNote(note)
        offlineQueueManager.submit(.upsertDayNote, payload: note, recordKey: note.id.uuidString)
        return note
    }

    // MARK: - Day summary

    /// Totals (kcal, macros, every micro, water) overall and per meal, plus the active target and the day's note.
    /// Four small reads (entries, slots, water, note) and one in-memory pass: cheap enough to run on every change.
    func daySummary(userId: UUID, on date: Date) -> JournalDaySummary {
        let day = date.startOfDay
        let target = NutritionMath.target(in: localStorage.fetchNutritionTargets(userId: userId), on: day)
        return JournalDaySummaryBuilder.build(
            date: day,
            entries: localStorage.fetchFoodEntries(userId: userId, on: day),
            slots: localStorage.fetchMealSlots(userId: userId),
            water: localStorage.fetchWaterEntries(userId: userId, on: day),
            target: target,
            note: localStorage.fetchDayNote(userId: userId, on: day)
        )
    }
}
