import Foundation

enum Constants {
    static let githubAPIURL = "https://api.github.com"

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
}
