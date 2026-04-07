---
branch: feat/analytics
description: Add privacy-friendly analytics to bar-ticket-site to track page visits, download button clicks, and actual DMG download counts with a private dashboard
date: 2026-04-06
scope: website
technical_approach: GoatCounter hosted free tier — single script tag, data attributes for click events, no cookies, private dashboard by default
---

# feat/analytics — Bar Ticket Site Analytics

## Feature Summary

Add free, cookieless analytics to the bar-ticket-site landing page to track page visits, download button clicks, and actual DMG file download counts, with a private dashboard accessible only to Logan.

## User Value

Understand how many people visit the site, how many click to download, and how many actually complete the DMG download. This funnel data (visit → click → download) reveals whether the CTA is converting and whether users complete the download.

---

## Analytics Tool Recommendation: GoatCounter

### Comparison Matrix

| Tool | Free Tier | Cookie-Free | Single Script Tag | Private Dashboard | Custom Events | Verdict |
|---|---|---|---|---|---|---|
| **GoatCounter** | Yes — unlimited pageviews for personal/non-commercial | Yes — no cookies, no GDPR notice needed | Yes | Yes — private by default, opt-in public | Yes — `data-goatcounter-click` attributes + JS API | **Best fit** |
| Plausible | No — 30-day trial only, then $9/mo minimum | Yes | Yes | Yes | Yes — requires `plausible()` JS calls | Eliminated: not free |
| Fathom | No — 30-day trial only, then $14/mo minimum | Yes | Yes | Yes | Yes | Eliminated: not free |
| Umami | Self-hosted only (free) or Umami Cloud paid | Yes | Yes | Yes | Yes | Eliminated: requires a server you don't have |

### Why GoatCounter wins

1. **Genuinely free** for non-commercial personal use with no pageview cap.
2. **Single script tag** — `<script data-goatcounter="https://YOURSITE.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>`. Nothing else required for pageview tracking.
3. **No cookies, no GDPR notice needed** — GoatCounter explicitly states no cookie banner required.
4. **Dashboard is private by default** — you log in at `https://YOURSITE.goatcounter.com` with your credentials. There is an opt-in public view but it is off by default.
5. **Custom events via data attributes** — no extra JS library needed. Add `data-goatcounter-click="download-btn-hero"` to an anchor and GoatCounter tracks it automatically on click.
6. **Actual file download tracking** — GoatCounter uses `navigator.sendBeacon` under the hood, which fires reliably even when the browser navigates away to start a file download. This makes `.dmg` link tracking accurate.

### Limitation to acknowledge

GoatCounter's free tier is for personal/non-commercial use. Bar Ticket is a free app from Night District. This qualifies. If Bar Ticket ever goes paid/commercial, upgrade to a paid GoatCounter plan (€5/month) or migrate to Plausible.

---

## Setup Steps (Before Code Changes)

These are one-time account steps, not code:

1. Go to [goatcounter.com](https://www.goatcounter.com) and create a free account.
2. Choose a site code — recommend `bar-ticket` → your dashboard will be at `https://bar-ticket.goatcounter.com`.
3. Log in with your email. The dashboard is private — only you can see it with your credentials.
4. No domain verification step needed for GitHub Pages — GoatCounter identifies your site by the script's `data-goatcounter` URL.

---

## Technical Components Affected

**Repository:** `bar-ticket-site` (separate repo from the Swift app)
**Files to change:**
- `/Users/loganriedley/Developer/night-district/bar-ticket-site/index.html` — add script tag + data attributes to download links
- No changes needed to `assets/js/main.js` — GoatCounter's data attribute approach handles click events natively
- No changes to `assets/css/style.css`
- No changes to any Swift app files

**Deployment:** Commit to `bar-ticket-site` main branch → GitHub Pages deploys automatically via `.github/workflows/pages.yml`.

---

## Implementation Tasks

### Task 1 — Add GoatCounter script tag to `<head>` (Small)

**File:** `/Users/loganriedley/Developer/night-district/bar-ticket-site/index.html`

Add the GoatCounter script tag as the last item in `<head>`, after the existing stylesheet link (line 35). The `async` attribute ensures it does not block page render.

```html
<!-- Analytics — GoatCounter (cookieless, no GDPR banner required) -->
<script data-goatcounter="https://bar-ticket.goatcounter.com/count"
        async src="//gc.zgo.at/count.js"></script>
```

Place it at line 36, after `<link rel="stylesheet" href="assets/css/style.css">`.

This single tag handles **pageview tracking** automatically — every page load is counted.

---

### Task 2 — Tag the hero download button (Small)

**File:** `index.html`, line 84

Current element:
```html
<a href="assets/releases/BarTicket.dmg" class="nd-btn-primary text-center">
```

Change to:
```html
<a href="assets/releases/BarTicket.dmg"
   class="nd-btn-primary text-center"
   data-goatcounter-click="download-hero"
   data-goatcounter-title="Download — Hero Button">
```

The `data-goatcounter-click` attribute registers a **click event** named `download-hero`. Because GoatCounter uses `sendBeacon`, this fires before the browser starts the `.dmg` download, so it is reliable even though the page doesn't navigate away.

---

### Task 3 — Tag the CTA section download button (Small)

**File:** `index.html`, line 296

Current element:
```html
<a href="assets/releases/BarTicket.dmg" class="nd-btn-primary text-center">
```

Change to:
```html
<a href="assets/releases/BarTicket.dmg"
   class="nd-btn-primary text-center"
   data-goatcounter-click="download-cta"
   data-goatcounter-title="Download — CTA Section">
```

---

### Task 4 — Tag the navbar download button (Small)

**File:** `index.html`, line 56

Current element:
```html
<a href="#download" class="nd-btn-primary !py-2 !px-5 !text-sm">Download</a>
```

This links to `#download` anchor (scrolls to the CTA section), not directly to the `.dmg`. Tag it as a funnel step — it shows intent but is not a direct download:

```html
<a href="#download"
   class="nd-btn-primary !py-2 !px-5 !text-sm"
   data-goatcounter-click="nav-download-intent"
   data-goatcounter-title="Navbar Download Click">Download</a>
```

This completes the three-step funnel you can measure in GoatCounter:
- `nav-download-intent` — clicked the nav button (top-of-funnel intent)
- `download-hero` — clicked the hero CTA button (mid-funnel)
- `download-cta` — clicked the bottom CTA button (high-intent)

---

### Task 5 — (Optional) Consolidate download event name if you don't need hero vs. CTA split

If you prefer a single "total download clicks" metric rather than tracking which button was clicked, use the same event name on both download buttons:

```html
data-goatcounter-click="download-dmg"
```

Recommendation: **keep them separate** (Tasks 2 and 3 as written). Having `download-hero` vs `download-cta` tells you which placement converts better — that's actionable data.

---

## What You'll See in the GoatCounter Dashboard

After deploying, the GoatCounter dashboard at `https://bar-ticket.goatcounter.com` will show:

| Metric | How it appears |
|---|---|
| Page visits | Automatic — shown as pageview count on the main dashboard |
| Unique visitors (approximate) | Automatic — GoatCounter uses IP + User-Agent fingerprint, not cookies |
| Download button clicks | Under "Events" tab: `download-hero`, `download-cta` |
| Nav intent clicks | Under "Events" tab: `nav-download-intent` |
| Referrers | Automatic — where visitors came from |
| Browsers / OS | Automatic |

The dashboard is private. Only you can access it at `https://bar-ticket.goatcounter.com` with your login.

---

## A Note on "Actual DMG Download Counts"

There is an important distinction:

- **Download button clicks** = what GoatCounter tracks. This fires when the user clicks the link.
- **Actual completed DMG downloads** = impossible to track purely from a static site. Once the browser fetches the file from GitHub Pages' CDN, there is no callback to your analytics.

GoatCounter's `sendBeacon`-based click tracking is the closest reliable approximation available from a static site. The gap between click count and actual completed downloads is typically small (users rarely click the download link and then cancel before the file arrives). If you ever need true download completion counts, you would need to move the `.dmg` behind a redirect server that logs the hit before serving the file — that is out of scope for a GitHub Pages deployment.

**Short answer:** The plan gives you reliable download button click counts, which is the practical equivalent for a static site.

---

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| GoatCounter free tier terms change | Trivial to migrate — swap the script `src` and `data-goatcounter` URL for any other provider. Event names in data attributes are provider-agnostic concepts. |
| Ad blockers block GoatCounter | Unavoidable on any analytics platform. GoatCounter has a slightly better pass-through rate than Google Analytics but adblockers will still miss some visits. Accept as a known undercount. |
| Script tag slows page load | The `async` attribute prevents render-blocking. GoatCounter's `count.js` is ~3KB. Negligible impact. |
| GitHub Pages serves the .dmg and GoatCounter can't see the download | Acknowledged above — click tracking is the best approximation available from static hosting. |

---

## Testing Strategy

1. Deploy the changes to `bar-ticket-site` main branch.
2. Wait for GitHub Pages to redeploy (usually under 60 seconds).
3. Visit the live site at `https://night-district.github.io/bar-ticket-site/` in a normal browser window (not incognito — incognito tends to run more aggressive tracking protection).
4. Click each download button once.
5. Navigate to `https://bar-ticket.goatcounter.com` and verify:
   - The pageview count incremented.
   - The events `download-hero` and `download-cta` each show 1 hit under the Events tab.
6. Test in a second browser to confirm pageviews count separately.
7. Note: GoatCounter's dashboard updates in near-real-time (within a few seconds), so you don't need to wait.

---

## Bar Ticket Website

This plan is entirely website-side. No Swift app changes. No bar-ticket-site-developer sub-agent needed — the site is a single HTML file and the changes are straightforward data attribute additions.

**Repo:** `bar-ticket-site`
**Deploy:** Commit to main → GitHub Pages auto-deploys via `.github/workflows/pages.yml`
**No deploy script needed** — this is not a `.dmg` release, just an HTML change.

---

## Git Workflow

**Branch:** `feat/analytics` (already specified)

**Suggested commit message:**
```
add GoatCounter analytics script tag; tag hero and CTA download buttons with click events; tag navbar download intent click
```

**PR title:** `feat/analytics`

**Merge target:** `main` on `bar-ticket-site` repo (not the Swift app repo)

**Steps:**
```bash
cd /Users/loganriedley/Developer/night-district/bar-ticket-site
git checkout -b feat/analytics
# make the index.html changes
git add index.html
git commit -m "add GoatCounter analytics script tag; tag hero and CTA download buttons with click events; tag navbar download intent click"
git push -u origin feat/analytics
# create PR → squash merge → delete branch
```

---

## Implementation Scope

| Task | Scope | Estimated Time |
|---|---|---|
| Create GoatCounter account + choose site code | Small | 5 min |
| Add script tag to `<head>` | Small | 2 min |
| Add data attributes to 3 buttons | Small | 5 min |
| Deploy and verify in dashboard | Small | 10 min |
| **Total** | **Small** | **~22 min** |
