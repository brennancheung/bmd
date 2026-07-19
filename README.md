# bmd

Dedicated macOS Markdown reader. Native shell, web rendering. One window, sidebar recents + pinned folders.

**Not** an editor. **Not** Quick Look (yet). **Not** Safari/Chrome.

## Why

Agent- and human-written Markdown is painful in Finder + Quick Look: narrow previews, bad tables, constant path-hunting. **bmd** opens `.md` files in a wide, resizable WKWebView and keeps a recent stack agents can feed by opening files after they write them.

## Status

Phase 1 proof of concept — scaffold + basic open/render/recents.

Full intent and handoff notes: [`docs/CONTEXT.md`](docs/CONTEXT.md)  
Plan: [`docs/PLAN.md`](docs/PLAN.md)

## Requirements

- macOS 14+  
- Xcode 15+ (developed against Xcode 26 / recent toolchain)

## Build & run

```bash
cd /Users/brennan/code/bmd
open bmd.xcodeproj
```

Or:

```bash
xcodebuild -scheme bmd -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/bmd.app
```

## CLI

After the app exists (build or `/Applications/bmd.app`):

```bash
# from repo
./scripts/bmd path/to/file.md

# optional install
ln -sf /Users/brennan/code/bmd/scripts/bmd /usr/local/bin/bmd
bmd path/to/file.md
```

## Headless rendering

Render Markdown through the same bundled HTML, CSS, marked.js, and system WebKit
without launching `bmd` or creating a visible window:

```bash
./scripts/render-headless.swift examples/welcome.md
```

The default PNG is written to `build/headless/<file-name>.png`. Pass a second
argument to choose a different output path:

```bash
./scripts/render-headless.swift report.md /tmp/report.png
```

## Stack

- SwiftUI app target **bmd**  
- WKWebView + bundled `Resources/viewer` (marked.js + CSS)  
- UserDefaults for recents / pins (bookmarks later)

## License

Private / TBD.
