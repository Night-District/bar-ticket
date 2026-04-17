# Plan: AI-Enhanced Issue Creation

**Branch:** `feat/aiIssueCreation`
**Scope:** Large
**Status:** Ready for implementation

---

## Feature Summary

When Bar Ticket detects a new TODO comment, it calls the Claude API (claude-haiku-4-5) to classify the content, select the best-fit issue template, and generate a structured GitHub issue title, body, and labels — falling back gracefully to the raw TODO title if AI is unavailable.

---

## User Value

Raw TODO comments are typically terse ("fix auth bug", "add retry logic"). AI expansion turns those fragments into properly structured GitHub issues with a user story or bug description, acceptance criteria, and relevant labels — without the developer having to open GitHub at all. The template system (seeded from a built-in enum but extensible via SwiftData) gives teams a consistent issue format with zero manual effort.

---

## Technical Components Affected

| Component | Change Type |
|---|---|
| `Constants.swift` | Add Claude API constants, system prompt |
| `KeychainService.swift` | Add `.claudeAPIKey` keychain key |
| `Services/ClaudeClient.swift` | New service — wraps Anthropic Messages API |
| `Services/IssueTemplateService.swift` | New service — template selection & seeding |
| `Models/IssueTemplate.swift` | New SwiftData model |
| `Models/AppSettings.swift` | Add `aiEnabled: Bool` flag |
| `AppState.swift` | Add `expanding` island state |
| `DynamicIslandWindow.swift` | Handle `.expanding` state in `DynamicIslandController` |
| `BarTicketApp.swift` | Wire AI into `handleNewTodo` pipeline; seed templates on bootstrap |
| `SettingsView.swift` | Add AI section: toggle, API key field, template manager |
| `project.yml` | No changes needed (Alamofire already present) |

---

## New Island State

Add `.expanding` to `IslandState` in `AppState.swift`:

```swift
case expanding(title: String)   // AI is generating content
```

This sits between `.detecting` and `.creating` in the pipeline:

```
detecting → expanding → creating → confirmed
```

If AI is disabled or fails, `expanding` is skipped entirely:

```
detecting → creating → confirmed
```

---

## Implementation Approach

### Claude API Call

Use `URLSession` directly (not Alamofire) to keep the Claude service dependency-free and easier to unit test. The Anthropic Messages API endpoint is `POST https://api.anthropic.com/v1/messages`. The API key is stored in Keychain under a new key `.claudeAPIKey`.

The system prompt (copied verbatim from beta's `Constants.swift`, reproduced below) instructs Claude to return only valid JSON with `title`, `body`, and `labels` keys.

Request model:
```json
{
  "model": "claude-haiku-4-5",
  "max_tokens": 2048,
  "system": "<system prompt>",
  "messages": [
    {
      "role": "user",
      "content": "Raw TODO: <todo text>\n\nTemplate:\n<selected template body>"
    }
  ]
}
```

Response decoding: parse `content[0].text` as JSON, then decode into `AIIssueResult`:
```swift
struct AIIssueResult: Decodable {
    let title: String
    let body: String
    let labels: [String]
}
```

### Template Selection

`IssueTemplateService` loads all `IssueTemplate` records from SwiftData and sends their `name` and `description` fields to Claude in the user message so Claude can pick the best one. The service then looks up the chosen template by name and returns its `body` for the second (content-generation) call. This avoids sending all template bodies in every request while still letting Claude make an informed choice.

Alternative (simpler, lower latency): send the raw TODO text and all template bodies in one call. Given haiku speed, this is acceptable. **Use the single-call approach:** send the raw TODO text plus all template names and bodies in one prompt. Claude picks and applies the template in one round-trip.

### Template Storage (Hybrid Enum + SwiftData)

`BuiltInTemplates` Swift enum defines the canonical template content (same structure as beta's `BuiltInTemplates` enum). On `bootstrap()`, if the SwiftData store has zero `IssueTemplate` records, seed from the enum. This means:
- First launch: both built-in templates are inserted
- Subsequent launches: seeding is a no-op (count > 0 guard)
- Users can add custom templates through Settings — they coexist in the same store
- Built-in templates can be updated by deleting and re-seeding (future migration concern)

### Graceful Degradation

If `ClaudeClient.generateIssue(...)` throws any error, `handleNewTodo` catches it, briefly shows a `.error` island state with the message "AI unavailable — using raw TODO", waits 1.5s, then continues with the raw `todo.title` and an empty body (or a minimal body string). The GitHub issue is still created. This matches the user's choice C from the clarifying questions.

---

## Specific Tasks

### Task 1 — Add Claude API constants to `Constants.swift` [Small]

**File:** `BarTicket/Utilities/Constants.swift`

Add inside `enum Constants`:
```swift
// Claude AI
static let claudeAPIURL = "https://api.anthropic.com/v1/messages"
static let claudeModel = "claude-haiku-4-5"
static let claudeAPIVersion = "2023-06-01"
static let claudeMaxTokens = 2048
static let claudeExpandDuration: TimeInterval = 1.0  // min time in expanding state

static let systemPrompt = """
    You are an expert software project manager who writes clear, actionable GitHub issues. \
    Given a user's raw idea or bug report and an issue template, you produce a well-structured issue. \
    Return ONLY valid JSON with exactly these keys: "title" (concise issue title as a string), \
    "body" (the full issue body in markdown following the template structure), \
    "labels" (an array of 1–3 relevant label strings like "bug", "enhancement", "documentation"). \
    Do not wrap the JSON in code fences or add any other text.
    """
```

---

### Task 2 — Add `claudeAPIKey` to `KeychainService.swift` [Small]

**File:** `BarTicket/Services/KeychainService.swift`

Add to `KeychainKey` enum:
```swift
case claudeAPIKey = "com.nightdistrict.bar-ticket.claude-api-key"
```

---

### Task 3 — Create `IssueTemplate` SwiftData model [Small]

**File:** `BarTicket/Models/IssueTemplate.swift` (new)

```swift
import Foundation
import SwiftData

@Model
final class IssueTemplate {
    @Attribute(.unique) var name: String
    var templateDescription: String   // shown to Claude for selection
    var body: String                   // full markdown template body
    var isBuiltIn: Bool
    var createdAt: Date

    init(name: String, description: String, body: String, isBuiltIn: Bool = false) {
        self.name = name
        self.templateDescription = description
        self.body = body
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
    }
}
```

Note: `templateDescription` is used (not `description`) because `description` conflicts with `CustomStringConvertible` on `@Model` classes.

---

### Task 4 — Create `BuiltInTemplates` enum [Small]

**File:** `BarTicket/Utilities/BuiltInTemplates.swift` (new)

This enum contains the canonical template content copied from the beta repo. Keeping it in a separate file from `Constants.swift` avoids a growing constants file.

```swift
import Foundation

enum BuiltInTemplates: CaseIterable {
    case feature
    case bug

    var templateName: String {
        switch self {
        case .feature: return "Feature"
        case .bug:     return "Bug"
        }
    }

    var templateDescription: String {
        switch self {
        case .feature: return "A new capability, enhancement, or user-facing improvement"
        case .bug:     return "An unexpected error, crash, or incorrect behavior"
        }
    }

    var body: String {
        switch self {
        case .feature:
            return """
                # Feature Name

                ## User Story
                **As a** [user]
                **I want** [goal]
                **So that** [benefit]

                ## Acceptance Criteria
                - [ ] ...

                ## Tasks
                - [ ] ...

                ## Dependencies (Optional)
                - [ ] ...
                """
        case .bug:
            return """
                # Fix Name

                ## Bug Description
                Describe the issue and its impact.

                ## Steps to Reproduce
                1. ...

                ## Expected Behavior
                Describe what should happen instead.

                ## Tasks
                - [ ] ...
                """
        }
    }

    func toModel() -> IssueTemplate {
        IssueTemplate(name: templateName, description: templateDescription, body: body, isBuiltIn: true)
    }
}
```

---

### Task 5 — Create `ClaudeClient` service [Medium]

**File:** `BarTicket/Services/ClaudeClient.swift` (new)

This service uses `URLSession` directly (not Alamofire). It takes the raw TODO title, all available templates, picks the best template itself, and returns an `AIIssueResult`.

Key design points:
- Single API call: the user message includes the raw TODO text and all template names + bodies so Claude picks and fills in one round-trip
- Decoding: parse `content[0].text` from the Anthropic response envelope, then `JSONDecoder().decode(AIIssueResult.self, from: textData)`
- Throws `ClaudeClientError` on HTTP failures, decode failures, or missing API key

```swift
struct AIIssueResult {
    let title: String
    let body: String
    let labels: [String]
}

enum ClaudeClientError: LocalizedError {
    case noAPIKey
    case httpError(Int)
    case decodingFailed(String)
}

enum ClaudeClient {
    static func generateIssue(rawTodo: String, templates: [IssueTemplate]) async throws -> AIIssueResult
}
```

The user message format:
```
Raw developer note: "<rawTodo>"

Available templates (choose the most appropriate one and fill it in):

--- Template: Feature ---
<A new capability, enhancement, or user-facing improvement>
<feature body>

--- Template: Bug ---
<An unexpected error, crash, or incorrect behavior>
<bug body>
```

---

### Task 6 — Create `IssueTemplateService` [Small]

**File:** `BarTicket/Services/IssueTemplateService.swift` (new)

A simple namespace enum with one responsibility: seed built-in templates into SwiftData if the store is empty.

```swift
enum IssueTemplateService {
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<IssueTemplate>())) ?? 0
        guard count == 0 else { return }
        for template in BuiltInTemplates.allCases {
            context.insert(template.toModel())
        }
        try? context.save()
        print("[BarTicket] Seeded \(BuiltInTemplates.allCases.count) built-in issue templates")
    }

    static func fetchAll(context: ModelContext) -> [IssueTemplate] {
        (try? context.fetch(FetchDescriptor<IssueTemplate>())) ?? []
    }
}
```

---

### Task 7 — Add `aiEnabled` to `AppSettings` and `expanding` to `IslandState` [Small]

**File:** `BarTicket/Models/AppSettings.swift`

Add `var aiEnabled: Bool = true` property.

**File:** `BarTicket/ViewModels/AppState.swift`

Add to `IslandState`:
```swift
case expanding(title: String)
```

---

### Task 8 — Handle `.expanding` state in `DynamicIslandWindow.swift` [Small]

**File:** `BarTicket/Views/DynamicIslandWindow.swift`

Add a case to `DynamicIslandController.show(state:)`:

```swift
case .expanding(let title):
    viewModel.icon = "sparkles"
    viewModel.iconColor = .purple
    viewModel.iconAnimation = .pulsing
    viewModel.title = "Expanding with AI..."
    viewModel.subtitle = title
    viewModel.issueURL = nil
    viewModel.projectName = nil
    viewModel.projectURL = nil
    viewModel.projectFailed = false
    viewModel.isV2Project = false
```

The `sparkles` SF Symbol is already used in `ProjectBadge` for V2 projects, so it's confirmed available. Purple differentiates it from the blue detecting state and orange creating state.

---

### Task 9 — Wire AI into `handleNewTodo` pipeline in `BarTicketApp.swift` [Medium]

**File:** `BarTicket/BarTicketApp.swift`

The updated pipeline inside `handleNewTodo` Task block:

```
1. Sleep 1s (detecting min display)
2. If aiEnabled:
   a. Show .expanding(title:)
   b. Fetch templates from SwiftData
   c. Call ClaudeClient.generateIssue(rawTodo:templates:)
      - On success: use AI title, body, labels for GitHub issue
      - On failure: show brief .error("AI unavailable — using raw TODO"), sleep 1.5s, 
                    use todo.title and empty body, continue
3. Show .creating(title:)
4. Call GitHubClient.createIssue (pass labels if AI succeeded)
5. Continue with confirmed flow unchanged
```

The `expandingShownAt` clock is captured before the Claude call. After the call returns, enforce `Constants.claudeExpandDuration` (1.0s) minimum display time for the expanding state before transitioning to creating — same pattern as the existing `creatingShownAt` enforcement.

---

### Task 10 — Update `GitHubClient.createIssue` to accept labels [Small]

**File:** `BarTicket/Services/GitHubClient.swift`

Change the `createIssue` signature:
```swift
static func createIssue(
    owner: String,
    repo: String,
    title: String,
    body: String,
    labels: [String] = [],
    token: String
) async throws -> GitHubIssueResponse
```

Add `"labels": labels` to the `parameters` dictionary when `!labels.isEmpty`. The GitHub Issues API accepts a `labels` array on POST. Labels that don't yet exist in the repo are silently ignored by GitHub (they must be pre-created), so no error handling needed.

Note: `updateIssue` does not need to change — AI only runs on new TODO creation, not edits.

---

### Task 11 — Add AI section to `SettingsView.swift` [Medium]

**File:** `BarTicket/Views/SettingsView.swift`

Add a new "AI" section in the settings UI:

- Toggle: "Expand TODOs with AI" (bound to `AppSettings.aiEnabled`)
- When toggle is ON, show a `SecureField` for the Anthropic API key, with a small "Get API key" link opening `https://console.anthropic.com/`
- On submit/focus-loss of the API key field, save to Keychain via `KeychainService.save(key: .claudeAPIKey, value:)`
- Load existing key on appear: `KeychainService.read(key: .claudeAPIKey) != nil` — show a masked placeholder like "sk-ant-••••••••" if a key is already stored, clearing on edit
- Below the toggle, show a "Templates" disclosure group listing all `IssueTemplate` records fetched from the model context, with the ability to delete custom ones (built-in templates show a lock icon and cannot be deleted)

The `AppSettings` record needs to be fetched in the view (same pattern as existing `WatchedDirectory` fetch in `SettingsView`) to read/write `aiEnabled`.

---

### Task 12 — Register `IssueTemplate` in `ModelContainer` schema and seed on bootstrap [Small]

**File:** `BarTicket/BarTicketApp.swift`

1. Add `IssueTemplate.self` to the `Schema([...])` array in the `modelContainer` computed property.
2. In `bootstrap()`, after existing seeding logic, call:
   ```swift
   IssueTemplateService.seedIfNeeded(context: context)
   ```

---

## Dependencies & Risks

### External Dependencies
- **Anthropic API** — network dependency; any outage or rate limit triggers graceful degradation. No SDK needed; raw `URLSession` POST is sufficient.
- **Anthropic API key** — user must obtain and enter their own key from `console.anthropic.com`. This is a self-service step; the onboarding or settings UI should surface this clearly.

### Potential Risks

| Risk | Mitigation |
|---|---|
| Claude returns malformed JSON | Catch `DecodingError`, fall through to raw TODO path |
| Labels array contains names not pre-created in the repo | GitHub API silently ignores unknown labels; no user-facing error |
| SwiftData migration on upgrade | Adding a new model and attributes with default values are non-breaking changes — SwiftData handles these automatically. No migration plan needed. |
| `expanding` state adds latency | haiku-4-5 is fast (typically 1–2s). Combined with the 1s detecting floor, total pre-creating time is ~2–3s, which is acceptable. |
| User enters wrong API key | `ClaudeClientError.httpError(401)` caught, graceful fallback shown |
| Template name collision on re-seed | `@Attribute(.unique) var name` prevents duplicate insert; SwiftData will throw on conflict. Guard with `count == 0` check in `seedIfNeeded` prevents this. |

---

## Testing Strategy

### Manual Test Cases

1. **Happy path (AI enabled, valid key):** Write `// TODO: add retry logic for network calls`, save. Confirm island shows: detecting → expanding → creating → confirmed. Verify GitHub issue has structured title, body with Tasks/Acceptance Criteria section, and at least one label.

2. **AI disabled toggle:** Turn off "Expand TODOs with AI" in Settings. Write a new TODO. Confirm island skips `expanding` state entirely.

3. **Invalid/missing API key:** Set a bad API key. Write a TODO. Confirm island briefly shows error message "AI unavailable — using raw TODO" then transitions to creating and creates the issue with raw title.

4. **Network offline during Claude call:** Disconnect network, write TODO. Confirm graceful fallback, issue still created.

5. **Template seeding:** Delete app's SwiftData store (or fresh install). Launch app. Open Settings > Templates. Confirm "Feature" and "Bug" templates are present and marked as built-in.

6. **Labels passthrough:** After AI issue creation, open the GitHub issue. Confirm labels are set (pre-create "bug" and "enhancement" labels in the test repo first).

7. **Non-notch Mac (external display):** Confirm expanding state displays and dismisses correctly without the notch persisting.

### Debug Prints to Add
Follow the existing `[BarTicket]` print convention:
- `[BarTicket] AI expansion started for: "<title>"`
- `[BarTicket] AI expansion succeeded: title="\(result.title)" labels=\(result.labels)`
- `[BarTicket] AI expansion failed, using raw TODO: \(error)`

---

## File Creation Summary

| Action | File |
|---|---|
| New | `BarTicket/Services/ClaudeClient.swift` |
| New | `BarTicket/Services/IssueTemplateService.swift` |
| New | `BarTicket/Models/IssueTemplate.swift` |
| New | `BarTicket/Utilities/BuiltInTemplates.swift` |
| Modify | `BarTicket/Utilities/Constants.swift` |
| Modify | `BarTicket/Services/KeychainService.swift` |
| Modify | `BarTicket/Services/GitHubClient.swift` |
| Modify | `BarTicket/Models/AppSettings.swift` |
| Modify | `BarTicket/ViewModels/AppState.swift` |
| Modify | `BarTicket/Views/DynamicIslandWindow.swift` |
| Modify | `BarTicket/Views/SettingsView.swift` |
| Modify | `BarTicket/BarTicketApp.swift` |

---

## Git Workflow

**Branch:** `feat/aiIssueCreation`

Suggested commit sequence (squash-merged into dev):
```
add claude API constants and system prompt; add claudeAPIKey keychain key
add IssueTemplate SwiftData model; add BuiltInTemplates enum with feature and bug templates
add ClaudeClient service using URLSession; add IssueTemplateService seed logic
add expanding island state; wire sparkles icon and pulsing animation
add labels parameter to GitHubClient.createIssue
wire AI expansion into handleNewTodo pipeline with graceful fallback
add AI section to SettingsView with toggle, key field, and template list
register IssueTemplate in ModelContainer schema; seed built-in templates on bootstrap
```

---

## Open Questions / Decisions Made

| Question | Decision |
|---|---|
| Template selection strategy | Single Claude call — Claude picks template and fills content simultaneously |
| Model | claude-haiku-4-5, 2048 tokens |
| API response format | JSON with `title`, `body`, `labels` |
| Fallback behavior | Brief error notch state ("AI unavailable — using raw TODO"), then continue with raw title |
| Template storage | Swift enum seeds SwiftData; built-in + custom coexist in one store |
| Networking | URLSession (no Alamofire dependency for Claude) |
| Labels on update | Not supported — AI only runs on new issue creation |
