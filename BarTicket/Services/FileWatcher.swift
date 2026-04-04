import Foundation
import SwiftData

/// Watches directories for file changes and detects new TODO: comments
final class FileWatcher {

    private var streams: [FSEventStreamRef] = []
    private let queue = DispatchQueue(label: "com.nightdistrict.bar-ticket.filewatcher", qos: .utility)
    private var fileCache: [String: String] = [:] // filePath → lastKnownContent
    private var seenHashes: Set<String> = []
    private var isRunning = false

    /// Called when a new TODO is detected
    var onTodoDetected: ((ParsedTodo) -> Void)?

    // MARK: - Lifecycle

    func startWatching(directories: [String], performInitialScan: Bool = false) {
        stopWatching()

        if performInitialScan {
            // Scan synchronously on the watcher queue BEFORE starting streams
            // so the cache is populated before any events fire
            queue.sync {
                for dir in directories {
                    scanDirectory(dir)
                }
            }
            print("[BarTicket] Initial scan complete. Cached \(fileCache.count) files, \(seenHashes.count) existing TODOs")
        }

        for dir in directories {
            guard FileManager.default.fileExists(atPath: dir) else {
                print("[BarTicket] Directory does not exist, skipping: \(dir)")
                continue
            }
            startStream(for: dir)
        }
        isRunning = true
        print("[BarTicket] FSEvents streams started for \(streams.count) directory(ies)")
    }

    func stopWatching() {
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
        isRunning = false
    }

    func loadSeenHashes(_ hashes: Set<String>) {
        seenHashes = hashes
    }

    func addSeenHash(_ hash: String) {
        seenHashes.insert(hash)
    }

    // MARK: - Initial Scan

    private func scanDirectory(_ directory: String) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: directory),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            let path = url.path()

            // Skip ignored directories
            let pathComponents = Set(url.pathComponents)
            if !Constants.ignoredDirectories.isDisjoint(with: pathComponents) {
                enumerator.skipDescendants()
                continue
            }

            // Only process watched file extensions
            guard Constants.watchedExtensions.contains(url.pathExtension.lowercased()) else {
                continue
            }

            // Cache the file content (marks all existing TODOs as "known")
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                fileCache[path] = content
                // Also hash all existing TODOs so they're marked as seen
                let existingTodos = TodoParser.parseTodos(from: content, filePath: path)
                for todo in existingTodos {
                    seenHashes.insert(todo.contentHash)
                }
            }
        }
    }

    // MARK: - FSEvents

    private func startStream(for directory: String) {
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let paths = [directory] as CFArray

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventsCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Constants.fsEventsLatency,
            UInt32(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        streams.append(stream)
    }

    /// Process a file change event
    fileprivate func handleFileEvent(path: String) {
        let url = URL(fileURLWithPath: path)

        // Skip non-code files
        let ext = url.pathExtension.lowercased()
        guard Constants.watchedExtensions.contains(ext) else { return }

        // Skip ignored directories
        let pathComponents = Set(url.pathComponents)
        guard Constants.ignoredDirectories.isDisjoint(with: pathComponents) else { return }

        // Read current content
        guard let currentContent = try? String(contentsOfFile: path, encoding: .utf8) else {
            print("[BarTicket] Could not read file: \(path)")
            return
        }

        let previousContent = fileCache[path]
        let hadPrevious = previousContent != nil

        // Find new TODOs
        let newTodos = TodoParser.findNewTodos(
            currentContent: currentContent,
            previousContent: previousContent,
            filePath: path,
            seenHashes: seenHashes
        )

        // Update cache
        fileCache[path] = currentContent

        if !newTodos.isEmpty {
            print("[BarTicket] Found \(newTodos.count) new TODO(s) in \(path) (had previous cache: \(hadPrevious))")
        }

        // Notify for each new TODO
        for todo in newTodos {
            seenHashes.insert(todo.contentHash)
            DispatchQueue.main.async { [weak self] in
                self?.onTodoDetected?(todo)
            }
        }
    }
}

// MARK: - FSEvents C Callback

private func fsEventsCallback(
    _ streamRef: ConstFSEventStreamRef,
    _ clientCallBackInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()

    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    for i in 0..<numEvents {
        let flags = eventFlags[i]
        let path = paths[i]

        // Only process file modifications (not directory events, renames, etc.)
        let isFile = flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0
        let isModified = flags & UInt32(kFSEventStreamEventFlagItemModified) != 0
        let isCreated = flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0

        if isFile && (isModified || isCreated) {
            watcher.handleFileEvent(path: path)
        }
    }
}
