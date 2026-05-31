import XCTest
@testable import MacAppClean

final class CleanerStoreTests: XCTestCase {
    private var rootURL: URL!
    private var defaultsSuiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appending(path: "MacAppCleanStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        defaultsSuiteName = "MacAppCleanStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        rootURL = nil
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    func testDeletedTrashBatchesGroupsRecordsAndReportsRestorableStatus() throws {
        let batchID = UUID()
        let removedAt = Date(timeIntervalSince1970: 1_800)
        let originalURL = rootURL.appending(path: "Applications/Sample.app", directoryHint: .isDirectory)
        let trashURL = rootURL.appending(path: "Trash/Sample.app", directoryHint: .isDirectory)
        try makeDirectory(trashURL)
        try seedRecords([
            CleanerStore.TrashRecord(
                batchID: batchID,
                batchName: "Sample",
                originalURL: originalURL,
                trashURL: trashURL,
                removedAt: removedAt,
                size: 42
            )
        ])

        let store = CleanerStore(defaults: defaults)

        XCTAssertEqual(store.deletionHistoryCount, 1)
        XCTAssertEqual(store.restorableTrashCount, 1)
        XCTAssertEqual(store.deletedTrashBatches.count, 1)
        XCTAssertEqual(store.deletedTrashBatches[0].id, batchID)
        XCTAssertEqual(store.deletedTrashBatches[0].name, "Sample")
        XCTAssertEqual(store.deletedTrashBatches[0].statusText, "可恢复")
        XCTAssertTrue(store.deletedTrashBatches[0].canRestore)
    }

    func testRestoreDeletedBatchMovesTrashItemBackAndKeepsHistoryRecord() throws {
        let batchID = UUID()
        let originalURL = rootURL.appending(path: "Library/Application Support/Sample/config.json")
        let trashURL = rootURL.appending(path: "Trash/config.json")
        try makeFile(trashURL, contents: "configuration")
        try seedRecords([
            CleanerStore.TrashRecord(
                batchID: batchID,
                batchName: "Sample",
                originalURL: originalURL,
                trashURL: trashURL,
                removedAt: Date(timeIntervalSince1970: 2_000),
                size: 13
            )
        ])

        let store = CleanerStore(defaults: defaults)
        store.restoreDeletedBatch(id: batchID)

        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashURL.path))
        XCTAssertEqual(store.deletionHistoryCount, 1)
        XCTAssertEqual(store.restorableTrashCount, 0)
        XCTAssertEqual(store.deletedTrashBatches[0].statusText, "已恢复")

        let storedRecords = try loadStoredRecords()
        XCTAssertEqual(storedRecords.count, 1)
        XCTAssertNotNil(storedRecords[0].restoredAt)
    }

    func testDeletionAuditLogExportsComparableJSONRecordsWithStatuses() throws {
        let restorableBatchID = UUID()
        let restoredBatchID = UUID()
        let originalExistsBatchID = UUID()
        let missingBatchID = UUID()
        let restorableTrashURL = rootURL.appending(path: "Trash/Restorable.app", directoryHint: .isDirectory)
        let originalExistsURL = rootURL.appending(path: "Applications/Reinstalled.app", directoryHint: .isDirectory)
        let originalExistsTrashURL = rootURL.appending(path: "Trash/Reinstalled.app", directoryHint: .isDirectory)
        try makeDirectory(restorableTrashURL)
        try makeDirectory(originalExistsURL)
        try makeDirectory(originalExistsTrashURL)

        try seedRecords([
            CleanerStore.TrashRecord(
                batchID: restorableBatchID,
                batchName: "Restorable",
                originalURL: rootURL.appending(path: "Applications/Restorable.app", directoryHint: .isDirectory),
                trashURL: restorableTrashURL,
                removedAt: Date(timeIntervalSince1970: 3_000),
                size: 100
            ),
            restoredRecord(
                batchID: restoredBatchID,
                batchName: "Restored",
                originalURL: rootURL.appending(path: "Applications/Restored.app", directoryHint: .isDirectory),
                trashURL: rootURL.appending(path: "Trash/Restored.app", directoryHint: .isDirectory)
            ),
            CleanerStore.TrashRecord(
                batchID: originalExistsBatchID,
                batchName: "Reinstalled",
                originalURL: originalExistsURL,
                trashURL: originalExistsTrashURL,
                removedAt: Date(timeIntervalSince1970: 3_200),
                size: 300
            ),
            CleanerStore.TrashRecord(
                batchID: missingBatchID,
                batchName: "Missing",
                originalURL: rootURL.appending(path: "Applications/Missing.app", directoryHint: .isDirectory),
                trashURL: rootURL.appending(path: "Trash/Missing.app", directoryHint: .isDirectory),
                removedAt: Date(timeIntervalSince1970: 3_300),
                size: 400
            )
        ])
        let exportURL = rootURL.appending(path: "audit.json")

        let store = CleanerStore(defaults: defaults)
        try store.exportDeletionAuditLog(to: exportURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(UninstallAuditLog.self, from: Data(contentsOf: exportURL))
        let statusesByName = Dictionary(uniqueKeysWithValues: exported.records.map { ($0.batchName, $0.status) })

        XCTAssertEqual(exported.schemaVersion, 1)
        XCTAssertEqual(exported.appName, "MacAppClean")
        XCTAssertEqual(exported.records.count, 4)
        XCTAssertEqual(statusesByName["Restorable"], .restorable)
        XCTAssertEqual(statusesByName["Restored"], .restored)
        XCTAssertEqual(statusesByName["Reinstalled"], .originalExists)
        XCTAssertEqual(statusesByName["Missing"], .missingFromTrash)
        XCTAssertTrue(exported.records.allSatisfy { !$0.originalPath.isEmpty && !$0.trashPath.isEmpty })
    }

    private func restoredRecord(batchID: UUID, batchName: String, originalURL: URL, trashURL: URL) -> CleanerStore.TrashRecord {
        var record = CleanerStore.TrashRecord(
            batchID: batchID,
            batchName: batchName,
            originalURL: originalURL,
            trashURL: trashURL,
            removedAt: Date(timeIntervalSince1970: 3_100),
            size: 200
        )
        record.restoredAt = Date(timeIntervalSince1970: 3_150)
        return record
    }

    private func seedRecords(_ records: [CleanerStore.TrashRecord]) throws {
        let data = try JSONEncoder().encode(records)
        defaults.set(data, forKey: CleanerStore.trashRecordsKey)
    }

    private func loadStoredRecords() throws -> [CleanerStore.TrashRecord] {
        let data = try XCTUnwrap(defaults.data(forKey: CleanerStore.trashRecordsKey))
        return try JSONDecoder().decode([CleanerStore.TrashRecord].self, from: data)
    }

    private func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
