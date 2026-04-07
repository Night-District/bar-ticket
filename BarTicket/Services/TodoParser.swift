import Foundation

struct ParsedTodo {
    let title: String
    let body: String
    let fullContent: String
    let filePath: String
    let lineNumber: Int
    let contentHash: String
    let issueNumber: Int?
    let repoFullName: String?

    /// Issue body formatted with metadata footer
    var issueBody: String {
        var result = body

        // Add file location metadata
        let relativePath = filePath
        result += "\n\n---\n"
        result += "`\(relativePath):\(lineNumber)`"

        return result
    }
}

/// Lightweight record of a TODO that already has a corresponding GitHub issue.
/// Stored in FileWatcher so update detection survives across file events without
/// requiring a SwiftData fetch on the watcher's background queue.
struct IssuedTodoRecord {
    let issueNumber: Int
    let repoFullName: String
    let contentHash: String
    let issueURL: String?
    let title: String
}

/// A TODO whose text has changed since its issue was created.
struct UpdatedTodo {
    let old: IssuedTodoRecord
    let new: ParsedTodo
}

enum TodoParser {

    /// Single-line comment prefixes by language
    private static let singleLinePrefixes = ["//", "#", "--", ";", "%"]

    /// Find new TODOs by diffing current content against previous content
    static func findNewTodos(
        currentContent: String,
        previousContent: String?,
        filePath: String,
        seenHashes: Set<String>
    ) -> [ParsedTodo] {
        let currentTodos = parseTodos(from: currentContent, filePath: filePath)

        // If no previous content, this is a first scan — all are "existing", skip them
        guard previousContent != nil else { return [] }

        // Filter to only new TODOs not in previous content and not already seen
        let previousTodos = previousContent.map {
            Set(parseTodos(from: $0, filePath: filePath).map(\.contentHash))
        } ?? Set()

        return currentTodos.filter { todo in
            !previousTodos.contains(todo.contentHash) && !seenHashes.contains(todo.contentHash)
        }
    }

    /// Parse all TODO comment blocks from file content
    static func parseTodos(from content: String, filePath: String) -> [ParsedTodo] {
        let lines = content.components(separatedBy: .newlines)
        var todos: [ParsedTodo] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            let commentPrefix = detectCommentPrefix(trimmed)
            let isInsideBlockComment = trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")

            // Strip comment prefix to get the comment body
            let commentBody: String? = {
                if let prefix = commentPrefix {
                    return String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                } else if isInsideBlockComment {
                    var body = trimmed
                    if body.hasPrefix("/*") { body = String(body.dropFirst(2)) }
                    else if body.hasPrefix("*") { body = String(body.dropFirst(1)) }
                    return body.trimmingCharacters(in: .whitespaces)
                }
                return nil
            }()

            // Match "TODO:" only at the start of the comment body (not embedded in code snippets)
            if let body = commentBody,
               body.range(of: "^TODO:", options: [.caseInsensitive, .regularExpression]) != nil {
                let todoText = String(body.dropFirst(5)).trimmingCharacters(in: .whitespaces)

                // Collect the full comment block
                var blockLines: [String] = [todoText]
                var j = i + 1

                if let prefix = commentPrefix {
                    // Collect consecutive comment lines with the same prefix
                    while j < lines.count {
                        let nextTrimmed = lines[j].trimmingCharacters(in: .whitespaces)
                        if nextTrimmed.hasPrefix(prefix) {
                            let commentContent = String(nextTrimmed.dropFirst(prefix.count))
                                .trimmingCharacters(in: .whitespaces)
                            // Stop if we hit another TODO:
                            if commentContent.range(of: "TODO:", options: .caseInsensitive) != nil {
                                break
                            }
                            // Stop if the line is an empty comment
                            if commentContent.isEmpty {
                                // Include blank lines within the block, but stop on double-blank
                                if j + 1 < lines.count {
                                    let afterNext = lines[j + 1].trimmingCharacters(in: .whitespaces)
                                    if !afterNext.hasPrefix(prefix) || afterNext == prefix {
                                        break
                                    }
                                }
                            }
                            blockLines.append(commentContent)
                        } else {
                            break
                        }
                        j += 1
                    }
                } else {
                    // Might be inside a block comment — collect until block end
                    while j < lines.count {
                        let nextTrimmed = lines[j].trimmingCharacters(in: .whitespaces)
                        if nextTrimmed.contains("*/") {
                            let beforeClose = nextTrimmed
                                .replacingOccurrences(of: "*/", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            if !beforeClose.isEmpty {
                                blockLines.append(beforeClose)
                            }
                            break
                        }
                        // Strip leading * from block comment lines
                        let cleaned = nextTrimmed.hasPrefix("*")
                            ? String(nextTrimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                            : nextTrimmed
                        if !cleaned.isEmpty {
                            blockLines.append(cleaned)
                        }
                        j += 1
                    }
                }

                // Extract issue reference from raw first line before stripping,
                // so we can identify this as a known TODO (already has an issue).
                let issueRef = extractIssueReference(blockLines.first ?? todoText)

                // Strip appended issue references before hashing so that
                // "(#42 https://...)" appended by appendIssueReference doesn't
                // produce a new hash and re-trigger issue creation.
                let strippedLines = blockLines.map(stripIssueReferences)
                let title = strippedLines.first ?? todoText
                let body = strippedLines.dropFirst().joined(separator: "\n")
                let fullContent = strippedLines.joined(separator: "\n")
                let hash = SeenTodo.hash(content: fullContent)

                guard !title.isEmpty else {
                    i += 1
                    continue
                }

                todos.append(ParsedTodo(
                    title: title,
                    body: body,
                    fullContent: fullContent,
                    filePath: filePath,
                    lineNumber: i + 1,
                    contentHash: hash,
                    issueNumber: issueRef?.issueNumber,
                    repoFullName: issueRef?.repoFullName
                ))
            }

            i += 1
        }

        return todos
    }

    /// Find TODOs whose content has changed since their issue was created.
    /// Matches by the embedded `(#N url)` reference — immune to line number drift.
    static func findUpdatedTodos(
        currentContent: String,
        filePath: String,
        issuedTodos: [IssuedTodoRecord]
    ) -> [UpdatedTodo] {
        guard !issuedTodos.isEmpty else { return [] }

        let currentTodos = parseTodos(from: currentContent, filePath: filePath)
        var updated: [UpdatedTodo] = []

        for parsed in currentTodos {
            guard let issueNumber = parsed.issueNumber,
                  let repoFullName = parsed.repoFullName else { continue }

            guard let record = issuedTodos.first(where: {
                $0.issueNumber == issueNumber && $0.repoFullName == repoFullName
            }) else { continue }

            if parsed.contentHash != record.contentHash {
                updated.append(UpdatedTodo(old: record, new: parsed))
            }
        }

        return updated
    }

    /// Extract the embedded issue reference from a TODO comment body line.
    /// Matches the `(#N https://github.com/owner/repo/issues/N)` suffix.
    private static func extractIssueReference(_ text: String) -> (issueNumber: Int, repoFullName: String)? {
        let pattern = #"\(#(\d+)\s+https://github\.com/([^/]+/[^/]+)/issues/\d+\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let repoRange = Range(match.range(at: 2), in: text),
              let number = Int(text[numRange])
        else { return nil }
        return (issueNumber: number, repoFullName: String(text[repoRange]))
    }

    /// Remove appended issue references like " (#42 https://github.com/...)" from a line.
    private static func stripIssueReferences(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\s*\(#\d+ https?://\S+\)"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
    }

    /// Detect which single-line comment prefix is used on a line
    private static func detectCommentPrefix(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in singleLinePrefixes {
            if trimmed.hasPrefix(prefix) {
                return prefix
            }
        }
        return nil
    }
}
