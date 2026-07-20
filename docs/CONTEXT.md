# bmd — session context & handoff

**Project name:** `bmd` (Beautiful Markdown in repository-facing prose; the product UI is literally **bmd**)
**Location:** `/Users/brennan/code/bmd`  
**Not related to:** `/Users/brennan/code/QLMarkdown` (inspiration only; do not build inside that repo)

---

## Intent

Dedicated macOS app for reading Markdown written by agents and humans. Native shell + real browser rendering. Not a full editor. Not Safari/Chrome. Not a C/C++ markdown stack.

Primary pain points with existing Quick Look Markdown tools (esp. QLMarkdown):

1. **Window too narrow** — tables cropped; no good control over width  
2. **Hunting files** — agents dump `.md` into folders; copy path → Finder → spacebar is friction  
3. **Heavy native stack** — cmark, Highlight, XPC, settings zoo for little daily value  

## Product shape (agreed)

| In v1 | Deferred |
|-------|----------|
| Single window app (SwiftUI + WKWebView) | Quick Look extension |
| Persistent menu-bar access to Updates and Open | Full background agent automation |
| Open `.md` via Open dialog, drag-drop, `open -a bmd`, CLI `bmd` | Multi-window per file |
| Sidebar: **Updates** + stable **Open** + **Projects** | Full Finder replacement |
| Filename-first fuzzy search across the active project or all projects | File-content search |
| Agents open files with this app → they join Open without reordering it | YAML/Rmd/Quarto science stack |
| Web markdown, syntax, math, and Mermaid | Full editing workflows |
| Table-friendly CSS + centered, full-height window | App Store sandboxing/bookmarks |
| Relative local images via bounded local URL scheme | Quick Look extension |

### Architecture

```
Native (Swift)
  - screen-safe window placement and native reader controls
  - agent updates, stable open documents, history, project-opened files, and search index
  - recursive project discovery and dedicated current-file watching
  - file access + WebKit document read root
  - pass markdown text + base directory into webview

Web (bundled Resources/viewer)
  - marked.js → HTML
  - theme CSS (prose max-width, tables scroll/expand)
  - highlight.js, KaTeX, Mermaid, and light/dark themes
```

**No Electron. No Safari. No system Chrome.** Only WKWebView inside bmd.

### Integration boundary (keep thin for v1)

Swift owns:

- Which file is open  
- Reading file bytes  
- Updates, Open, history, project, and opened-file lists
- Global and active-project fuzzy search across indexed Markdown paths
- Serving relative assets from the current file’s directory

JS owns:

- Markdown → HTML  
- Presentation  

Bridge: load local `index.html`, then `window.bmdRender(markdownSource)` via `evaluateJavaScript`. Optional later: `WKScriptMessageHandler` for link clicks, outline, etc.

### CLI

`bmd` should be easy to type:

```bash
bmd path/to/file.md
```

Script at `scripts/bmd` uses `open -a bmd` (or the built app path). Agents can:

```bash
bmd /path/to/report.md
```

so the file becomes current and joins the stable Open working set.

### Registration

- Document types / UTIs for Markdown (`.md`, `.markdown`, common UTIs)  
- App is a **viewer** (not claiming to be a full editor)  
- Quick Look: **not in v1** (phase 2+)

### Origin discussion (QLMarkdown)

QLMarkdown = host app + QL appex + cmark-gfm + custom C extensions + Highlight/Enry + XPC.  
We studied it only to know how QL works and what to *avoid*. bmd is greenfield and separate.

---

## Phases

### Phase 1 — POC (this scaffold)

- [x] Repo + handoff docs  
- [x] SwiftUI single window  
- [x] Sidebar Updates + Open + Projects hierarchy
- [x] WKWebView + marked  
- [x] Open file, render, and remember a stable working set
- [x] Number the first nine Open positions and support adjacent keyboard traversal
- [x] Search all indexed Markdown globally or within the active project
- [x] Debug build succeeds (`xcodebuild -scheme bmd`)  
- [ ] Optional: install `bmd` on PATH (`ln -s …/scripts/bmd /usr/local/bin/bmd`)  
- [x] Human smoke-test: open documents, switch, navigate Back, and restore scroll

### Phase 2 — Daily driver

- [x] Centered, full-visible-height window with semantic width presets
- [x] Configurable zoom and readable/table widths
- [x] Native View menu zoom commands (Command-plus/minus/zero)
- [x] Stable `/Applications/bmd.app` install/update workflow
- [x] Set bmd as the Markdown default from Settings or the installer
- [x] Keep Updates, Open, navigation, Settings, and Quit available from the menu bar
- [x] Watched folders surface created/modified files without listing every Markdown file
- [x] Auto-refresh the current Markdown file after external changes
- [x] Search by partial filename with `⇧⌘O` globally or `⇧⌘P` in the active project
- Optional folder grants/bookmarks if App Store sandboxing is added later
- [x] Better CSS, light/dark
- [x] Syntax highlighting with highlight.js
- Click external links in default browser; internal anchors work  

The direct-distribution build is intentionally not App Sandboxed. A file-only
Powerbox grant lets bmd read the selected Markdown file but not its sibling
images. Re-enabling the sandbox requires an explicit folder-grant workflow and
security-scoped directory bookmarks.

### Phase 3 — Quick Look (optional)

- Appex returning HTML from same viewer pipeline  
- Don’t rely on QL for wide tables  

### Phase 4 — Nice-to-haves

- [x] Math with offline KaTeX
- [x] Mermaid diagrams
- “Open from clipboard” if paste looks like a path  
- Optional notification or auto-open policy for watched-folder activity
- Outline / TOC sidebar section  

---

## How to resume (next session)

```bash
cd /Users/brennan/code/bmd
open bmd.xcodeproj
# or
xcodebuild -scheme bmd -configuration Debug build
```

Read this file first, then `docs/PLAN.md` and `README.md`.  
Do not work in `QLMarkdown/`.

Build output app: look under Xcode DerivedData or `build/` if configured.

Smoke test:

1. Run bmd  
2. Open an example `.md`  
3. Confirm the document joins Open without moving existing rows
4. Resize window; confirm tables not trapped forever in a phone column  
5. `scripts/bmd /path/to/file.md` once app is built/installed  

---

## Explicit non-goals (v1)

- Editing / saving markdown  
- Multiple document windows  
- Parity with GitHub rendering  
- C/C++ markdown engines  
- Settings XPC services  
- Notarization polish (later)  
