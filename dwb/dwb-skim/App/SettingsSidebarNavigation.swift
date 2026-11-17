import Foundation

enum SettingsSidebarNavigation {
    static func adjacentIndex(from index: Int, direction: Int, count: Int) -> Int? {
        guard direction == -1 || direction == 1, (0..<count).contains(index) else { return nil }
        let next = index + direction
        return (0..<count).contains(next) ? next : nil
    }
}
