---
branch: feat/github-oauth
description: Replace PAT-based auth with GitHub OAuth flow including onboarding, browser-based login, custom URL scheme callback, proxy token exchange, and account info in SettingsView
date: 2026-04-08
scope: app
technical_approach: GitHub OAuth App with custom URL scheme (barticket://), Cloudflare Worker proxy for client secret security, AsyncImage avatar in SettingsView, PAT migration path
---

# feat/github-oauth — GitHub OAuth Authentication

## Feature Summary

Replace the manual personal access token entry system with a GitHub OAuth App flow that opens the browser, handles the callback via a custom URL scheme, exchanges the authorization code for a token, stores it in the Keychain, and displays account info in SettingsView.

## User Value

PATs require the user to understand GitHub's developer settings, manually scope permissions, copy a token, and paste it into the app. OAuth is one button. The user sees the familiar GitHub authorization page, approves, and is returned to the app automatically. The resulting token also carries delegated user-level permissions — it sees every repo the user can access, including org repos and collaborator-granted private repos, without any manual scoping decisions.

---

## Manual Setup Steps (Sequential — Must Be Done Before Writing Code)

These steps require action in GitHub, Cloudflare, and Xcode. They cannot be automated.

### Step 1: Register a GitHub OAuth App

Go to https://github.com/organizations/Night-District/settings/applications (or your personal account at https://github.com/settings/developers) and click "New OAuth App".

Fill in:
- **Application name:** `Bar Ticket`
- **Homepage URL:** `https://night-district.github.io/bar-ticket-site/`
- **Authorization callback URL:** `barticket://oauth/callback`

Click "Register application". GitHub will give you a **Client ID** (public) and let you generate a **Client Secret** (treat as a secret, never commit to source control).

Save both values — you'll need them in Step 2.

### Step 2: Deploy the Cloudflare Worker (token exchange proxy)

The Worker holds the Client Secret server-side so it never ships in the app binary.

**Prerequisites:**
- A Cloudflare account (free tier — 100k requests/day, more than enough)
- `wrangler` CLI: `npm install -g wrangler`

**2a. Authenticate wrangler:**
```bash
wrangler login
```
This opens your browser to authorize the CLI with your Cloudflare account.

**2b. Create the Worker project:**
```bash
mkdir bar-ticket-oauth && cd bar-ticket-oauth
wrangler init --type javascript
```

**2c. Write the Worker — replace `src/index.js` with:**
```js
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204 });
    }

    if (request.method !== 'POST') {
      return Response.json({ error: 'Method not allowed' }, { status: 405 });
    }

    // GitHub Marketplace webhook events
    if (url.pathname === '/webhook') {
      const signature = request.headers.get('x-hub-signature-256');
      const body = await request.text();

      // Verify HMAC-SHA256 signature using the webhook secret
      const encoder = new TextEncoder();
      const key = await crypto.subtle.importKey(
        'raw',
        encoder.encode(env.WEBHOOK_SECRET),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign']
      );
      const mac = await crypto.subtle.sign('HMAC', key, encoder.encode(body));
      const expected = 'sha256=' + Array.from(new Uint8Array(mac))
        .map(b => b.toString(16).padStart(2, '0')).join('');

      if (signature !== expected) {
        return new Response('Unauthorized', { status: 401 });
      }

      // Acknowledge receipt — no action needed for free plan
      return new Response(null, { status: 200 });
    }

    // OAuth token exchange
    const { code } = await request.json();
    if (!code) {
      return Response.json({ error: 'Missing code' }, { status: 400 });
    }

    const res = await fetch('https://github.com/login/oauth/access_token', {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        client_id: env.GITHUB_CLIENT_ID,
        client_secret: env.GITHUB_CLIENT_SECRET,
        code,
      }),
    });

    const data = await res.json();

    if (data.error) {
      return Response.json({ error: data.error_description }, { status: 400 });
    }

    return Response.json({ access_token: data.access_token });
  },
};
```

**2d. Configure `wrangler.toml`:**
```toml
name = "bar-ticket-oauth"
main = "src/index.js"
compatibility_date = "2024-01-01"
```

**2e. Add secrets (stored encrypted in Cloudflare, never in source):**
```bash
wrangler secret put GITHUB_CLIENT_ID
# paste your Client ID from Step 1 when prompted

wrangler secret put GITHUB_CLIENT_SECRET
# paste your Client Secret from Step 1 when prompted

wrangler secret put WEBHOOK_SECRET
# generate and paste a random secret: openssl rand -hex 32
# save this value — you'll need it in Step 6 (GitHub webhook config)
```

**2f. Deploy:**
```bash
wrangler deploy
```

This gives you a URL like: `https://bar-ticket-oauth.<your-subdomain>.workers.dev`

**2g. Test the OAuth exchange endpoint:**
```bash
curl -X POST https://bar-ticket-oauth.<your-subdomain>.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"code": "fake"}'
```

Expected response: `{"error": "bad_verification_code"}` — confirms the Worker is live and talking to GitHub.

Save the Worker URL — you'll need it in Steps 3 and 6.

### Step 3: Store the Client ID and Worker URL in the Xcode project

The Client ID and Worker URL are not secrets — they can live in source code. Add them to `Constants.swift`:

```swift
static let githubOAuthClientID = "Ov23li..." // your actual Client ID
static let githubOAuthCallbackURL = "barticket://oauth/callback"
static let githubOAuthScopes = "repo project"
static let githubOAuthProxyURL = "https://bar-ticket-oauth.<your-subdomain>.workers.dev"
```

The Client Secret lives only in Cloudflare — it is never committed to source control or embedded in the app binary.

### Step 4: Register the custom URL scheme in Info.plist

Add a `CFBundleURLTypes` entry to `/BarTicket/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>com.nightdistrict.bar-ticket.oauth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>barticket</string>
        </array>
    </dict>
</array>
```

After adding this, macOS will route any URL with the `barticket://` scheme to the Bar Ticket app via `application(_:open:)` on `NSApplicationDelegate`.

### Step 5: Verify App Sandbox entitlements

In `/BarTicket/BarTicket.entitlements`, verify `com.apple.security.network.client` is present (it should already be there for Alamofire). No additional entitlements needed.

### Step 6: Configure the GitHub Marketplace webhook

GitHub requires a webhook endpoint to publish on the Marketplace. It sends `POST` events for plan purchases, cancellations, and changes.

In your GitHub OAuth App settings under **Marketplace listing → Manage webhook**, fill in:

| Field | Value |
|---|---|
| **Payload URL** | `https://bar-ticket-oauth.<your-subdomain>.workers.dev/webhook` |
| **Content type** | `application/json` |
| **Secret** | The `WEBHOOK_SECRET` value you generated in Step 2e |
| **Active** | Checked |

The Worker verifies the HMAC-SHA256 signature on every incoming request and returns `200` to acknowledge. No further action is taken since Bar Ticket is currently on a free plan.

---

## The Client Secret Problem

The standard OAuth web flow requires the client secret to exchange a code for a token. In a native macOS app, the binary can be reverse-engineered — the secret cannot be safely embedded.

**Recommended approach: Proxy server (most secure)**

Deploy a minimal serverless function (Cloudflare Worker) that holds the client secret server-side. The app sends the authorization code to this proxy, the proxy exchanges it with GitHub, and returns only the token. The proxy URL is public but the secret stays off-device.

Endpoint: `POST https://bar-ticket-oauth.nightdistrict.workers.dev/exchange` with body `{ "code": "..." }`, returns `{ "access_token": "gho_..." }`.

---

## Technical Components Affected

| Component | Change Type |
|---|---|
| `KeychainService.swift` | Add new `KeychainKey` case for OAuth token |
| `AppState.swift` | Add `githubUser` model, OAuth state, sign-in/out methods |
| `BarTicketApp.swift` / `AppDelegate` | Handle `application(_:open:)` URL callback; onboarding gate |
| `Constants.swift` | Add OAuth client ID, callback URL, proxy URL |
| `GitHubClient.swift` | No breaking changes; token source changes but usage identical |
| `GitHubProjectsClient.swift` | No breaking changes; same token usage |
| `SettingsView.swift` | Replace token GroupBox with GitHub account GroupBox |
| `Info.plist` | Register `barticket://` URL scheme |
| New: `GitHubAuthService.swift` | New service: orchestrate OAuth flow, code exchange, user fetch |
| New: `GitHubUser.swift` | New model: decoded GitHub user profile |
| New: `OnboardingView.swift` | New view: first-launch sign-in screen |

---

## Implementation Tasks

### Task 1 — Add `GitHubUser` model
**File:** `BarTicket/Models/GitHubUser.swift` (new)

Create a plain `struct GitHubUser: Codable` with fields: `login`, `name`, `avatarUrl`, `email`, `htmlUrl`, `publicRepos`. Include `CodingKeys` for snake_case mapping. Not a SwiftData model — lives in `AppState` in memory, re-fetched at launch.

### Task 2 — Extend `KeychainService`
**File:** `BarTicket/Services/KeychainService.swift`

Add new `KeychainKey` case:
```swift
case githubOAuthToken = "com.nightdistrict.bar-ticket.github-oauth-token"
```

Keep existing `githubToken` (PAT) temporarily for migration. Migration logic in `AppState.loadAuth()`: check OAuth token first, fall back to PAT key, delete PAT after migrating.

### Task 3 — Create `GitHubAuthService`
**File:** `BarTicket/Services/GitHubAuthService.swift` (new)

```swift
@Observable
final class GitHubAuthService {
    private(set) var isExchangingToken = false
    private(set) var error: String?
    private var pendingState: String?
    
    func startOAuthFlow()               // build URL, store nonce, open browser
    func handleCallback(url: URL) async // parse code+state, validate, exchange, fetch user
    private func exchangeCode(_ code: String) async throws -> String  // POST to proxy
    private func fetchAuthenticatedUser(token: String) async throws -> GitHubUser
}
```

`startOAuthFlow()` constructs:
```
https://github.com/login/oauth/authorize
  ?client_id=<Constants.githubOAuthClientID>
  &redirect_uri=barticket://oauth/callback
  &scope=repo%20project
  &state=<UUID().uuidString>
```

`scope=repo project` — `repo` grants read/write to repos and issues, `project` grants project board access.

`exchangeCode(_:)` POSTs to the proxy URL with `{ "code": "..." }` and expects `{ "access_token": "gho_..." }` back.

`fetchAuthenticatedUser(token:)` calls `GET https://api.github.com/user` and decodes into `GitHubUser`.

### Task 4 — Deploy the Cloudflare Worker proxy
**Scope:** Manual (infrastructure, outside this repo)

See **Manual Setup Step 2** above for the full Cloudflare Worker setup guide including project creation, Worker code, secrets configuration, deployment, and testing.

### Task 5 — Update `AppState`
**File:** `BarTicket/ViewModels/AppState.swift`

Add:
```swift
var githubUser: GitHubUser?
var authService = GitHubAuthService()
var hasCompletedOnboarding: Bool  // backed by UserDefaults
```

`loadToken()` becomes `loadAuth()`:
- Read OAuth token from Keychain (new key first, PAT fallback with migration)
- If token present, fetch user profile via `GitHubAuthService.fetchAuthenticatedUser(token:)`
- Set `githubUser` and `githubToken`

`clearToken()` becomes `signOut()`:
- Deletes Keychain entry
- Nils `githubToken` and `githubUser`
- Resets `hasCompletedOnboarding` to `false`

Add `isAuthenticated: Bool` computed property: `githubToken != nil`

### Task 6 — Handle URL callback in `AppDelegate`
**File:** `BarTicket/BarTicketApp.swift`

Add to `AppDelegate`:
```swift
func application(_ application: NSApplication, open urls: [URL]) {
    guard let url = urls.first, url.scheme == "barticket" else { return }
    Task { @MainActor in
        await appState.authService.handleCallback(url: url)
        if appState.authService.error == nil {
            appState.loadAuth()
        }
    }
}
```

Update `bootstrap()`: replace `loadToken()` with `loadAuth()`, gate on `isAuthenticated`.

### Task 7 — Create `OnboardingView`
**File:** `BarTicket/Views/OnboardingView.swift` (new)

Centered SwiftUI view shown when `!appState.isAuthenticated`:
- Bar Ticket logo/icon at top
- Heading: "Welcome to Bar Ticket"
- Subheading: "Connect your GitHub account to start creating issues automatically from your TODO comments."
- Primary CTA: "Sign in with GitHub" button — calls `appState.authService.startOAuthFlow()`
- During exchange: `ProgressView` with "Connecting..." label, button disabled
- On error: small red caption beneath the button

In `BarTicketApp.swift`, swap views based on `appState.isAuthenticated`:
```swift
MenuBarExtra("Bar Ticket", systemImage: "ticket.fill") {
    Group {
        if appState.isAuthenticated {
            SettingsView()
        } else {
            OnboardingView()
        }
    }
    .environment(appDelegate.appState)
    .modelContainer(appDelegate.modelContainer)
    .frame(width: 480, height: appState.isAuthenticated ? 440 : 320)
}
```

### Task 8 — Update `SettingsView`
**File:** `BarTicket/Views/SettingsView.swift`

Remove the "GitHub Token" `GroupBox` entirely. Replace with "GitHub Account" `GroupBox`:
- `AsyncImage` avatar (32x32, rounded)
- `@login` (name if available)
- "Connected via GitHub OAuth" caption
- "Sign Out" button (red, destructive) — calls `appState.signOut()`

Remove `@State private var tokenInput` and `showTokenField`.

### Task 9 — Update `Constants.swift`
**File:** `BarTicket/Utilities/Constants.swift`

Add:
```swift
static let githubOAuthClientID = "<your-client-id>"
static let githubOAuthCallbackURL = "barticket://oauth/callback"
static let githubOAuthScopes = "repo project"
static let githubOAuthProxyURL = "https://<your-worker>.workers.dev/exchange"
```

### Task 10 — Register URL scheme in `Info.plist`
**File:** `BarTicket/Info.plist`

Add `CFBundleURLTypes` as shown in Manual Setup Step 3. Test with:
```bash
open barticket://oauth/callback?code=test&state=test
```

---

## Dependencies and Risks

- **Client Secret exposure:** Proxy pattern adds infrastructure dependency. Mitigate by keeping the proxy stateless and simple.
- **Token exchange race condition:** Only store one `pendingState` nonce at a time; discard callbacks with mismatched state.
- **URL scheme timing:** On first install, macOS may not have registered the scheme yet. Verify with clean install test.
- **Existing PAT migration:** Users with PAT under old key get transparent migration on first launch.
- **`project` OAuth scope:** Projects v2 requires `project` scope for write, `read:project` for read. Use `repo project` in authorization URL.
- **Avatar caching:** `AsyncImage` in `MenuBarExtra` makes a request on every popover open. System URL cache should handle this, but monitor.

---

## Testing Strategy

1. **Full flow test:** Delete Keychain entry -> launch -> OnboardingView appears -> sign in -> GitHub opens -> approve -> redirected back -> SettingsView shows account
2. **Persistence test:** Quit and relaunch -> token persisted, SettingsView loads without re-auth
3. **Issue creation test:** Create a TODO -> verify issue creation works with OAuth token
4. **Sign out test:** Click Sign Out -> OnboardingView reappears -> Keychain entry deleted
5. **State nonce validation:** Run `open barticket://oauth/callback?code=fake&state=wrongstate` -> app ignores the callback
6. **Migration test:** Insert old PAT in Keychain -> launch -> transparent migration

---

## Git Workflow

**Branch:** `feat/github-oauth`

Suggested commit sequence:
```
add GitHubUser model; add githubOAuthToken keychain key; add PAT migration logic
add GitHubAuthService with OAuth flow, state nonce, code exchange, user fetch
add barticket:// URL scheme to Info.plist; add Constants for OAuth config
add OnboardingView with sign-in button and exchange progress state
update AppState: add githubUser, isAuthenticated, loadAuth, signOut
handle application(_:open:) in AppDelegate; gate bootstrap on isAuthenticated
update SettingsView: replace token field with GitHub account section and avatar
deploy Cloudflare Worker proxy for token exchange
```

## No Website Changes Required

This feature is entirely internal to the app.
