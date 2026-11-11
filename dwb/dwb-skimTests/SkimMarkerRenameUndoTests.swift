import XCTest

final class SkimMarkerRenameUndoTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/markers").appendingPathComponent(name)
    }

    private func move(_ from: String, _ to: String) -> SkimMarkerRenameMove {
        SkimMarkerRenameMove(source: url(from), destination: url(to))
    }

    /// A fake file system: the set of paths that exist.
    private func exists(_ names: [String]) -> (String) -> Bool {
        let paths = Set(names.map { url($0).path })
        return { paths.contains($0) }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkimMarkerRenameUndoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Single file

    func testSingleFileUndoPlansInverseRename() {
        var slot = SkimMarkerRenameUndoSlot()
        slot.record([move("clip.mov", "select_clip.mov")])
        let step = try! XCTUnwrap(slot.step)

        let plan = SkimMarkerRenameUndoPlanner.inversePlan(for: step,
                                                           fileExistsAtPath: exists(["select_clip.mov"]))

        XCTAssertEqual(plan, .success([move("select_clip.mov", "clip.mov")]))
    }

    func testSingleFileUndoRenamesFileBackOnDisk() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("clip.mov")
        let renamed = dir.appendingPathComponent("select_clip.mov")
        FileManager.default.createFile(atPath: renamed.path, contents: Data("x".utf8))

        let step = SkimMarkerRenameUndoStep(moves: [SkimMarkerRenameMove(source: original, destination: renamed)])
        let plan = try SkimMarkerRenameUndoPlanner.inversePlan(for: step).get()
        let result = SkimMarkerRenameUndoPlanner.perform(plan)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.completed, [SkimMarkerRenameMove(source: renamed, destination: original)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

    // MARK: - Multiple files, all or nothing

    func testMultiFileRenameIsOneStepAndUndoesAllFilesTogether() {
        var slot = SkimMarkerRenameUndoSlot()
        slot.record([move("a.mov", "select_a.mov"),
                     move("b.mov", "select_b.mov"),
                     move("c.mov", "select_c.mov")])
        let step = try! XCTUnwrap(slot.step)
        XCTAssertEqual(step.moves.count, 3)

        let plan = SkimMarkerRenameUndoPlanner.inversePlan(
            for: step,
            fileExistsAtPath: exists(["select_a.mov", "select_b.mov", "select_c.mov"]))

        guard case .success(let moves) = plan else { return XCTFail("expected a plan") }
        XCTAssertEqual(Set(moves.map(\.destination.lastPathComponent)), ["a.mov", "b.mov", "c.mov"])
        XCTAssertEqual(Set(moves.map(\.source.lastPathComponent)), ["select_a.mov", "select_b.mov", "select_c.mov"])
    }

    func testMultiFileUndoRenamesNoneWhenAnyCheckFails() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = ["a.mov", "b.mov", "c.mov"]
        var moves: [SkimMarkerRenameMove] = []
        for name in names {
            let renamed = dir.appendingPathComponent("select_" + name)
            FileManager.default.createFile(atPath: renamed.path, contents: Data())
            moves.append(SkimMarkerRenameMove(source: dir.appendingPathComponent(name), destination: renamed))
        }
        // The last file's old name has been taken since the rename.
        FileManager.default.createFile(atPath: dir.appendingPathComponent("c.mov").path, contents: Data())

        let plan = SkimMarkerRenameUndoPlanner.inversePlan(for: SkimMarkerRenameUndoStep(moves: moves))

        XCTAssertEqual(plan, .failure(.originalNameOccupied("c.mov")))
        for name in names {
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("select_" + name).path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.mov").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("b.mov").path))
    }

    // MARK: - Refusals

    func testMissingSourceRefusesUndo() {
        let step = SkimMarkerRenameUndoStep(moves: [move("a.mov", "select_a.mov"),
                                                    move("b.mov", "select_b.mov")])

        let plan = SkimMarkerRenameUndoPlanner.inversePlan(for: step,
                                                           fileExistsAtPath: exists(["select_a.mov"]))

        XCTAssertEqual(plan, .failure(.renamedFileMissing))
        XCTAssertEqual(SkimMarkerRenameUndoRefusal.renamedFileMissing.message,
                       "The renamed file could not be found.")
    }

    func testOccupiedDestinationRefusesUndo() {
        let step = SkimMarkerRenameUndoStep(moves: [move("clip.mov", "select_clip.mov")])

        let plan = SkimMarkerRenameUndoPlanner.inversePlan(
            for: step,
            fileExistsAtPath: exists(["select_clip.mov", "clip.mov"]))

        XCTAssertEqual(plan, .failure(.originalNameOccupied("clip.mov")))
        XCTAssertEqual(SkimMarkerRenameUndoRefusal.originalNameOccupied("clip.mov").message,
                       "A file named \"clip.mov\" already exists at the original location.")
    }

    // MARK: - Step lifecycle

    func testNoOpMarkerActionCreatesNoStep() {
        var slot = SkimMarkerRenameUndoSlot()
        slot.record([])
        XCTAssertFalse(slot.canUndo)

        slot.record([move("clip.mov", "clip.mov")])
        XCTAssertFalse(slot.canUndo)
        XCTAssertNil(slot.step)
    }

    func testNoOpMarkerActionDoesNotReplaceExistingStep() {
        var slot = SkimMarkerRenameUndoSlot()
        slot.record([move("a.mov", "select_a.mov")])
        slot.record([])
        slot.record([move("b.mov", "b.mov")])

        XCTAssertEqual(slot.step, SkimMarkerRenameUndoStep(moves: [move("a.mov", "select_a.mov")]))
    }

    func testNewMarkerRenameReplacesOldStep() {
        var slot = SkimMarkerRenameUndoSlot()
        slot.record([move("a.mov", "select_a.mov")])
        slot.record([move("b.mov", "later_b.mov")])

        XCTAssertEqual(slot.step, SkimMarkerRenameUndoStep(moves: [move("b.mov", "later_b.mov")]))
    }

    func testClearedStepCannotBeUndoneAgain() {
        var slot = SkimMarkerRenameUndoSlot()
        slot.record([move("a.mov", "select_a.mov")])
        XCTAssertTrue(slot.canUndo)

        slot.clear()

        XCTAssertFalse(slot.canUndo)
        XCTAssertNil(slot.step)
    }

    func testPerformStopsAtFirstFailureAndReportsCompletedMoves() {
        struct MoveFailure: Error {}
        let plan = [move("select_a.mov", "a.mov"), move("select_b.mov", "b.mov"), move("select_c.mov", "c.mov")]
        var attempted: [String] = []

        let result = SkimMarkerRenameUndoPlanner.perform(plan) { source, _ in
            attempted.append(source.lastPathComponent)
            if source.lastPathComponent == "select_b.mov" { throw MoveFailure() }
        }

        XCTAssertEqual(result.completed, [move("select_a.mov", "a.mov")])
        XCTAssertNotNil(result.error)
        XCTAssertEqual(attempted, ["select_a.mov", "select_b.mov"])
    }
}
