import Foundation

enum QueueOrderMode: String, CaseIterable, Equatable {
    case sequential
    case shuffle
    case weighted
}

struct QueueOrderPlannerItem: Equatable {
    let id: String
    let displayName: String
    let lastPlayedOrdinal: Int?

    init(id: String, displayName: String, lastPlayedOrdinal: Int? = nil) {
        self.id = id
        self.displayName = displayName
        self.lastPlayedOrdinal = lastPlayedOrdinal
    }
}

enum QueueOrderPlanner {
    typealias RandomInt = (_ upperBound: Int) -> Int

    static func cycleOrder(mode: QueueOrderMode,
                           items: [QueueOrderPlannerItem],
                           currentID: String? = nil,
                           avoidingFirstID: String? = nil,
                           randomInt: RandomInt) -> [Int] {
        guard !items.isEmpty else { return [] }

        let ordered: [Int]
        switch mode {
        case .sequential:
            ordered = Array(items.indices)
        case .shuffle:
            ordered = shuffled(indices: Array(items.indices), randomInt: randomInt)
        case .weighted:
            ordered = waited(indices: Array(items.indices), items: items)
        }

        return adjusted(order: ordered, items: items, currentID: currentID, avoidingFirstID: avoidingFirstID)
    }

    private static func adjusted(order: [Int],
                                 items: [QueueOrderPlannerItem],
                                 currentID: String?,
                                 avoidingFirstID: String?) -> [Int] {
        var adjusted = order

        if let currentID,
           let position = adjusted.firstIndex(where: { items[$0].id == currentID }) {
            let current = adjusted.remove(at: position)
            adjusted.insert(current, at: 0)
        }

        if currentID == nil,
           let avoidingFirstID,
           adjusted.count > 1,
           let first = adjusted.first,
           items[first].id == avoidingFirstID,
           let swapIndex = adjusted.indices.dropFirst().first {
            adjusted.swapAt(0, swapIndex)
        }

        return adjusted
    }

    private static func shuffled(indices: [Int], randomInt: RandomInt) -> [Int] {
        guard indices.count > 1 else { return indices }
        var result = indices
        for index in stride(from: result.count - 1, through: 1, by: -1) {
            let swapIndex = boundedRandom(randomInt(index + 1), upperBound: index + 1)
            if index != swapIndex {
                result.swapAt(index, swapIndex)
            }
        }
        return result
    }

    private static func waited(indices: [Int], items: [QueueOrderPlannerItem]) -> [Int] {
        indices.sorted { lhs, rhs in
            switch (items[lhs].lastPlayedOrdinal, items[rhs].lastPlayedOrdinal) {
            case (nil, nil):
                return lhs < rhs
            case (nil, _?):
                return true
            case (_?, nil):
                return false
            case let (left?, right?):
                if left != right { return left < right }
                return lhs < rhs
            }
        }
    }

    private static func boundedRandom(_ value: Int, upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        let modulo = value % upperBound
        return modulo >= 0 ? modulo : modulo + upperBound
    }
}
