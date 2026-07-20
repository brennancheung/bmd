<p align="center">
  <img src="assets/bmd-icon.png" width="180" alt="Beautiful Markdown navy-and-gold BMD application icon">
</p>

<h1 align="center">bmd — Beautiful Markdown</h1>

<p align="center">
  A native macOS reader for the Markdown files people and coding agents keep writing.
</p>

`bmd` is a focused Markdown viewer for macOS. It opens documents in a wide,
readable native window, renders modern technical Markdown entirely offline, and
watches project folders so newly generated files are already waiting in the
sidebar.

The application is a reader, not an editor. The repository and product name are
**Beautiful Markdown**; the installed application is simply **bmd**.

> **Status:** Early development. The core reader and daily workflow work on
> macOS 14 and newer, but releases, signing, notarization, and a public license
> have not been finalized.

## Why bmd exists

Markdown is often produced somewhere other than the app used to read it. Coding
agents write plans and reports into project folders. Commands generate logs and
documentation. Finder and Quick Look make those documents possible to inspect,
but the repeated navigation, narrow layouts, clipped tables, and manual refresh
cycle add friction.

`bmd` is designed around that handoff:

1. Add the folders where Markdown is produced.
2. Let tools and agents create or update files normally.
3. Open `bmd` and select the latest file from **Watched**.
4. Keep reading while the current document refreshes automatically.

## Highlights

- **Native macOS shell.** SwiftUI navigation with a `WKWebView` reading surface;
  no Electron and no external browser window.
- **Wide by default.** New windows open centered at the display's full visible
  height. Width uses semantic presets and remains safe when monitors change.
- **Project-aware watching.** Recursive FSEvents monitoring surfaces created and
  modified Markdown without listing every file in every project.
- **Live current document.** The open file automatically reloads when another
  process replaces or modifies it.
- **Menu-bar access.** Watched and recently opened files remain one click away,
  even after the main reader window is closed.
- **Rich offline rendering.** Bundled marked, highlight.js, KaTeX, and Mermaid
  handle GFM-style Markdown, syntax highlighting, math, and diagrams without a
  network connection.
- **Local assets.** Relative PNG, JPEG, GIF, WebP, and SVG references resolve
  from the document directory through a bounded read-only URL handler.
- **System appearance.** Light and dark themes follow macOS automatically, with
  manual overrides in Settings.
- **Reader controls.** Command-plus, Command-minus, and Command-zero control
  zoom. Reading width, table width, sidebar label size, sidebar counts, and
  watch ignores are configurable.

## Sidebar model

The sidebar separates three different questions instead of mixing them into one
large file tree:

| Section | What it answers |
|---|---|
| **Watched** | Which Markdown files were created, modified, or opened most recently? |
| **Recents** | Which files did I open most recently across the app? |
| **Projects** | Which files have I opened inside each added project? |

The Watched section shows five files by default. Projects deliberately show only
opened files; recursive scanning is used for change detection, not as a Finder
replacement. Right-click any file row to copy its complete path or reveal it in
Finder.

Recent files inside projects display their project name and project-relative
path. Clicking a project name expands or collapses its opened files. Each
project row also provides a Markdown-only file picker rooted at that project and
a Reveal in Finder button.

`node_modules` is ignored by default. Hidden folders and application packages
are always skipped. Additional exact folder names can be added in Settings.

The BMD menu-bar item keeps the five most recent Watched files and five recently
opened files close at hand. It also provides Open, Add Project, Refresh,
Settings, and Quit commands. Closing the reader window leaves bmd running in the
menu bar; use **Quit bmd** when you want to stop the application completely.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 15 or newer to build from source

## Build and install

Clone the repository and open the Xcode project:

```bash
git clone https://github.com/brennancheung/bmd.git
cd bmd
open bmd.xcodeproj
```

Or build from the command line:

```bash
xcodebuild -scheme bmd -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/bmd.app
```

The shared Xcode scheme keeps a stable development build at
`/Applications/bmd.app`. The same update can be performed explicitly:

```bash
./scripts/install
```

To install and ask macOS to make bmd the default application for common Markdown
types:

```bash
./scripts/install --set-default
```

The file association is attached to the stable `com.brennan.bmd` bundle
identifier, so replacing `/Applications/bmd.app` with a new build does not
normally require rebinding the default application.

## Open files from agents and scripts

The repository includes a small shell entry point:

```bash
./scripts/bmd path/to/report.md
```

Optionally place it on your `PATH`:

```bash
ln -sf "$PWD/scripts/bmd" /usr/local/bin/bmd
bmd path/to/report.md
```

Opening a file places it at the top of Watched and Recents. If the file belongs
to an added project, it also becomes available under that project.

## Rendering support

The checked-in showcase covers the formats used by technical and agent-authored
documents:

- headings, lists, blockquotes, links, and GFM tables
- fenced code with language-aware syntax highlighting
- inline and display math through KaTeX
- Mermaid diagrams with visible local error states
- inline SVG and relative SVG/raster images
- light and dark themes

The same viewer can render headlessly for regression checks without opening an
application window:

```bash
BMD_APPEARANCE=light ./scripts/render-headless.swift \
  examples/rendering-showcase.md build/headless/showcase-light.png

BMD_APPEARANCE=dark ./scripts/render-headless.swift \
  examples/rendering-showcase.md build/headless/showcase-dark.png
```

## Architecture

```text
SwiftUI application
├── window placement and native commands
├── Watched, Recents, and Projects state
├── recursive project watcher and current-file watcher
├── UserDefaults persistence
└── WKWebView bridge
    ├── bundled Markdown renderer
    ├── syntax, math, and diagram renderers
    └── bounded local-asset URL scheme
```

The direct-distribution build is intentionally not App Sandboxed. A file-only
Powerbox grant cannot read sibling images referenced by a Markdown document.
WebKit still receives no general `file:` access: local resources are served only
after normalized-path containment checks against the current document directory.

## Development and verification

Run the complete native, state, watcher, asset-containment, and rendering checks:

```bash
./scripts/test
```

Useful project references:

- [`docs/CONTEXT.md`](docs/CONTEXT.md) — product intent and architecture handoff
- [`docs/PLAN.md`](docs/PLAN.md) — current milestones and roadmap
- [`examples/rendering-showcase.md`](examples/rendering-showcase.md) — rendering fixture

## Roadmap

Near-term work includes interaction polish, larger real-world project testing,
release packaging, code signing and notarization, and deciding whether a Quick
Look extension belongs in the product.

## License

A public license has not been selected yet. Until a `LICENSE` file is added, the
source is available for inspection but no additional rights are granted.
