import XCTest

/// P37 — folder drag-and-drop auto-shuffle decision seam.
final class SkimFolderDropShuffleTests: XCTestCase {

    // MARK: - Folder / mixed drops → request Shuffle

    func testFolderOnlyDropWithMediaRequestsShuffle() {
        XCTAssertTrue(SkimFolderDropShuffle.shouldRequestShuffle(
            isDragAndDrop: true,
            droppedContainedDirectory: true,
            acceptedMediaCount: 5))
    }

    func testMixedFolderAndFilesDropWithMediaRequestsShuffle() {
        // Mixed drops are treated as folder drops when a directory is present.
        XCTAssertTrue(SkimFolderDropShuffle.shouldRequestShuffle(
            isDragAndDrop: true,
            droppedContainedDirectory: true,
            acceptedMediaCount: 1))
    }

    // MARK: - File-only drops → no Queue Order change

    func testFileOnlyDropDoesNotRequestShuffle() {
        XCTAssertFalse(SkimFolderDropShuffle.shouldRequestShuffle(
            isDragAndDrop: true,
            droppedContainedDirectory: false,
            acceptedMediaCount: 8))
    }

    // MARK: - Failed / empty folder drops → no Queue Order change

    func testFolderDropWithNoAcceptedMediaDoesNotRequestShuffle() {
        XCTAssertFalse(SkimFolderDropShuffle.shouldRequestShuffle(
            isDragAndDrop: true,
            droppedContainedDirectory: true,
            acceptedMediaCount: 0))
    }

    // MARK: - Non-drag-and-drop intake (Open File / Open Folder) → never affected

    func testOpenFolderPathDoesNotRequestShuffle() {
        XCTAssertFalse(SkimFolderDropShuffle.shouldRequestShuffle(
            isDragAndDrop: false,
            droppedContainedDirectory: true,
            acceptedMediaCount: 5))
    }

    // MARK: - Authoritative Queue Order setter behaviour reused by P37

    private func makeStore(_ label: String) -> (UserDefaults, SkimSettingsStore, NotificationCenter, String) {
        let suite = "com.dwb.skimTests.SkimFolderDropShuffle.\(label)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)
        let center = NotificationCenter()
        return (defaults, SkimSettingsStore(defaults: defaults, notificationCenter: center), center, suite)
    }

    func testExistingShuffleSelectionPathPersistsAndNotifies() {
        let (defaults, store, center, suite) = makeStore("shuffle")
        defer { defaults.removePersistentDomain(forName: suite) }

        var posts = 0
        let token = center.addObserver(
            forName: .queueBehaviorSettingsChanged, object: nil, queue: nil) { _ in posts += 1 }
        defer { center.removeObserver(token) }

        store.setQueueOrderMode(.shuffle)

        XCTAssertEqual(store.snapshot().queueOrderMode, .shuffle)
        XCTAssertEqual(posts, 1)
    }

    func testSequentialAndWeightedAreLeftUntouchedWhenNoShuffleRequested() {
        for mode in [QueueOrderMode.sequential, .weighted] {
            let (defaults, store, _, suite) = makeStore("mode.\(mode.rawValue)")
            defer { defaults.removePersistentDomain(forName: suite) }

            store.setQueueOrderMode(mode)

            // A direct-file drop does not request a change …
            XCTAssertFalse(SkimFolderDropShuffle.shouldRequestShuffle(
                isDragAndDrop: true,
                droppedContainedDirectory: false,
                acceptedMediaCount: 4))
            // … so the mode the user chose is still in effect.
            XCTAssertEqual(store.snapshot().queueOrderMode, mode)
        }
    }
}
