---
name: bar-ticket-site structure and deployment
description: Key facts about the bar-ticket-site repo structure, deployment, and file layout — avoids re-reading the repo from scratch each session
type: project
---

The bar-ticket-site is a fully static single-page site hosted on GitHub Pages at https://night-district.github.io/bar-ticket-site/. It auto-deploys on every push to main via `.github/workflows/pages.yml`.

Key files:
- `index.html` — the entire site. One HTML file. ~327 lines.
- `assets/js/main.js` — 13 lines, just a scroll fade-in IntersectionObserver
- `assets/css/style.css` — custom styles (glassmorphism, gradient text, ND brand colors)
- `assets/releases/BarTicket.dmg` — the actual DMG served directly from GitHub Pages
- `assets/video/demo.mp4` — autoplay hero demo video
- `assets/img/` — logo, editor logos for carousel

There are THREE clickable elements related to download:
1. Line 56 — Navbar "Download" button → links to `#download` anchor (not the .dmg directly)
2. Line 84 — Hero section download button → `href="assets/releases/BarTicket.dmg"` (direct .dmg)
3. Line 296 — CTA section download button → `href="assets/releases/BarTicket.dmg"` (direct .dmg)

**Why:** Needed for planning any website feature — knowing which elements exist and where they are prevents wrong file references.
**How to apply:** Use this when a feature touches the site so you don't have to re-read index.html to find button locations and file structure.

Deployment for HTML/JS/CSS changes: just commit to bar-ticket-site main. No deploy script needed.
Deployment for new .dmg releases: use the `/deploy` skill in the bar-ticket Swift repo.
