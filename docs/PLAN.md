# bmd plan

## MVP proof of concept

1. Single `Window` scene titled **bmd**  
2. `NavigationSplitView`:
   - Sidebar: global Watched activity, Recents, and project-opened files
   - Detail: `MarkdownWebView`  
3. Open Markdown → read UTF-8 → inject into marked → show HTML  
4. On open: push path onto recent stack (dedupe, cap list)  
5. Add folder → persist it, recursively list Markdown, and watch for changes
6. Bundle offline viewer assets (no CDN at runtime)

## Default UX choices

- New windows use the current display's full visible height and a centered 1680 pt Wide preset
- Window placement is recalculated from the available screens; absolute coordinates are not persisted
- Default zoom 125%; semantic width preset, zoom, prose width, and table width are configurable
- Appearance follows the macOS system setting by default, with explicit light/dark overrides
- CSS: readable prose track; tables share its left edge and can grow to the right
- One open file at a time in the detail pane (switching recents replaces content)  
- No splash marketing UI — empty state with Open / Drop / paste-path later  

## Daily-driver usability milestone

- [x] Remove document-level horizontal overflow
- [x] Align tables with the prose start while giving them a wider maximum region
- [x] Add View → Zoom In/Out/Actual Size and Command-plus/minus/zero
- [x] Add visible toolbar access to Settings and appearance controls
- [x] Add Settings for default zoom, prose/table widths, and semantic window width
- [x] Disable stale frame restoration and keep windows on-screen across monitor changes
- [x] Install every scheme build to a stable `/Applications/bmd.app`
- [x] Register or select bmd as the macOS default Markdown viewer
- [x] Add persistent menu-bar access to Watched, Recents, Open, Settings, and Quit

## Watched-folder workflow

- [x] Persist projects added from the sidebar, Open panel, drop target, or legacy pins
- [x] Recursively scan `.md`, `.markdown`, `.mdown`, `.mkd`, and `.mdwn` files
- [x] Ignore `node_modules` by default and support configurable exact-name rules
- [x] Watch projects with recursive FSEvents
- [x] Show created, modified, and currently open files in one global Watched section
- [x] Limit Watched and Recents independently through Settings
- [x] Show only opened files under each project
- [x] Auto-refresh the current file after external writes and atomic replacements
- [x] Provide Copy Path and Reveal in Finder context actions
- [ ] Add optional glob rules and activity retention controls after real-world use

## File access (sandbox)

- Direct-distribution builds are not App Sandboxed. A file-only sandbox grant
  cannot read sibling images, which conflicts with the primary `bmd file.md`
  workflow.
- A read-only URL handler serves only normalized paths contained in the current
  Markdown file's directory; WebKit does not receive general `file:` access.
- Bundled fonts are served through a read-only viewer-resource URL scheme.
- If App Store sandboxing becomes a goal, add an explicit folder-access grant
  and security-scoped bookmark before re-enabling the sandbox.

## Rendering milestone

Upgrade the offline viewer from basic Markdown to the document formats used in
real agent output. Keep every renderer bundled in the app so opening a document
never depends on a CDN or network connection.

- [x] Match the macOS light/dark appearance for prose, code, math, and diagrams
- [x] Highlight fenced code blocks with explicit languages and safe fallback
- [x] Render inline and display math with KaTeX
- [x] Render fenced `mermaid` blocks as diagrams
- [x] Display inline SVG and relative `.svg` image files
- [x] Resolve relative raster image files from the Markdown file's directory
- [x] Preserve useful error output when math or diagram syntax is invalid
- [x] Cover every capability in one checked-in rendering fixture

Acceptance checks:

1. Open the rendering fixture in both light and dark macOS appearances.
2. Confirm Swift, JavaScript, shell, JSON, and unknown-language code fences stay readable.
3. Confirm inline math, display math, and a Mermaid flowchart render without network access.
4. Confirm relative PNG and SVG files render from disk rather than embedded data URLs.
5. Confirm an invalid Mermaid block shows a local error without blanking the document.

## Agent workflow

Agents write markdown, then:

```bash
bmd "$OUT/report.md"
```

App activates, opens file, recent stack updates. Human uses sidebar to jump back.

## Tech choices (v1)

| Piece | Choice | Why |
|-------|--------|-----|
| UI | SwiftUI | Fast shell |
| Render surface | WKWebView | Real browser engine |
| MD parser | marked 15 (vendored) | Simple, good enough GFM-ish |
| Code | highlight.js (vendored) | Broad language coverage with no runtime network |
| Math | KaTeX (vendored) | Fast offline TeX rendering |
| Diagrams | Mermaid (vendored) | Standard fenced-diagram syntax and SVG output |
| CSS | Custom small theme | Control tables/width |
| Storage | UserDefaults | Simple path lists for direct distribution |

Swap marked for markdown-it later if GFM edge cases matter; keep the same `bmdRender` JS API.
