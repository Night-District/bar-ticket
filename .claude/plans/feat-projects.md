# Feature Plan: GitHub Projects Integration

**Feature:** Add GitHub Projects (Classic + v2) support to Bar Ticket  
**Status:** Planning  
**Created:** 2026-04-05  
**Scope:** Local project selection per watched directory; auto-assign issues to projects on creation

---

## Overview

Currently, Bar Ticket creates issues but doesn't assign them to any project. This feature adds per-directory project assignment:

1. **User selects a GitHub project** (org/user projects, both Classic v1 and v2)
2. **Bar Ticket caches projects locally** (SwiftData) keyed by project node ID
3. **On TODO detection**, issues are auto-assigned to the selected project
4. **Failure handling:** If assignment fails, issue still created, user notified
5. **UI:** Inline dropdown in SettingsView watched directory row; project badge in NotchExpandedView

---

## Architecture Decisions

### 1. Project Scope: Org/User Remote URL
- Project scope determined by `git remote get-url origin`
- Supports both GitHub organization projects and user profile projects
- Example: `https://github.com/Night-District/bar-ticket.git` → fetch org projects for "Night-District"
- User profile projects: `https://github.com/username/repo.git` → fetch projects for "username"

### 2. Project Versions: Classic + v2
- **Classic (v1):** Traditional GitHub Projects, simpler REST API
- **v2:** New Projects (beta), GraphQL-based, more powerful
- UI: Grouped by type and owner in dropdown (e.g., "Classic Projects", "v2 Projects")
- GraphQL queries fetch both types and unify them in the dropdown

### 3. Caching Strategy: SwiftData
- New model `ProjectCache`: stores name, node ID, type, owner
- Keyed by `projectNodeId` (stable across renames, unlike numeric IDs)
- Populated on first fetch; refreshed on user action (button click)
- Enables offline selection and fast dropdown rendering

### 4. Assignment Failure Handling
- If project assignment fails (API error, permission denied, etc.):
  - Issue is **already created** (separate API call, happens first)
  - Failure is **logged** in console
  - **Notification shown** in NotchExpandedView with retry option
  - User can manually assign in GitHub if needed
- No blocking on project assignment; TODO pipeline continues

### 5. API Integration: GraphQL
- Use GraphQL for both Classic and v2 projects (REST API only supports Classic)
- Fetch:
  - Org/user projects with proper scoping
  - Issue templates (optional future feature)
- Advantages:
  - Fetch multiple project types in single query
  - Field-level control (avoid unnecessary data)
  - Future-proof for v2-only features

### 6. UI Placement: Watched Directory Row
- **Current:** Folder icon, path, remove button
- **New:** Inline dropdown after path showing selected project (or "No project")
- **Behavior:** Click opens dropdown, shows cached projects grouped by type/owner
- **May expand SettingsView:** Dropdown width could require increasing frame width from 380px
- **Future:** Could migrate to List-based SettingsView for better scalability

### 7. NotchExpandedView Badge
- Add project info to confirmed state UI
- **Design goals:**
  - Subtly indicate project assignment without cluttering
  - Show project type (Classic/v2) or just name
  - Clickable to open project in GitHub
  - "Surprise with great design" — use glassmorphism or icon hints
- **Proposed:** Small rounded badge below subtitle showing project name + icon
  - Example: "🗂 Q1 Planning" (Classic) or "✨ 2024 Roadmap" (v2)
  - Hover: show full project name, click to open

### 8. Empty State: Omit Project Row
- If no project assigned to directory: don't show project row at all
- Cleaner UI, reduces clutter
- User can always add project via dropdown on demand

### 9. Project Grouping
- Group in dropdown by:
  1. Owner (org/user name)
  2. Type (Classic, v2)
  3. Example layout:
     ```
     Night-District (org)
       ├─ Classic Projects
       │  └─ Backlog
       │  └─ Q1 Planning
       └─ v2 Projects
         └─ 2024 Roadmap
     
     loganriedley (user)
       ├─ Classic Projects
       │  └─ Personal Notes
     ```

### 10. Storage: Project Node ID in SwiftData
- Store stable `projectNodeId` (from GraphQL `node` field)
- Node IDs survive project renames and are stable across API versions
- Migrate if display name changes (re-fetch projects)
- Don't store numeric `id` (Classic) or `number` (v2) — they're not stable

---

## Data Models

### New Model: `ProjectCache`
```swift
@Model
final class ProjectCache {
    @Attribute(.unique) var projectNodeId: String  // GraphQL node ID
    var displayName: String                         // Project name
    var owner: String                               // Org or user
    var projectType: ProjectType                   // .classic or .v2
    var projectURL: String?                        // GitHub project link
    var cachedAt: Date
    var expiresAt: Date?                           // Optional TTL for cache invalidation
    
    enum ProjectType: Codable {
        case classic
        case v2
    }
}
```

### Extended Model: `WatchedDirectory`
```swift
// Add optional project field
var selectedProjectNodeId: String?  // Links to ProjectCache.projectNodeId
```

### New IslandState Case
```swift
case confirmed(
    title: String,
    repoFullName: String,
    issueNumber: Int,
    issueURL: String,
    projectName: String? = nil,          // NEW
    projectType: ProjectCache.ProjectType? = nil  // NEW
)
```

---

## GraphQL Implementation

### Query: Fetch Organization Projects
```graphql
query FetchOrgProjects($owner: String!) {
  organization(login: $owner) {
    projectsV2(first: 50) {
      nodes {
        id
        title
        url
      }
    }
    projects(first: 50) {  # Classic projects
      nodes {
        id
        name
        url
      }
    }
  }
}
```

### Query: Fetch User Projects
```graphql
query FetchUserProjects($login: String!) {
  user(login: $login) {
    projectsV2(first: 50) {
      nodes {
        id
        title
        url
      }
    }
    projects(first: 50) {  # Classic projects
      nodes {
        id
        name
        url
      }
    }
  }
}
```

### Mutation: Add Issue to Project
**v2 Projects:**
```graphql
mutation AddIssueToProjectV2($projectId: ID!, $issueId: ID!) {
  addProjectV2ItemById(input: {
    projectId: $projectId
    contentId: $issueId
  }) {
    item {
      id
    }
  }
}
```

**Classic Projects:**
```graphql
mutation AddIssueToClassicProject($projectId: ID!, $issueId: ID!) {
  addProjectCard(input: {
    projectColumnId: $projectId
    contentId: $issueId
  }) {
    projectCard {
      id
    }
  }
}
```

### New Service: `GitHubProjectsClient`
```swift
enum GitHubProjectsClient {
    
    static func fetchProjects(
        owner: String,
        token: String
    ) async throws -> [ProjectInfo]
    // Returns merged list of Classic + v2 projects for owner
    
    static func addIssueToProject(
        projectNodeId: String,
        issueNumber: Int,
        owner: String,
        repo: String,
        projectType: ProjectCache.ProjectType,
        token: String
    ) async throws
    // Assigns issue to project; doesn't block on failure
}

struct ProjectInfo: Identifiable {
    let id: String  // Node ID
    let name: String
    let url: String
    let type: ProjectCache.ProjectType
    let owner: String
}
```

---

## UI Components

### 1. WatchedDirectoryRow (in SettingsView)
```swift
HStack {
    // Existing folder icon and path
    Image(systemName: "folder.fill")
    Text(dir.displayPath)
    
    Spacer()
    
    // NEW: Project dropdown
    if let projectId = dir.selectedProjectNodeId,
       let project = cachedProject(projectId) {
        ProjectDropdownButton(
            directory: dir,
            selectedProject: project,
            onSelect: { selectedId in
                dir.selectedProjectNodeId = selectedId
                try? modelContext.save()
            }
        )
    } else {
        ProjectDropdownButton(
            directory: dir,
            selectedProject: nil,
            onSelect: { selectedId in
                dir.selectedProjectNodeId = selectedId
                try? modelContext.save()
            }
        )
    }
    
    // Existing remove button
    Button { ... }
}
```

### 2. ProjectDropdownButton
```swift
struct ProjectDropdownButton: View {
    let directory: WatchedDirectory
    let selectedProject: ProjectCache?
    let onSelect: (String) -> Void
    
    @State private var isLoading = false
    @State private var showDropdown = false
    @State private var groupedProjects: [ProjectGroup] = []
    @State private var errorMessage: String?
    
    var body: some View {
        Menu {
            // Refresh button
            Button {
                refreshProjects()
            } label: {
                Label("Refresh Projects", systemImage: "arrow.clockwise")
            }
            
            Divider()
            
            // Group by owner and type
            ForEach(groupedProjects, id: \.owner) { group in
                Section(header: Text(group.owner)) {
                    ForEach(group.projects, id: \.id) { project in
                        Button {
                            onSelect(project.id)
                        } label: {
                            HStack {
                                Text(project.name)
                                if project.id == selectedProject?.projectNodeId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedProject != nil ? "folder.badge.checkmark" : "folder.badge.plus")
                    .foregroundStyle(.blue)
                Text(selectedProject?.displayName ?? "No project")
                    .lineLimit(1)
                    .font(.caption)
                    .foregroundStyle(selectedProject != nil ? .primary : .secondary)
                Image(systemName: "triangle.fill")
                    .font(.system(size: 3))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.1), in: Capsule())
        }
        .onAppear {
            loadCachedProjects()
        }
    }
    
    private func loadCachedProjects() {
        // Load from ProjectCache, populate groupedProjects
    }
    
    private func refreshProjects() {
        // Fetch fresh projects from API, update cache
    }
}

struct ProjectGroup {
    let owner: String
    let projects: [ProjectCache]
}
```

### 3. Enhanced NotchExpandedView
```swift
struct NotchExpandedView: View {
    @Bindable var viewModel: NotchViewModel
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon (existing)
            AnimatedIcon(...)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                
                if !viewModel.subtitle.isEmpty {
                    Text(viewModel.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                
                // NEW: Project badge
                if let projectName = viewModel.projectName {
                    ProjectBadge(
                        name: projectName,
                        type: viewModel.projectType
                    )
                }
            }
            
            Spacer(minLength: 0)
            
            // Open button (existing)
            if let urlString = viewModel.issueURL { ... }
        }
        .frame(height: 40)  // May need to increase for badge
    }
}

struct ProjectBadge: View {
    let name: String
    let type: ProjectCache.ProjectType?
    
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type == .v2 ? "sparkles" : "folder.fill")
                .font(.caption2)
            Text(name)
                .font(.caption2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.white.opacity(0.15), in: Capsule())
        .onTapGesture {
            if let url = projectURL {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private var projectURL: URL? {
        // Build GitHub project URL
        // v2: https://github.com/owner/repo/projects/123
        // Classic: https://github.com/orgs/owner/projects/123
        nil
    }
}
```

### 4. NotchViewModel Extended
```swift
@MainActor
@Observable
final class NotchViewModel {
    // Existing fields...
    
    // NEW:
    var projectName: String? = nil
    var projectType: ProjectCache.ProjectType? = nil
    var projectURL: String? = nil
}
```

---

## Implementation Timeline

### Phase 1: Data Models & Caching (1-2 hours)
1. Create `ProjectCache` model in `BarTicket/Models/ProjectCache.swift`
2. Extend `WatchedDirectory` with `selectedProjectNodeId`
3. Update `BarTicketApp.swift` AppDelegate schema to include `ProjectCache`
4. Create migration/initialization logic

### Phase 2: GraphQL Integration (2-3 hours)
1. Extend `GitHubClient.swift` with GraphQL transport layer
2. Create `GitHubProjectsClient.swift` with:
   - `fetchProjects(owner:token:)` for both Classic + v2
   - `addIssueToProject(projectNodeId:issueNumber:...)` mutation
3. Add error handling for rate limits, permission errors, org/user detection

### Phase 3: UI Components (2-3 hours)
1. Create `ProjectDropdownButton.swift` with grouping logic
2. Update `WatchedDirectoryRow` in `SettingsView.swift`
3. Design & implement `ProjectBadge.swift` in `DynamicIslandWindow.swift`
4. Extend `NotchViewModel` with project fields
5. Update `NotchExpandedView` to render badge

### Phase 4: Pipeline Integration (1-2 hours)
1. Update `AppDelegate.handleNewTodo()` to:
   - Check if directory has `selectedProjectNodeId`
   - Call `GitHubProjectsClient.addIssueToProject()` after issue creation
   - Capture project name/type, pass to NotchViewController
   - Handle assignment failures gracefully
2. Update `IslandState.confirmed` to include project info
3. Update `DynamicIslandController.show()` to populate NotchViewModel fields

### Phase 5: Testing & Refinement (1-2 hours)
1. Test project fetch on org + user remotes
2. Verify Classic + v2 project detection and grouping
3. Test assignment to both project types
4. Test error handling (API failures, permission errors)
5. Verify notch badge UX (size, visibility, click-through)
6. Test cache invalidation on project refresh

---

## Implementation Details

### Owner Detection from Git Remote

In `AppDelegate.handleNewTodo()`:

```swift
guard let repoInfo = GitResolver.resolve(filePath: todo.filePath) else { ... }
let owner = repoInfo.owner  // "Night-District" or "loganriedley"

// Fetch projects for this owner
if let selectedProjectId = watchedDir.selectedProjectNodeId {
    Task {
        do {
            try await GitHubProjectsClient.addIssueToProject(
                projectNodeId: selectedProjectId,
                issueNumber: response.number,
                owner: owner,
                repo: repoInfo.repo,
                projectType: projectType,
                token: token
            )
            // Update NotchViewModel with project info
            // Don't block; continue to confirmed state
        } catch {
            // Log error, show in notch if needed
            print("[BarTicket] Project assignment failed: \(error)")
        }
    }
}
```

### Project Dropdown Refresh Logic

When user clicks "Refresh Projects":

```swift
private func refreshProjects() {
    isLoading = true
    guard let owner = extractOwnerFromDirectory() else {
        errorMessage = "Could not determine project owner"
        isLoading = false
        return
    }
    
    Task {
        do {
            let projects = try await GitHubProjectsClient.fetchProjects(
                owner: owner,
                token: appState.githubToken ?? ""
            )
            
            // Save to cache
            for project in projects {
                let cached = ProjectCache(
                    projectNodeId: project.id,
                    displayName: project.name,
                    owner: project.owner,
                    projectType: project.type,
                    projectURL: project.url,
                    cachedAt: Date()
                )
                modelContext.insert(cached)
            }
            try? modelContext.save()
            
            groupedProjects = groupByOwnerAndType(projects)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}
```

### Graceful Assignment Failure

In `AppDelegate.handleNewTodo()`:

```swift
let response = try await GitHubClient.createIssue(...)  // Issue created first

// Then attempt project assignment (non-blocking)
if let selectedProjectId = watchedDir.selectedProjectNodeId {
    Task {
        do {
            try await GitHubProjectsClient.addIssueToProject(...)
            // Success — update NotchViewModel
        } catch {
            // Log but don't fail
            print("[BarTicket] Could not add issue to project: \(error)")
            // Optionally: store failure in SeenTodo for later retry
        }
    }
}

// Show confirmed state regardless of project assignment
appState.showIsland(state: .confirmed(...))
```

---

## Testing Strategy

### Unit Tests
- [ ] GraphQL query builder (Classic vs v2 detection)
- [ ] Project grouping logic (by owner, by type)
- [ ] Node ID extraction and caching

### Integration Tests
- [ ] Fetch org projects (requires auth with org access)
- [ ] Fetch user projects (personal account)
- [ ] Add issue to Classic project
- [ ] Add issue to v2 project
- [ ] Handle API errors (403 permission, 404 not found, rate limit)

### Manual Tests
- [ ] Create TODO in org repo, verify project assignment
- [ ] Create TODO in personal repo, verify project selection
- [ ] Switch between Classic/v2 projects in dropdown
- [ ] Refresh projects; verify cache update
- [ ] Disable watching; verify no assignment attempts
- [ ] Test on macOS with/without notch (badge visibility)

### Test Files
- `BarTicket/Tests/GitHubProjectsClientTests.swift`
- `BarTicket/Tests/ProjectDropdownButtonTests.swift`
- `BarTicket/Tests/ProjectCacheTests.swift`

---

## Error Handling Scenarios

| Scenario | Behavior |
|----------|----------|
| No GitHub token | Skip project fetch; show "No token" error in dropdown |
| Org/user not found | Show "Owner not found" in dropdown; allow manual retry |
| Project assignment permission denied (403) | Log error; create issue without project; show notification |
| Project not found (404) | Assume project deleted; clear cache; offer refresh |
| Rate limit hit (429) | Show "Rate limited" in dropdown; suggest retry |
| Network offline | Use cached projects; show "Offline" badge; queue assignment for retry |
| Issue created but assignment fails | Issue is live on GitHub; user can assign manually; log failure |

---

## Known Limitations & Future Work

### Current Limitations
1. **No bulk edit:** Cannot assign multiple issues to project at once
2. **No custom fields:** Can only assign; cannot set Classic project columns or v2 field values
3. **No project templates:** Cannot use issue templates from projects
4. **Single project per directory:** Not supporting multiple projects per watched directory (MVP)
5. **No offline assignment queue:** Failed assignments not retried

### Future Enhancements
1. **Issue templates:** Fetch templates from v2 project, pre-fill issue body
2. **Custom field values:** For v2 projects, allow setting status, priority, etc.
3. **Multiple projects per directory:** Support assigning to multiple projects
4. **Cache TTL:** Expire project cache after N hours; auto-refresh
5. **Assignment retry queue:** Persist failed assignments; retry on next app launch
6. **Org/team settings:** Admin UI to set default project per team/org

---

## bar-ticket-site Updates

**No website changes required** for initial release:
- App version stays 2.0.0 (or bumps to 2.1.0 if released separately)
- Feature is opt-in (project dropdown)
- No new user-facing docs needed initially
- Release notes will mention "Projects Integration" in next release

**Future:** Add to feature tour or onboarding if needed

---

## Git Workflow & Commits

### Branch Strategy
```bash
git checkout -b feat/projects-integration
```

### Commit Structure (following Night District workflow)
```
feat/projects-integration
├─ add ProjectCache model; extend WatchedDirectory (commit 1)
├─ implement GitHubProjectsClient with GraphQL (commit 2)
├─ add ProjectDropdownButton UI component (commit 3)
├─ integrate project assignment in handleNewTodo (commit 4)
├─ add ProjectBadge to NotchExpandedView (commit 5)
└─ tests and refinements (commit 6)
```

### Example Commits
```bash
git commit -m 'add ProjectCache model; extend WatchedDirectory with selectedProjectNodeId'
git commit -m 'implement GitHubProjectsClient; support Classic and v2 project fetching'
git commit -m 'add ProjectDropdownButton with grouping by owner and type'
git commit -m 'integrate project assignment in todo pipeline; handle failures gracefully'
git commit -m 'add ProjectBadge to NotchExpandedView; show project name and type'
```

### PR & Review
1. Push to `origin feat/projects-integration`
2. Create PR with:
   - Title: "feat: Add GitHub Projects integration"
   - Description: Link to this plan, summarize scope & decisions
   - Test plan: Manual tests listed above
3. Request review from project manager
4. Squash & merge to `dev` when approved
5. Delete branch after merge

---

## Summary

**Scope:** Full GitHub Projects (Classic + v2) integration with per-directory selection, auto-assignment, and graceful error handling.

**Key Decisions:**
- Org/user scope via git remote
- GraphQL for unified API
- SwiftData caching with node IDs
- Non-blocking project assignment
- Inline dropdown + badge UI
- Omit project row when not assigned

**Effort:** ~8-10 hours (5 phases)

**Start Phase:** 1 — Data Models & Caching

**Next Steps:**
1. Approve this plan
2. Begin Phase 1 implementation
3. Create feature branch
4. Write ProjectCache model
5. Extend WatchedDirectory + AppDelegate schema
