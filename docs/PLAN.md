# bmd plan

## MVP proof of concept

1. Single `Window` scene titled **bmd**  
2. `NavigationSplitView`:
   - Sidebar: Recents, Pinned folders  
   - Detail: `MarkdownWebView`  
3. Open Markdown → read UTF-8 → inject into marked → show HTML  
4. On open: push path onto recent stack (dedupe, cap list)  
5. Pin folder → show in sidebar (v1: list `.md` via enumerator when expanded/selected)  
6. Bundle offline viewer assets (no CDN at runtime)

## Default UX choices

- Default window ~1100×750 (wide enough for tables)  
- CSS: prose `max-width` for text; tables in horizontal scroll wrappers  
- One open file at a time in the detail pane (switching recents replaces content)  
- No splash marketing UI — empty state with Open / Drop / paste-path later  

## File access (sandbox)

- App sandbox ON  
- User-selected file read  
- When opening a file, start security-scoped access on the file URL  
- Load webview with `loadFileURL` / `allowingReadAccessTo` parent directory so relative images work  
- Phase 2: bookmark data in UserDefaults for recents/pins  

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
| CSS | Custom small theme | Control tables/width |
| Storage | UserDefaults | Recents/pins until bookmarks |

Swap marked for markdown-it later if GFM edge cases matter; keep the same `bmdRender` JS API.
