import Foundation

extension ByteCountFormatter {
    static func megabytes(_ amount: Int) -> String {
        string(fromByteCount: Int64(amount) * 1_000_000, countStyle: .file)
    }
}
