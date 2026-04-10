import Foundation

struct RepoInfo: Hashable {
    let owner: String
    let repo: String
    let rootPath: String

    var fullName: String { "\(owner)/\(repo)" }
}

enum GitResolverError: LocalizedError {
    case notGitRepository
    case noRemoteConfigured
    case remoteNotGitHub
    case invalidGitHubURL
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notGitRepository:
            return "File is not in a git repository"
        case .noRemoteConfigured:
            return "Git remote 'origin' is not configured"
        case .remoteNotGitHub:
            return "Remote 'origin' is not a GitHub repository"
        case .invalidGitHubURL:
            return "Unable to parse owner/repo from GitHub URL"
        case .unknown(let message):
            return message
        }
    }
}

enum GitResolver {

    /// Cache resolved repos by git root path
    private static var cache: [String: RepoInfo] = [:]

    /// Find the git repo root and GitHub remote for a file path
    static func resolve(filePath: String) throws -> RepoInfo {
        // Find .git root
        guard let root = findGitRoot(from: filePath) else {
            throw GitResolverError.notGitRepository
        }

        // Check cache
        if let cached = cache[root] { return cached }

        // Parse remote origin
        guard let remoteURL = getRemoteURL(repoRoot: root) else {
            throw GitResolverError.noRemoteConfigured
        }

        let info = try parseGitHubURL(remoteURL, rootPath: root)

        cache[root] = info
        return info
    }

    /// Walk up directories to find .git
    private static func findGitRoot(from path: String) -> String? {
        var current = (path as NSString).deletingLastPathComponent

        while current != "/" {
            let gitDir = (current as NSString).appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: gitDir) {
                return current
            }
            current = (current as NSString).deletingLastPathComponent
        }

        return nil
    }

    /// Run `git remote get-url origin`
    private static func getRemoteURL(repoRoot: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoRoot, "remote", "get-url", "origin"]
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parse GitHub owner/repo from remote URL
    ///
    /// Supports:
    /// - `https://github.com/owner/repo.git`
    /// - `https://github.com/owner/repo`
    /// - `git@github.com:owner/repo.git`
    /// - `ssh://git@github.com/owner/repo.git`
    private static func parseGitHubURL(_ url: String, rootPath: String) throws -> RepoInfo {
        let cleaned = url
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // SSH format: git@github.com:owner/repo
        if cleaned.hasPrefix("git@github.com:") {
            let path = String(cleaned.dropFirst("git@github.com:".count))
            let parts = path.split(separator: "/")
            guard parts.count == 2 else { throw GitResolverError.invalidGitHubURL }
            return RepoInfo(
                owner: String(parts[0]),
                repo: String(parts[1]),
                rootPath: rootPath
            )
        }

        // HTTPS format or SSH with scheme
        guard let parsed = URL(string: cleaned),
              parsed.host()?.contains("github.com") == true else {
            throw GitResolverError.invalidGitHubURL
        }

        let pathComponents = parsed.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { throw GitResolverError.invalidGitHubURL }

        return RepoInfo(
            owner: pathComponents[0],
            repo: pathComponents[1],
            rootPath: rootPath
        )
    }

    /// Clear the cache (useful when directories change)
    static func clearCache() {
        cache.removeAll()
    }
}
