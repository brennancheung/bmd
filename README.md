<p align="center">
  <img src="assets/bmd-icon.png" width="180" alt="Beautiful Markdown navy-and-gold BMD application icon">
</p>

<h1 align="center">bmd — Beautiful Markdown</h1>

<p align="center">
  <strong>A native Markdown reader for Mac, built for working with agents.</strong>
</p>

<p align="center">
  Find the document. Switch to it. Keep reading while it changes.
</p>

## Markdown moves fast now

Working with agents changed how much Markdown I read. Plans, research, reports,
implementation notes, and handoffs were constantly appearing across different
project folders.

The files were easy to create, but strangely tedious to consume. I kept
navigating back to folders, hunting for the right document, switching windows,
resizing the viewer, horizontally scrolling through cropped tables, and manually
refreshing files as agents continued writing. Each interruption only cost a few
seconds. Repeated all day, those seconds added up—and kept pulling me out of the
work.

I built **bmd** to reduce that friction. It watches the folders where agents
work, surfaces documents as they are created or modified, keeps project files
easy to switch between, and refreshes the document you are already reading.

The goal is simple: spend less time managing Markdown files and more time
understanding what is in them.

## Stay in the flow

### The file comes to you

Add the folders where your agents work. When a Markdown file is created or
updated, it appears in **Watched**—no trip through Finder required.

### Switch without searching

Move between watched files, recent documents, and project files from one
sidebar. The menu-bar app keeps the latest documents close even when the main
window is closed.

### Follow work as it changes

Keep a document open while an agent updates it. bmd notices changes and refreshes
the page automatically, so you can keep reading instead of reopening the file.

### Open it ready to read

New windows open centered, full-height, and wide enough for the sidebar and the
document. Reading width, table width, zoom, sidebar sizing, and list counts can
all be adjusted without dragging the same window into shape every time.

## Built for the Markdown agents actually produce

Agent output is rarely just a few paragraphs of prose. bmd renders the technical
documents that show up in real projects:

- syntax-highlighted code blocks
- wide GitHub Flavored Markdown tables
- Mermaid diagrams
- inline and display math
- SVG, PNG, JPEG, GIF, and WebP images referenced with local relative paths
- light and dark appearances that follow macOS automatically

Everything needed to render a document is bundled with the app. Reading works
offline, and local assets stay local.

## Try bmd

> **Current status:** bmd is in early development for macOS 14 Sonoma and newer.
> The daily reading workflow works, but packaged releases, signing,
> notarization, and a public license have not been finalized.

Clone the repository and install the current development build:

```bash
git clone https://github.com/brennancheung/bmd.git
cd bmd
./scripts/install
```

To make bmd the default application for common Markdown files:

```bash
./scripts/install --set-default
```

The application is installed at `/Applications/bmd.app`. Updates replace that
stable application, so macOS should not require you to choose the default
Markdown opener again after every build.

Once bmd is open:

1. Add the project folders where agents create Markdown.
2. Let the agent write files normally.
3. Open the latest document from **Watched**.
4. Keep reading while bmd follows subsequent changes.

## Open a document from an agent or script

The repository includes a command-line entry point:

```bash
./scripts/bmd path/to/report.md
```

You can optionally place it on your `PATH`:

```bash
ln -sf "$PWD/scripts/bmd" /usr/local/bin/bmd
bmd path/to/report.md
```

Opening a document places it at the top of Watched and Recents. If the document
belongs to an added project, bmd also keeps it under that project for quick
switching later.

## How the sidebar works

- **Watched** shows the latest Markdown files created, modified, or opened in
  the folders you watch.
- **Recents** keeps documents you opened across all projects close at hand.
- **Projects** remembers the documents you opened inside each project without
  turning the sidebar into another enormous file tree.

Project folders are watched recursively, but `node_modules`, hidden folders,
and application packages are skipped. Additional folder names can be ignored
from Settings. Right-click any file to copy its complete path or reveal it in
Finder.

## Built for macOS

bmd is a native SwiftUI application with a focused reading surface. It supports
the standard zoom shortcuts, system light and dark appearances, project-aware
file menus, and a menu-bar companion for opening recent work quickly.

Closing the reader window leaves bmd available in the menu bar. Choose
**Quit bmd** when you want to stop the application completely.

<details>
<summary><strong>Architecture and local file access</strong></summary>

bmd uses SwiftUI for its window, navigation, settings, commands, and persistent
state. A `WKWebView` reading surface uses bundled copies of marked,
highlight.js, KaTeX, and Mermaid to render documents without a network
connection.

The direct-distribution build is intentionally not App Sandboxed because a
file-only Powerbox grant cannot read sibling images referenced by a Markdown
document. WebKit still receives no general `file:` access. Local resources are
served through a read-only URL handler after normalized-path containment checks
against the current document directory.

</details>

## Development

Requirements:

- macOS 14 Sonoma or newer
- Xcode 15 or newer

Open the Xcode project:

```bash
open bmd.xcodeproj
```

Run the native, state, watcher, asset-containment, and rendering checks:

```bash
./scripts/test
```

Useful project references:

- [`docs/CONTEXT.md`](docs/CONTEXT.md) explains the product intent and
  architecture.
- [`docs/PLAN.md`](docs/PLAN.md) tracks current milestones and the roadmap.
- [`examples/rendering-showcase.md`](examples/rendering-showcase.md) exercises
  the supported rendering formats.

The rendering showcase can also be captured without opening an application
window:

```bash
BMD_APPEARANCE=light ./scripts/render-headless.swift \
  examples/rendering-showcase.md build/headless/showcase-light.png

BMD_APPEARANCE=dark ./scripts/render-headless.swift \
  examples/rendering-showcase.md build/headless/showcase-dark.png
```

## Roadmap

Near-term work includes interaction polish, testing with larger real-world
projects, release packaging, code signing and notarization, and deciding whether
a Quick Look extension belongs in the product.

## License

A public license has not been selected yet. Until a `LICENSE` file is added, the
source is available for inspection but no additional rights are granted.
