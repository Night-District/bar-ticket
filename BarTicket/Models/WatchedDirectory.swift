import Foundation
import SwiftData

@Model
final class WatchedDirectory {
    var path: String
    var isEnabled: Bool
    var addedAt: Date

    init(path: String, isEnabled: Bool = true) {
        self.path = path
        self.isEnabled = isEnabled
        self.addedAt = Date()
    }

    /// Display-friendly path with ~ for home directory
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
