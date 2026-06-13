import Foundation

struct UninstallAuditLog: Codable, Equatable {
    var schemaVersion: Int
    var appName: String
    var generatedAt: Date
    var records: [Record]

    struct Record: Codable, Equatable {
        var id: UUID
        var batchID: UUID
        var batchName: String
        var originalPath: String
        var trashPath: String
        var removedAt: Date
        var restoredAt: Date?
        var size: Int64
        var status: Status
    }

    enum Status: String, Codable, Equatable {
        case restorable
        case restored
        case originalExists
        case missingFromTrash
    }
}
