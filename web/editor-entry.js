import { basicSetup } from "codemirror";
import { EditorView, keymap } from "@codemirror/view";
import { markdown } from "@codemirror/lang-markdown";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { Compartment, Prec } from "@codemirror/state";
import { tags } from "@lezer/highlight";
import { Vim, vim } from "@replit/codemirror-vim";

const palettes = {
  light: {
    background: "#ffffff",
    foreground: "#1f2328",
    gutter: "#f6f8fa",
    gutterText: "#8c959f",
    activeLine: "#f6f8fa",
    selection: "#b6d7ff",
    cursor: "#0969da",
    comment: "#6e7781",
    keyword: "#cf222e",
    string: "#0a3069",
    number: "#0550ae",
    heading: "#8250df",
    link: "#0969da",
    punctuation: "#57606a"
  },
  dark: {
    background: "#0d1117",
    foreground: "#e6edf3",
    gutter: "#161b22",
    gutterText: "#7d8590",
    activeLine: "#161b22",
    selection: "#264f78",
    cursor: "#58a6ff",
    comment: "#8b949e",
    keyword: "#ff7b72",
    string: "#a5d6ff",
    number: "#79c0ff",
    heading: "#d2a8ff",
    link: "#58a6ff",
    punctuation: "#8b949e"
  }
};

function editorTheme(appearance) {
  const dark = appearance === "dark";
  const palette = dark ? palettes.dark : palettes.light;
  const theme = EditorView.theme({
    "&": {
      height: "100%",
      color: palette.foreground,
      backgroundColor: palette.background,
      fontSize: "14px"
    },
    ".cm-scroller": {
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      lineHeight: "1.6",
      overflow: "auto",
      paddingTop: "24px"
    },
    ".cm-content": {
      caretColor: palette.cursor,
      padding: "0 0 64px"
    },
    ".cm-line": {
      padding: "0 24px"
    },
    ".cm-cursor, .cm-dropCursor": {
      borderLeftColor: palette.cursor
    },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
      backgroundColor: palette.selection
    },
    ".cm-activeLine": {
      backgroundColor: palette.activeLine
    },
    ".cm-gutters": {
      backgroundColor: palette.gutter,
      color: palette.gutterText,
      border: "none"
    },
    ".cm-activeLineGutter": {
      backgroundColor: palette.activeLine,
      color: palette.foreground
    },
    ".cm-panels": {
      backgroundColor: palette.gutter,
      color: palette.foreground
    },
    ".cm-panels.cm-panels-top": {
      borderBottom: "1px solid color-mix(in srgb, currentColor 18%, transparent)"
    },
    ".cm-searchMatch": {
      backgroundColor: dark ? "#9e6a03aa" : "#fff8c5",
      outline: "1px solid " + (dark ? "#d29922" : "#d4a72c")
    },
    ".cm-searchMatch.cm-searchMatch-selected": {
      backgroundColor: dark ? "#bb8009" : "#fae17d"
    },
    ".cm-fat-cursor": {
      background: palette.cursor,
      color: palette.background
    }
  }, { dark });

  const highlighting = HighlightStyle.define([
    { tag: [tags.comment, tags.quote], color: palette.comment, fontStyle: "italic" },
    { tag: [tags.keyword, tags.bool, tags.null, tags.atom], color: palette.keyword },
    { tag: [tags.string, tags.inserted], color: palette.string },
    { tag: [tags.number, tags.integer, tags.float], color: palette.number },
    { tag: [tags.heading, tags.strong], color: palette.heading, fontWeight: "650" },
    { tag: [tags.link, tags.url], color: palette.link, textDecoration: "underline" },
    { tag: [tags.meta, tags.processingInstruction, tags.punctuation], color: palette.punctuation },
    { tag: tags.emphasis, fontStyle: "italic" },
    { tag: tags.deleted, color: palette.keyword, textDecoration: "line-through" }
  ]);

  return [theme, syntaxHighlighting(highlighting)];
}

let activeEditor = null;
let exCommandsInstalled = false;

function installExCommands() {
  if (exCommandsInstalled) return;
  exCommandsInstalled = true;
  Vim.defineEx("write", "w", function () {
    activeEditor?.requestSave(false);
  });
  Vim.defineEx("wq", "wq", function () {
    activeEditor?.requestSave(true);
  });
  Vim.defineEx("quit", "q", function () {
    activeEditor?.requestPreviewIfClean();
  });
}

class BMDEditorController {
  constructor(parent, options) {
    this.appearanceCompartment = new Compartment();
    this.vimCompartment = new Compartment();
    this.suppressChanges = false;
    this.onChange = options.onChange;
    this.onCommand = options.onCommand;

    const saveKeymap = Prec.highest(keymap.of([
      {
        key: "Mod-s",
        run: () => {
          this.requestSave(false);
          return true;
        },
        preventDefault: true
      },
      {
        key: "Mod-Enter",
        run: () => {
          this.requestSave(true);
          return true;
        },
        preventDefault: true
      }
    ]));

    this.view = new EditorView({
      doc: options.text || "",
      parent,
      extensions: [
        basicSetup,
        markdown(),
        EditorView.lineWrapping,
        saveKeymap,
        this.appearanceCompartment.of(editorTheme(options.appearance)),
        this.vimCompartment.of(options.vimEnabled ? vim() : []),
        EditorView.updateListener.of((update) => {
          if (!update.docChanged || this.suppressChanges) return;
          this.onChange(update.state.doc.toString());
        }),
        EditorView.domEventHandlers({
          focus: () => {
            activeEditor = this;
            return false;
          }
        })
      ]
    });

    installExCommands();
    activeEditor = this;
  }

  get text() {
    return this.view.state.doc.toString();
  }

  setText(text) {
    if (text === this.text) return;
    this.suppressChanges = true;
    this.view.dispatch({
      changes: { from: 0, to: this.view.state.doc.length, insert: text }
    });
    this.suppressChanges = false;
  }

  setAppearance(appearance) {
    this.view.dispatch({
      effects: this.appearanceCompartment.reconfigure(editorTheme(appearance))
    });
  }

  setVimEnabled(enabled) {
    this.view.dispatch({
      effects: this.vimCompartment.reconfigure(enabled ? vim() : [])
    });
  }

  snapshotPosition() {
    return {
      anchor: this.view.state.selection.main.anchor,
      head: this.view.state.selection.main.head,
      scrollTop: this.view.scrollDOM.scrollTop,
      scrollLeft: this.view.scrollDOM.scrollLeft
    };
  }

  restorePosition(position) {
    if (!position) return;
    const length = this.view.state.doc.length;
    const anchor = Math.min(Math.max(Number(position.anchor) || 0, 0), length);
    const head = Math.min(Math.max(Number(position.head) || anchor, 0), length);
    this.view.dispatch({ selection: { anchor, head } });
    window.requestAnimationFrame(() => {
      this.view.scrollDOM.scrollTop = Number(position.scrollTop) || 0;
      this.view.scrollDOM.scrollLeft = Number(position.scrollLeft) || 0;
    });
  }

  requestSave(andPreview) {
    this.onCommand(andPreview ? "saveAndPreview" : "save", this.text);
  }

  requestPreviewIfClean() {
    this.onCommand("previewIfClean", this.text);
  }

  focus() {
    activeEditor = this;
    this.view.focus();
  }

  destroy() {
    if (activeEditor === this) activeEditor = null;
    this.view.destroy();
  }
}

window.BMDEditorController = BMDEditorController;
