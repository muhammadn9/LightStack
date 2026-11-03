import Foundation
import CoreData

/// Core Data access for nutrition goal settings and weekday plans.
/// Local only: `NutritionRepository` queues the cloud writes; restore uses the restore* upserts (never queue).
extension LocalStorageService {

    // MARK: - Goal settings

    func fetchGoalSettings(userId: UUID) -> NutritionGoalSettings? {
        let request: NSFetchRequest<CDNutritionGoalSettings> = CDNutritionGoalSettings.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first.map { NutritionGoalSettings(from: $0) }
    }

    private func goalSettingsEntity(id: UUID) -> CDNutritionGoalSettings? {
        let request: NSFetchRequest<CDNutritionGoalSettings> = CDNutritionGoalSettings.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchGoalSettings(id: UUID) -> NutritionGoalSettings? {
        goalSettingsEntity(id: id).map { NutritionGoalSettings(from: $0) }
    }

    /// Upsert by id.
    func saveGoalSettings(_ settings: NutritionGoalSettings) {
        let entity = goalSettingsEntity(id: settings.id) ?? CDNutritionGoalSettings(context: context)
        settings.apply(to: entity)
        save()
    }

    // MARK: - Plans

    /// All of the user's plans (archived included), in display order.
    func fetchNutritionPlans(userId: UUID) -> [NutritionPlan] {
        let request: NSFetchRequest<CDNutritionPlan> = CDNutritionPlan.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { NutritionPlan(from: $0) }
    }

    private func nutritionPlanEntity(id: UUID) -> CDNutritionPlan? {
        let request: NSFetchRequest<CDNutritionPlan> = CDNutritionPlan.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchNutritionPlan(id: UUID) -> NutritionPlan? {
        nutritionPlanEntity(id: id).map { NutritionPlan(from: $0) }
    }

    /// Upsert by id.
    func saveNutritionPlan(_ plan: NutritionPlan) {
        saveNutritionPlans([plan])
    }

    /// Upserts several plans with one save.
    func saveNutritionPlans(_ plans: [NutritionPlan]) {
        guard !plans.isEmpty else { return }
        performBatch {
            for plan in plans {
                let entity = nutritionPlanEntity(id: plan.id) ?? CDNutritionPlan(context: context)
                plan.apply(to: entity)
            }
        }
    }

    // MARK: - Restore (local only, never queues)

    func restoreGoalSettings(_ settings: [NutritionGoalSettings]) {
        guard !settings.isEmpty else { return }
        performBatch {
            for item in settings {
                let entity = goalSettingsEntity(id: item.id) ?? CDNutritionGoalSettings(context: context)
                item.apply(to: entity)
            }
        }
    }

    func restoreNutritionPlans(_ plans: [NutritionPlan]) { saveNutritionPlans(plans) }
}
