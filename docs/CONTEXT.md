# bmd — session context & handoff

**Project name:** `bmd` (Brennan's Markdown — never put that long name in UI/titles; product is literally **bmd** everywhere)  
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
| Open `.md` via Open dialog, drag-drop, `open -a bmd`, CLI `bmd` | Multi-window per file |
| Sidebar: **recent files** + **pinned folders** | Full Finder replacement |
| Agents open files with this app → they land on recent stack | YAML/Rmd/Quarto science stack |
| Web markdown (HTML/JS/CSS ecosystem) | Mermaid (later if needed) |
| Table-friendly CSS + wide default window | Math (easy add via KaTeX later) |
| Relative local images via file base URL | Syntax highlight polish (add highlight.js/Shiki soon) |

### Architecture

```
Native (Swift)
  - window, sidebar, recents, pins, open file/folder
  - sandbox + security-scoped access
  - pass markdown text + base directory into webview

Web (bundled Resources/viewer)
  - marked.js → HTML
  - theme CSS (prose max-width, tables scroll/expand)
  - future: highlight, math, mermaid
```

**No Electron. No Safari. No system Chrome.** Only WKWebView inside bmd.

### Integration boundary (keep thin for v1)

Swift owns:

- Which file is open  
- Reading file bytes  
- Recent/pin lists  
- Granting WKWebView read access to the file’s directory  

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

so the file becomes current + top of recents.

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
- [x] Sidebar recents + pins  
- [x] WKWebView + marked  
- [x] Open file, render, remember recents  
- [x] Debug build succeeds (`xcodebuild -scheme bmd`)  
- [ ] Optional: install `bmd` on PATH (`ln -s …/scripts/bmd /usr/local/bin/bmd`)  
- [ ] Human smoke-test: open `examples/welcome.md`, check tables/recents

### Phase 2 — Daily driver

- Remember window frame  
- Pin folders: list contained `.md` files  
- Security-scoped bookmarks so pins/recents survive relaunch under sandbox  
- Better CSS, light/dark  
- Syntax highlighting (highlight.js or Shiki)  
- Click external links in default browser; internal anchors work  

### Phase 3 — Quick Look (optional)

- Appex returning HTML from same viewer pipeline  
- Don’t rely on QL for wide tables  

### Phase 4 — Nice-to-haves

- Math (KaTeX offline)  
- Mermaid  
- “Open from clipboard” if paste looks like a path  
- Watch pinned folder / auto-open newest  
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
3. Confirm sidebar recent entry  
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
