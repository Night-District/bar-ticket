---
branch: feat/update-issue
description: Detect when an already-issued TODO is edited and update the existing GitHub issue instead of creating a new one
date: 2026-04-07
scope: app-only
technical_approach: TodoParser extracts embedded (#N url) references from TODO comments to identify known TODOs; body change detection triggers a PATCH call to GitHubClient; identity is issueNumber + repoFullName, not filePath + lineNumber
---

# feat/update-issue — Update Existing GitHub Issue on TODO Edit

## Feature Summary

When a user edits a TODO that already has a corresponding GitHub issue, Bar Ticket detects the edit and updates the existing issue via PATCH rather than creating a duplicate.

## User Value

Prevents issue spam. A developer who iterates on a TODO's wording (clarifying scope, adding context) shouldn't end up with two half-baked issues. The canonical issue stays current with the latest thinking and the source file always reflects one authoritative issue reference.

---

## How the Current Pipeline Works (and Where It Breaks)

1. `FileWatcher.handleFileEvent` reads the current file and calls `TodoParser.findNewTodos`.
2. `findNewTodos` hashes the stripped TODO content and filters out anything whose hash is in `seenHashes`.
3. A hash match means "already processed" — the TODO is silently dropped.
4. When a TODO's text changes, its hash changes. The new hash is not in `seenHashes`, so it passes through as a **brand new** TODO and a second issue is created.

The system has no concept of "this is the same TODO, just with different content."

---

## Identity Model

After `createIssue` succeeds, `appendIssueReference` writes a `(#N url)` suffix back into the TODO comment. A TODO in source then looks like:

```swift
// TODO: Fix this thing (#123 https://github.com/owner/repo/issues/123)
```

This embedded reference is the identity anchor. `TodoParser` detects it during parsing and extracts:

- **`issueNumber`** (Int) — from `#N`
- **`repoFullName`** (String, e.g. `"owner/repo"`) — parsed from the URL path

A TODO that carries this reference is a **known TODO**. It is matched against `SeenTodo` by `issueNumber + repoFullName` — a true unique identifier, since issue numbers within a GitHub repo are non-reusable.

A TODO without this reference is a **new TODO** — the existing `createIssue` flow is unchanged.

### Why this is better than filePath + lineNumber

- Immune to line number drift — the reference travels with the TODO text regardless of insertions above it.
- Immune to file moves and renames — same reason.
- `issueNumber + repoFullName` is globally unambiguous within the app's scope.
- No fuzzy matching or proximity search needed.

### Manual removal edge case

If a user manually deletes the `(#N url)` suffix from a TODO, Bar Ticket loses the identity anchor and treats the TODO as new. A second GitHub issue is created. This is acceptable degradation — the user has explicitly removed the reference. The old `SeenTodo` record remains in SwiftData with the original hash; since the hash of the stripped TODO text is now different, no hash collision occurs.

---

## Technical Components Affected

| Component | Change |
|---|---|
| `TodoParser` | Detect `(#N url)` suffix in TODO comment body; extract `issueNumber` and `repoFullName`; expose on `ParsedTodo`; new method `findUpdatedTodos` that identifies known TODOs with changed body text |
| `FileWatcher` | New `onTodoUpdated` callback; call `findUpdatedTodos` alongside `findNewTodos` in `handleFileEvent` |
| `GitHubClient` | New `updateIssue` method (PATCH `/repos/{owner}/{repo}/issues/{number}`) |
| `AppDelegate` | Wire `onTodoUpdated` callback; new `handleUpdatedTodo` pipeline method; update `SeenTodo` record in SwiftData after successful PATCH |
| `IslandState` | New `.updating` state (mirrors `.creating` visually but with distinct label) |
| `SeenTodo` | No model changes needed — existing `issueNumber`, `repoFullName`, `contentHash` fields are sufficient; `contentHash` updated after successful PATCH |

---

## Implementation Tasks

### Task 1 — Extend `ParsedTodo` and `TodoParser` to detect embedded references (small)

**File:** `BarTicket/Services/TodoParser.swift`

Extend `ParsedTodo` with two optional fields:

```swift
struct ParsedTodo {
    // ... existing fields ...
    var issueNumber: Int?        // present if TODO carries (#N url)
    var repoFullName: String?    // e.g. "owner/repo", parsed from embedded URL
    var bodyWithoutReference: String  // TODO body text with (#N url) suffix stripped
}
```

In the parsing logic, after extracting the TODO comment body, apply a second regex to detect the trailing `(#N url)` pattern:

```
\(#(\d+)\s+https://github\.com/([^/]+/[^/]+)/issues/\d+\)
```

If matched:
- Set `issueNumber` and `repoFullName` from captures.
- Set `bodyWithoutReference` to the body with the match removed and whitespace trimmed.

If not matched:
- `issueNumber` and `repoFullName` remain nil.
- `bodyWithoutReference` equals the full body.

The content hash used for deduplication should be computed from `bodyWithoutReference`, not the full body. This ensures that after `appendIssueReference` writes the suffix back to the file, the hash of the stripped body still matches the original `SeenTodo.contentHash` — preventing the reference-append from being treated as a new TODO.

---

### Task 2 — Add `UpdatedTodo` struct and `findUpdatedTodos` to TodoParser (small)

**File:** `BarTicket/Services/TodoParser.swift`

Add a new public struct alongside `ParsedTodo`:

```swift
struct UpdatedTodo {
    let old: SeenTodo     // the persisted record being replaced
    let new: ParsedTodo   // the freshly parsed content (with embedded reference detected)
}
```

Add a new static method `findUpdatedTodos`:

```swift
static func findUpdatedTodos(
    currentContent: String,
    filePath: String,
    seenTodos: [SeenTodo]   // only those with issueNumber != nil
) -> [UpdatedTodo]
```

Logic:
1. Call `parseTodos(from: currentContent, filePath: filePath)` to get all current TODOs.
2. Filter results to only those where `parsedTodo.issueNumber != nil`.
3. For each such TODO, attempt to find a matching `SeenTodo` where `seenTodo.issueNumber == parsedTodo.issueNumber && seenTodo.repoFullName == parsedTodo.repoFullName`.
4. If a match is found and `parsedTodo.bodyWithoutReference` differs from `seenTodo.body` (or `seenTodo.contentHash` differs from the hash of `bodyWithoutReference`), emit an `UpdatedTodo`.
5. If the content is unchanged, it is a no-op — skip it.

This method is purely functional with no side effects.

---

### Task 3 — Extend FileWatcher with `onTodoUpdated` callback (small)

**File:** `BarTicket/Services/FileWatcher.swift`

Add a stored property and callback:

```swift
/// Called when an existing TODO's content changes (identified by embedded #N reference)
var onTodoUpdated: ((UpdatedTodo) -> Void)?
```

Modify `handleFileEvent` to call `TodoParser.findUpdatedTodos` after the existing `findNewTodos` call, passing the relevant `SeenTodo` records (those with `issueNumber != nil`). Emit each result via `onTodoUpdated`.

The `seenTodos` lookup requires access to the current SwiftData state. The cleanest approach is to pass a `seenTodosProvider: () -> [SeenTodo]` closure at initialization time (same pattern as any existing `seenHashes` refresh mechanism in the watcher). Alternatively, `AppDelegate` can maintain a local cache keyed by `issueNumber + repoFullName` and inject it into the watcher after each successful create/update.

---

### Task 4 — Add `updateIssue` to GitHubClient (small)

**File:** `BarTicket/Services/GitHubClient.swift`

Add a static method:

```swift
static func updateIssue(
    owner: String,
    repo: String,
    number: Int,
    title: String,
    body: String,
    token: String
) async throws -> GitHubIssueResponse
```

Uses `AF.request` with `.patch` method to `PATCH /repos/{owner}/{repo}/issues/{number}` with `{"title": ..., "body": ...}`. Reuses the existing `headers(token:)` helper and the same error mapping (403 → rateLimited, 404 → repoNotFound).

The response type is the same `GitHubIssueResponse` — GitHub returns the full issue object on PATCH too.

---

### Task 5 — Add `.updating` island state (small)

**File:** `BarTicket/ViewModels/AppState.swift`

Add a new case to `IslandState`:

```swift
case updating(title: String)
```

The UI treatment is identical to `.creating` — the same gear icon animation, same label style — but the subtitle text reads "Updating issue…" instead of "Creating issue…". Update all exhaustive `switch` statements that handle `IslandState` to handle this case.

**File:** `BarTicket/Views/DynamicIslandWindow.swift` (or wherever the island renders state)

Map `.updating(title:)` to the same visual as `.creating(title:)` but with subtitle "Updating issue…".

---

### Task 6 — Wire `onTodoUpdated` callback and `handleUpdatedTodo` pipeline (medium)

**File:** `BarTicket/BarTicketApp.swift`

**In `setupFileWatcher`**, wire the new callback:

```swift
watcher.onTodoUpdated = { [weak self] updated in
    DispatchQueue.main.async {
        self?.handleUpdatedTodo(updated, context: context)
    }
}
```

**New `handleUpdatedTodo` method** (mirrors `handleNewTodo`):

```swift
@MainActor
private func handleUpdatedTodo(_ updated: UpdatedTodo, context: ModelContext)
```

Pipeline:
1. Guard `appState.isWatchingEnabled` and token present.
2. `appState.showIsland(state: .detecting(title: updated.new.title))`
3. Resolve git repo via `GitResolver.resolve(filePath: updated.new.filePath)` — or use `updated.old.repoFullName` directly (it is already stored).
4. `await Task.sleep(1.0)` — hold detecting state.
5. `appState.showIsland(state: .updating(title: updated.new.title))`
6. Record `updatingShownAt`.
7. Call `GitHubClient.updateIssue(owner:repo:number:title:body:token:)` using `updated.old.issueNumber!` and the new `updated.new.title` / `updated.new.bodyWithoutReference`.
8. Enforce minimum 1s on updating state.
9. Update the `SeenTodo` record in SwiftData:
   - Fetch by `issueNumber == updated.old.issueNumber && repoFullName == updated.old.repoFullName`.
   - Mutate `contentHash` and `body` (title if stored separately) to the new values.
   - Call `context.save()`.
10. Refresh `seenHashes` in the `FileWatcher` to include the new hash and remove the old one, so a subsequent identical save is a no-op.
11. The `(#N url)` suffix in the file is unchanged (the issue number hasn't changed), so no re-append is needed.
12. `appState.showIsland(state: .confirmed(...))` reusing the existing issue number and URL from `updated.old`.
13. On error: `appState.showIsland(state: .error(message:))`.

Note: do **not** call `addRecentIssue` — the issue already exists. Optionally update its title in the `recentIssues` array (nice-to-have, not required for v1).

---

### Task 7 — Ensure `appendIssueReference` does not re-trigger update detection (small)

After `createIssue` succeeds, `appendIssueReference` writes the `(#N url)` suffix back to the source file. This triggers another FSEvent. The updated TODO now has an embedded reference, and its `bodyWithoutReference` hash must match the original `SeenTodo.contentHash`.

This is guaranteed by Task 1: the content hash is computed from `bodyWithoutReference` (the text without the suffix). So when the re-parse happens after `appendIssueReference`, the hash of the stripped body equals the stored hash, and `findUpdatedTodos` sees no change — no update fires.

Verify this behavior explicitly in testing (see Task in Testing Strategy below).

---

## Data Flow Diagram

```
FSEvent fires
    └─> FileWatcher.handleFileEvent(path)
            ├─> TodoParser.findNewTodos(...)
            │       (TODO has no embedded reference → new issue)
            │       → onTodoDetected → handleNewTodo (existing)
            │               └─> createIssue → appendIssueReference writes (#N url)
            │
            └─> TodoParser.findUpdatedTodos(...)
                    (TODO has embedded (#N url), body text changed → update)
                    → onTodoUpdated → handleUpdatedTodo (new)
                            └─> GitHubClient.updateIssue(PATCH)
                                    └─> SeenTodo.contentHash updated in SwiftData
                                            └─> IslandState.confirmed (same issue number)
```

---

## Edge Cases & Risks

| Scenario | Behavior |
|---|---|
| User manually removes `(#N url)` suffix | Reference anchor is gone. Bar Ticket treats the TODO as new. A second issue is created. Acceptable degradation — the user explicitly removed the reference. |
| User edits TODO text, saves, then immediately edits again before the PATCH completes | The second FSEvent fires while the first PATCH is in-flight. The island state is overwritten. The second PATCH updates the issue again. Both PATCHes may succeed; the second wins. Acceptable for v1. |
| User deletes a TODO entirely | No embedded-reference TODO at that `issueNumber`. No update fires. The `SeenTodo` record remains in SwiftData. If the exact same text (with reference) is re-added, hash match prevents re-creation. Existing behavior, acceptable. |
| User edits TODO back to its original body text | `bodyWithoutReference` hash reverts to the original `SeenTodo.contentHash`. `findUpdatedTodos` sees a match with no change — no update fires. Correct no-op behavior. |
| `SeenTodo` has `issueNumber == nil` (creation failed mid-way) | `findUpdatedTodos` filters for `issueNumber != nil`. These records are excluded. The TODO will be treated as new on the next edit, which is the correct fallback. |
| Multiple TODOs with embedded references in the same file | Each is identified independently by its `issueNumber + repoFullName`. Multiple changes in one save event fire separate `onTodoUpdated` callbacks and trigger separate PATCHes. |
| PATCH fails with 404 (issue was manually deleted on GitHub) | Existing `GitHubClientError.repoNotFound` error path shows an error island state. The `SeenTodo` record is not updated. Subsequent edits will attempt to PATCH again. The user can resolve by manually deleting the `(#N url)` suffix, which degrades to new-issue creation. |
| Same issue number appears in two repos (different `repoFullName`) | `issueNumber + repoFullName` composite key distinguishes them correctly. No collision. |

---

## Testing Strategy

1. **Unit test `TodoParser` embedded reference detection**: verify that a TODO with `(#N url)` suffix correctly extracts `issueNumber`, `repoFullName`, and `bodyWithoutReference`. Verify a TODO without the suffix has nil `issueNumber` and `bodyWithoutReference` equals the full body.

2. **Unit test `TodoParser.findUpdatedTodos`**: with a mock `SeenTodo` array, verify it correctly identifies a changed body for a known `issueNumber + repoFullName`, ignores TODOs with unchanged body, and ignores TODOs without an embedded reference.

3. **Integration test hash stability after `appendIssueReference`**:
   - Add a TODO to a watched file → issue created → `appendIssueReference` writes suffix.
   - Confirm the resulting FSEvent does not trigger a second create or a spurious update.
   - Verify that the stripped-body hash equals the `SeenTodo.contentHash` stored during creation.

4. **Integration test the full update pipeline**:
   - Add a TODO → confirm issue is created with reference suffix.
   - Edit the TODO body text (keep the `(#N url)` suffix) → confirm island shows detecting → updating → confirmed with the same issue number.
   - Verify the GitHub issue title and body were updated on the GitHub side.
   - Verify no second issue was created.
   - Save the file again without changes → confirm no island activity.

5. **Test manual reference removal**: remove the `(#N url)` suffix from a TODO, save → confirm a new issue is created (degraded behavior, expected).

6. **Test on both notched and non-notched Macs** to confirm `.updating` island state renders and dismisses correctly.

7. **Test PATCH failure handling**: use a revoked token or deleted issue to confirm the error island state appears and `SeenTodo` is not mutated.

---

## Out of Scope (Future Improvements)

- Closing a GitHub issue when a TODO is deleted
- Re-opening a closed issue when a matching TODO reappears
- Detecting reference removal and prompting the user
- Updating the issue reference annotation if the issue URL changes (it won't — GitHub issue URLs are permanent)

---

## Git Workflow

**Branch:** `feat/update-issue`

**Suggested commit sequence:**
```
extend ParsedTodo with issueNumber, repoFullName, bodyWithoutReference; hash from stripped body
add UpdatedTodo struct; implement findUpdatedTodos in TodoParser
add updateIssue PATCH method to GitHubClient
add .updating case to IslandState; update island view
extend FileWatcher with onTodoUpdated callback
wire handleUpdatedTodo pipeline in BarTicketApp; update SeenTodo on PATCH success
```
