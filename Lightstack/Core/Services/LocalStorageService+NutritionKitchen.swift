import Foundation
import CoreData

/// Core Data access for saved meals and recipes (`FoodCollection`) and their items.
/// Local only: `NutritionRepository` queues the cloud writes; restore uses the restore* upserts (never queue).
extension LocalStorageService {

    // MARK: - Collections

    /// All of the user's collections of a kind (or both), by name.
    func fetchFoodCollections(userId: UUID, kind: FoodCollectionKind? = nil) -> [FoodCollection] {
        let request: NSFetchRequest<CDFoodCollection> = CDFoodCollection.fetchRequest()
        if let kind {
            request.predicate = NSPredicate(format: "userId == %@ AND kind == %@", userId as CVarArg, kind.rawValue)
        } else {
            request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))]
        return ((try? context.fetch(request)) ?? []).map { FoodCollection(from: $0) }
    }

    private func foodCollectionEntity(id: UUID) -> CDFoodCollection? {
        let request: NSFetchRequest<CDFoodCollection> = CDFoodCollection.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchFoodCollection(id: UUID) -> FoodCollection? {
        foodCollectionEntity(id: id).map { FoodCollection(from: $0) }
    }

    /// Upsert by id.
    func saveFoodCollection(_ collection: FoodCollection) {
        let entity = foodCollectionEntity(id: collection.id) ?? CDFoodCollection(context: context)
        collection.apply(to: entity)
        save()
    }

    /// Deletes collections and every item inside them.
    @discardableResult
    func deleteFoodCollections(ids: Set<UUID>) -> Int {
        guard !ids.isEmpty else { return 0 }
        var count = 0
        performBatch {
            let items: NSFetchRequest<CDFoodCollectionItem> = CDFoodCollectionItem.fetchRequest()
            items.predicate = NSPredicate(format: "collectionId IN %@", Array(ids))
            ((try? context.fetch(items)) ?? []).forEach { context.delete($0) }
            for id in ids {
                guard let entity = foodCollectionEntity(id: id) else { continue }
                context.delete(entity)
                count += 1
            }
        }
        return count
    }

    // MARK: - Items

    func fetchFoodCollectionItems(collectionId: UUID) -> [FoodCollectionItem] {
        let request: NSFetchRequest<CDFoodCollectionItem> = CDFoodCollectionItem.fetchRequest()
        request.predicate = NSPredicate(format: "collectionId == %@", collectionId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { FoodCollectionItem(from: $0) }
    }

    func fetchAllFoodCollectionItems(userId: UUID) -> [FoodCollectionItem] {
        let request: NSFetchRequest<CDFoodCollectionItem> = CDFoodCollectionItem.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true), NSSortDescriptor(key: "createdAt", ascending: true)]
        return ((try? context.fetch(request)) ?? []).map { FoodCollectionItem(from: $0) }
    }

    /// Items (in any collection) that point at one of these foods.
    func fetchFoodCollectionItems(foodIds: Set<UUID>, userId: UUID) -> [FoodCollectionItem] {
        guard !foodIds.isEmpty else { return [] }
        let request: NSFetchRequest<CDFoodCollectionItem> = CDFoodCollectionItem.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@ AND foodId IN %@", userId as CVarArg, Array(foodIds))
        return ((try? context.fetch(request)) ?? []).map { FoodCollectionItem(from: $0) }
    }

    private func foodCollectionItemEntity(id: UUID) -> CDFoodCollectionItem? {
        let request: NSFetchRequest<CDFoodCollectionItem> = CDFoodCollectionItem.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    func fetchFoodCollectionItem(id: UUID) -> FoodCollectionItem? {
        foodCollectionItemEntity(id: id).map { FoodCollectionItem(from: $0) }
    }

    /// Upserts several items with one save.
    func saveFoodCollectionItems(_ items: [FoodCollectionItem]) {
        guard !items.isEmpty else { return }
        performBatch {
            for item in items {
                let entity = foodCollectionItemEntity(id: item.id) ?? CDFoodCollectionItem(context: context)
                item.apply(to: entity)
            }
        }
    }

    @discardableResult
    func deleteFoodCollectionItems(ids: Set<UUID>) -> Int {
        var count = 0
        for id in ids {
            guard let entity = foodCollectionItemEntity(id: id) else { continue }
            context.delete(entity)
            count += 1
        }
        save()
        return count
    }

    /// Deletes every item that points at one of these foods (the cloud cascades the same way). Returns the removed items.
    @discardableResult
    func deleteFoodCollectionItems(foodIds: Set<UUID>, userId: UUID) -> [FoodCollectionItem] {
        let removed = fetchFoodCollectionItems(foodIds: foodIds, userId: userId)
        deleteFoodCollectionItems(ids: Set(removed.map(\.id)))
        return removed
    }

    // MARK: - Restore (local only, never queues)

    func restoreFoodCollections(_ collections: [FoodCollection]) {
        guard !collections.isEmpty else { return }
        performBatch {
            for collection in collections {
                let entity = foodCollectionEntity(id: collection.id) ?? CDFoodCollection(context: context)
                collection.apply(to: entity)
            }
        }
    }

    func restoreFoodCollectionItems(_ items: [FoodCollectionItem]) { saveFoodCollectionItems(items) }
}
