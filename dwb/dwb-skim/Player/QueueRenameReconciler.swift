import Foundation

struct SkimQueueItemRecord: Equatable {
    let id: String
    var url: URL
    var fileIdentity: String?
}

struct SkimQueueSnapshotItem: Equatable {
    let url: URL
    let fileIdentity: String?
}

struct SkimQueueReconciliationResult: Equatable {
    let items: [SkimQueueItemRecord]
    let displayOrder: [Int]
    let currentDisplayIndex: Int
    let selectedItemIDs: Set<String>
    let membershipChanged: Bool
    let renamedItemIDs: Set<String>

    var displayItemIDs: [String] { displayOrder.map { items[$0].id } }
}

/// Pure queue reconciliation used by filesystem refreshes. URLs are mutable
/// attributes of stable queue items; they are never treated as queue identity.
enum QueueRenameReconciler {
    static func replacingURL(in items: [SkimQueueItemRecord],
                             at index: Int,
                             with newURL: URL,
                             fileIdentity: String?) -> [SkimQueueItemRecord]? {
        guard items.indices.contains(index) else { return nil }
        var updated = items
        updated[index].url = newURL
        updated[index].fileIdentity = fileIdentity ?? updated[index].fileIdentity
        return updated
    }

    static func reconcile(currentItems: [SkimQueueItemRecord],
                          displayOrder: [Int],
                          currentDisplayIndex: Int,
                          selectedItemIDs: Set<String>,
                          snapshot: [SkimQueueSnapshotItem],
                          preservingMissingItemID: String? = nil,
                          makeID: (URL) -> String) -> SkimQueueReconciliationResult {
        var unmatchedSnapshot = Set(snapshot.indices)
        var reconciled: [SkimQueueItemRecord] = []
        var oldToNew: [Int: Int] = [:]
        var renamedIDs = Set<String>()

        for (oldIndex, item) in currentItems.enumerated() {
            let path = item.url.standardizedFileURL.path
            let exact = unmatchedSnapshot.first {
                snapshot[$0].url.standardizedFileURL.path == path
            }
            let identityMatch = exact ?? unmatchedSnapshot.first {
                guard let currentIdentity = item.fileIdentity,
                      let snapshotIdentity = snapshot[$0].fileIdentity else { return false }
                return currentIdentity == snapshotIdentity
            }

            if let match = identityMatch {
                unmatchedSnapshot.remove(match)
                let fresh = snapshot[match]
                if fresh.url.standardizedFileURL.path != path {
                    renamedIDs.insert(item.id)
                }
                oldToNew[oldIndex] = reconciled.count
                reconciled.append(SkimQueueItemRecord(
                    id: item.id,
                    url: fresh.url,
                    fileIdentity: fresh.fileIdentity ?? item.fileIdentity
                ))
            } else if item.id == preservingMissingItemID {
                oldToNew[oldIndex] = reconciled.count
                reconciled.append(item)
            }
        }

        let retainedCount = reconciled.count
        for snapshotIndex in snapshot.indices where unmatchedSnapshot.contains(snapshotIndex) {
            let fresh = snapshot[snapshotIndex]
            reconciled.append(SkimQueueItemRecord(
                id: makeID(fresh.url),
                url: fresh.url,
                fileIdentity: fresh.fileIdentity
            ))
        }

        var reconciledOrder = displayOrder.compactMap { oldToNew[$0] }
        if reconciled.count > retainedCount {
            reconciledOrder.append(contentsOf: retainedCount..<reconciled.count)
        }

        let currentID: String? = displayOrder.indices.contains(currentDisplayIndex)
            && currentItems.indices.contains(displayOrder[currentDisplayIndex])
            ? currentItems[displayOrder[currentDisplayIndex]].id
            : nil
        let newCurrentIndex = currentID.flatMap { id in
            reconciledOrder.firstIndex { reconciled[$0].id == id }
        } ?? (reconciledOrder.isEmpty ? -1 : min(max(0, currentDisplayIndex), reconciledOrder.count - 1))

        let survivingIDs = Set(reconciled.map(\.id))
        let membershipChanged = reconciled.count != currentItems.count
            || survivingIDs != Set(currentItems.map(\.id))

        return SkimQueueReconciliationResult(
            items: reconciled,
            displayOrder: reconciledOrder,
            currentDisplayIndex: newCurrentIndex,
            selectedItemIDs: selectedItemIDs.intersection(survivingIDs),
            membershipChanged: membershipChanged,
            renamedItemIDs: renamedIDs
        )
    }
}

enum SkimFileIdentityResolver {
    static func identity(for url: URL) -> String? {
        guard url.isFileURL,
              let value = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]),
              let identifier = value.fileResourceIdentifier else { return nil }
        return String(reflecting: identifier)
    }
}
