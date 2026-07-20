/// A fixed-capacity FIFO buffer with O(1) append and eviction.
///
/// Entries are returned in chronological order. The buffer never grows beyond
/// its configured capacity, including between UI render passes.
struct DebugLogRetentionBuffer<Element> {
    private let capacity: Int
    private var storage: [Element] = []
    private var oldestIndex = 0

    init(capacity: Int) {
        precondition(capacity > 0, "Debug log retention capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    var count: Int { storage.count }

    var entries: [Element] {
        guard storage.count == capacity, oldestIndex != 0 else { return storage }
        return Array(storage[oldestIndex...]) + Array(storage[..<oldestIndex])
    }

    mutating func append(_ entry: Element) {
        if storage.count < capacity {
            storage.append(entry)
        } else {
            storage[oldestIndex] = entry
            oldestIndex = (oldestIndex + 1) % capacity
        }
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        oldestIndex = 0
    }
}
