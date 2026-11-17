import Foundation
import XCTest

extension XCTestCase {
    /// A shortcut store on its own throwaway `UserDefaults` suite, so no test touches
    /// `UserDefaults.standard` or another test's data.
    func makeShortcutStore() -> (store: ShortcutStore, defaults: UserDefaults, suite: String) {
        let suite = "com.dwb.skimTests.shortcuts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (ShortcutStore(defaults: defaults), defaults, suite)
    }
}
