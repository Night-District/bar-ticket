import Foundation

enum Constants {
    static let githubAPIURL = "https://api.github.com"

    // GitHub OAuth
    static let githubOAuthClientID = "Ov23liBVCZOUcDsJGC2G"
    static let githubOAuthCallbackURL = "barticket://oauth/callback"
    static let githubOAuthScopes = "repo read:project"

    /// Scopes this build of Bar Ticket needs for full Kanban functionality.
    /// A token with any of these in its X-OAuth-Scopes header is considered sufficient.
    static let requiredProjectScopes: Set<String> = ["read:project", "project"]
    static let githubOAuthProxyURL = "https://bar-ticket-oauth.loganriedley.workers.dev"

    /// File extensions to watch for TODO comments
    static let watchedExtensions: Set<String> = [
        "swift", "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs",
        "java", "kt", "kts", "c", "cpp", "cc", "h", "hpp", "m", "mm",
        "cs", "php", "scala", "ex", "exs", "erl", "hs", "lua",
        "r", "jl", "dart", "zig", "nim", "v", "sql",
        "css", "scss", "less", "html", "vue", "svelte",
        "sh", "bash", "zsh", "fish", "yml", "yaml", "toml",
        "tf", "hcl", "Dockerfile", "Makefile"
    ]

    /// Directories to ignore when watching
    static let ignoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "build", "Pods",
        "vendor", "dist", "out", ".next", ".nuxt",
        "target", "DerivedData", ".swiftpm",
        "__pycache__", ".venv", "venv", ".tox",
        "Carthage", ".sass-cache", "coverage"
    ]

    /// How long the confirmed state shows before dismissing (seconds)
    static let islandConfirmDuration: TimeInterval = 3.0

    /// How long the error state shows before dismissing (seconds)
    static let islandErrorDuration: TimeInterval = 4.0

    /// FSEvents latency in seconds
    static let fsEventsLatency: TimeInterval = 0.25

    // Claude AI
    static let claudeAPIURL = "https://api.anthropic.com/v1/messages"
    static let claudeModel = "claude-haiku-4-5-20251001"
    static let claudeAPIVersion = "2023-06-01"
    static let claudeMaxTokens = 2048
    static let claudeExpandDuration: TimeInterval = 1.0

    static let systemPrompt = """
        You are an expert software project manager who writes clear, actionable GitHub issues. \
        Given a user's raw idea or bug report and an issue template, you produce a well-structured issue. \
        Return ONLY valid JSON with exactly these keys: "title" (concise issue title as a string), \
        "body" (the full issue body in markdown following the template structure), \
        "labels" (an array of 1-3 relevant label strings like "bug", "enhancement", "documentation"). \
        Do not wrap the JSON in code fences or add any other text.
        """
}
