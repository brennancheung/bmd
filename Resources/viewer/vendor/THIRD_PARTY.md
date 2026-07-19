# Bundled viewer libraries

The viewer is fully offline. These browser builds are copied into the app
bundle and are not loaded from a CDN at runtime.

| Library | Version | License | Source |
|---------|---------|---------|--------|
| marked | 15.0.12 | MIT | https://github.com/markedjs/marked |
| highlight.js | 11.11.1 | BSD-3-Clause | https://github.com/highlightjs/highlight.js |
| KaTeX | 0.18.1 | MIT | https://github.com/KaTeX/KaTeX |
| Mermaid | 11.16.0 | MIT | https://github.com/mermaid-js/mermaid |

The highlight.js, KaTeX, and Mermaid license texts are stored beside their
vendored distributions. The marked license header is retained in
`marked.min.js`.
