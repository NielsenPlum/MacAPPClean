import Foundation

extension ByteCountFormatter {
    static func megabytes(_ amount: Int) -> String {
        string(fromByteCount: Int64(amount) * 1_000_000, countStyle: .file)
    }
}

extension URL {
    var deletingPathExtensionIfApp: URL {
        pathExtension == "app" ? deletingPathExtension() : self
    }
}
