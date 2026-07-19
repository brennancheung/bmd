# bmd

**Beautiful Markdown** is a dedicated macOS Markdown reader. Native shell, web
rendering. One window, sidebar recents + pinned folders. The app itself is
always named **bmd**.

**Not** an editor. **Not** Quick Look (yet). **Not** Safari/Chrome.

## Why

Agent- and human-written Markdown is painful in Finder + Quick Look: narrow previews, bad tables, constant path-hunting. **bmd** opens `.md` files in a wide, resizable WKWebView and keeps a recent stack agents can feed by opening files after they write them.

## Status

Working proof of concept with native navigation and a fully offline rich
Markdown renderer.

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

Every successful Run, Test, or Profile scheme build also updates the stable
`/Applications/bmd.app` copy and registers it with Launch Services. Archives and
static analysis do not modify the installed app. To build, install, and ask
macOS to make bmd the default for Markdown in one command:

```bash
./scripts/install --set-default
```

The default association is attached to the stable `com.brennan.bmd` bundle
identifier. Replacing `/Applications/bmd.app` with a newer build keeps that
association. The same action is available later in bmd → Settings.

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

Use the checked-in rendering showcase to exercise syntax highlighting, math,
Mermaid, linked PNG/SVG files, inline SVG, tables, and failure states:

```bash
BMD_APPEARANCE=light ./scripts/render-headless.swift \
  examples/rendering-showcase.md build/headless/showcase-light.png
BMD_APPEARANCE=dark ./scripts/render-headless.swift \
  examples/rendering-showcase.md build/headless/showcase-dark.png
```

The default PNG is written to `build/headless/<file-name>.png`. Pass a second
argument to choose a different output path:

```bash
./scripts/render-headless.swift report.md /tmp/report.png
```

## Stack

- SwiftUI app target **bmd**  
- WKWebView + bundled marked, highlight.js, KaTeX, and Mermaid
- UserDefaults path lists for recents and pins

Relative local assets are served to WebKit through a read-only handler bounded
to the current Markdown directory. The direct-distribution build is not App
Sandboxed because a file-only sandbox grant cannot read sibling images.

## Verification

```bash
# Native build
xcodebuild -scheme bmd -configuration Debug -derivedDataPath build build

# Local-asset containment regression test
mkdir -p build/tests
xcrun swiftc -parse-as-library \
  bmd/LocalAssetSchemeHandler.swift tests/LocalAssetResolverTests.swift \
  -framework WebKit -framework UniformTypeIdentifiers \
  -o build/tests/local-asset-resolver-tests
build/tests/local-asset-resolver-tests

# Preferences persistence and zoom behavior
xcrun swiftc -parse-as-library \
  bmd/AppPreferences.swift tests/AppPreferencesTests.swift \
  -framework Combine \
  -o build/tests/app-preferences-tests
build/tests/app-preferences-tests
```

## License

Private / TBD.
