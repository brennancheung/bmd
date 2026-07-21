/* global BMDEditorController, hljs, marked, mermaid, renderMathInElement */
(function () {
  "use strict";

  var editorController = null;
  var editorDocumentIdentifier = null;
  var editorPositions = {};

  function sendEditorMessage(type, text) {
    var handler = window.webkit && window.webkit.messageHandlers
      ? window.webkit.messageHandlers.bmdEditor
      : null;
    if (!handler || typeof handler.postMessage !== "function") return;
    handler.postMessage({
      type: type,
      text: text || "",
      documentIdentifier: editorDocumentIdentifier || ""
    });
  }

  function showSurface(mode) {
    var content = document.getElementById("content");
    var editor = document.getElementById("editor");
    var empty = document.getElementById("empty");
    document.documentElement.dataset.mode = mode;
    if (empty) empty.hidden = true;
    if (content) content.hidden = mode !== "preview";
    if (editor) editor.hidden = mode !== "editing";
  }

  function configureMarked() {
    if (typeof marked === "undefined") return;
    marked.setOptions({
      gfm: true,
      breaks: false,
    });
  }

  function wrapTables(root) {
    root.querySelectorAll("table").forEach(function (table) {
      if (table.parentElement && table.parentElement.classList.contains("table-wrap")) {
        return;
      }
      var wrap = document.createElement("div");
      wrap.className = "table-wrap";
      table.parentNode.insertBefore(wrap, table);
      wrap.appendChild(table);
    });
  }

  function renderMath(root) {
    if (typeof renderMathInElement !== "function") return;
    renderMathInElement(root, {
      delimiters: [
        { left: "$$", right: "$$", display: true },
        { left: "\\[", right: "\\]", display: true },
        { left: "\\(", right: "\\)", display: false },
        { left: "$", right: "$", display: false },
      ],
      ignoredTags: ["script", "noscript", "style", "textarea", "pre", "code"],
      ignoredClasses: ["mermaid"],
      throwOnError: false,
      strict: "warn",
    });
  }

  function highlightCode(root) {
    if (typeof hljs === "undefined") return;
    root.querySelectorAll("pre code").forEach(function (code) {
      if (code.classList.contains("language-mermaid")) return;
      try {
        hljs.highlightElement(code);
      } catch (error) {
        code.classList.add("nohighlight");
        console.warn("Could not highlight code block", error);
      }
    });
  }

  function extractMermaidBlocks(root) {
    return Array.from(root.querySelectorAll("pre code.language-mermaid")).map(
      function (code, index) {
        var container = document.createElement("figure");
        container.className = "mermaid-diagram";
        container.dataset.diagramIndex = String(index);
        var source = code.textContent || "";
        code.parentElement.replaceWith(container);
        return { container: container, source: source, index: index };
      }
    );
  }

  function diagramError(container, error) {
    container.className = "mermaid-diagram diagram-error";
    var heading = document.createElement("strong");
    heading.textContent = "Diagram error";
    var detail = document.createElement("pre");
    detail.textContent = String(error && error.message ? error.message : error);
    container.replaceChildren(heading, detail);
  }

  async function renderDiagrams(blocks, appearance) {
    if (blocks.length === 0) return;
    if (typeof mermaid === "undefined") {
      blocks.forEach(function (block) {
        diagramError(block.container, new Error("Mermaid did not load"));
      });
      return;
    }

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: appearance === "dark" ? "dark" : "default",
      flowchart: { htmlLabels: false, useMaxWidth: true },
    });

    for (var block of blocks) {
      try {
        var id = "bmd-mermaid-" + block.index;
        var result = await mermaid.render(id, block.source);
        block.container.innerHTML = result.svg;
        if (typeof result.bindFunctions === "function") {
          result.bindFunctions(block.container);
        }
      } catch (error) {
        diagramError(block.container, error);
        var leakedErrorDiagram = document.getElementById("d" + "bmd-mermaid-" + block.index);
        if (leakedErrorDiagram) leakedErrorDiagram.remove();
      }
    }
  }

  function setAppearance(appearance) {
    document.documentElement.dataset.appearance = appearance === "dark" ? "dark" : "light";
  }

  function setLayoutPreferences(proseWidth, tableWidth) {
    var safeProseWidth = Math.min(Math.max(Number(proseWidth) || 820, 640), 1040);
    var safeTableWidth = Math.min(
      Math.max(Number(tableWidth) || 1200, safeProseWidth, 820),
      1600
    );
    document.documentElement.style.setProperty("--max-prose", safeProseWidth + "px");
    document.documentElement.style.setProperty("--max-table", safeTableWidth + "px");
  }

  function captureScrollState(content) {
    return {
      windowX: window.scrollX,
      windowY: window.scrollY,
      tableOffsets: Array.from(content.querySelectorAll(".table-wrap")).map(
        function (tableWrap) {
          return tableWrap.scrollLeft;
        }
      ),
    };
  }

  function nextAnimationFrame() {
    return new Promise(function (resolve) {
      var finished = false;
      var timeout = window.setTimeout(finish, 50);
      function finish() {
        if (finished) return;
        finished = true;
        window.clearTimeout(timeout);
        resolve();
      }
      window.requestAnimationFrame(finish);
    });
  }

  async function restoreScrollState(content, state) {
    await nextAnimationFrame();
    await nextAnimationFrame();
    window.scrollTo(state.windowX, state.windowY);
    content.querySelectorAll(".table-wrap").forEach(function (tableWrap, index) {
      tableWrap.scrollLeft = state.tableOffsets[index] || 0;
    });
  }

  /**
   * Called from Swift via callAsyncJavaScript.
   * @param {string} markdownSource
   * @param {string} [title]
   * @param {string} [appearance]
   * @param {number} [proseWidth]
   * @param {number} [tableWidth]
   * @param {boolean} [preserveScroll]
   * @returns {Promise<object>}
   */
  window.bmdRender = async function bmdRender(
    markdownSource,
    title,
    appearance,
    proseWidth,
    tableWidth,
    preserveScroll
  ) {
    configureMarked();
    setAppearance(appearance);
    setLayoutPreferences(proseWidth, tableWidth);
    document.documentElement.dataset.mode = "preview";

    var empty = document.getElementById("empty");
    var content = document.getElementById("content");
    if (!content) throw new Error("Viewer content element is missing");
    var scrollState = preserveScroll ? captureScrollState(content) : null;

    var src = typeof markdownSource === "string" ? markdownSource : "";
    if (!src) {
      if (empty) empty.hidden = false;
      content.hidden = true;
      var editor = document.getElementById("editor");
      if (editor) editor.hidden = true;
      content.innerHTML = "";
      document.title = "bmd";
      return {
        codeBlocks: 0,
        diagramErrors: 0,
        diagrams: 0,
        images: 0,
        inlineSVG: 0,
        math: 0,
      };
    }

    if (empty) empty.hidden = true;
    content.hidden = false;
    var editorSurface = document.getElementById("editor");
    if (editorSurface) editorSurface.hidden = true;
    document.title = title ? String(title) : "bmd";

    try {
      content.innerHTML = marked.parse(src);
      wrapTables(content);
      renderMath(content);
      highlightCode(content);
      var diagrams = extractMermaidBlocks(content);
      await renderDiagrams(diagrams, appearance);

      if (scrollState) {
        await restoreScrollState(content, scrollState);
      } else {
        window.scrollTo(0, 0);
      }

      var result = {
        codeBlocks: content.querySelectorAll("pre code.hljs").length,
        diagramErrors: content.querySelectorAll(".diagram-error").length,
        diagrams: content.querySelectorAll(".mermaid-diagram svg").length,
        images: content.querySelectorAll("img").length,
        inlineSVG: content.querySelectorAll(":scope > svg").length,
        math: content.querySelectorAll(".katex").length,
      };
      return result;
    } catch (error) {
      content.innerHTML = "";
      var message = document.createElement("pre");
      message.className = "error";
      message.textContent = "Render error: " + String(error && error.message ? error.message : error);
      content.appendChild(message);
      throw error;
    }
  };

  window.bmdShowEditor = async function bmdShowEditor(
    markdownSource,
    title,
    appearance,
    vimEnabled,
    documentIdentifier
  ) {
    setAppearance(appearance);
    var editorRoot = document.getElementById("editor");
    if (!editorRoot) throw new Error("Editor surface is missing");
    if (typeof BMDEditorController !== "function") {
      throw new Error("Bundled CodeMirror editor did not load");
    }

    if (editorController && editorDocumentIdentifier
        && editorDocumentIdentifier !== documentIdentifier) {
      editorPositions[editorDocumentIdentifier] = editorController.snapshotPosition();
    }

    var source = typeof markdownSource === "string" ? markdownSource : "";
    if (!editorController) {
      editorController = new BMDEditorController(editorRoot, {
        text: source,
        appearance: appearance,
        vimEnabled: Boolean(vimEnabled),
        onChange: function (text) {
          sendEditorMessage("change", text);
        },
        onCommand: function (command, text) {
          sendEditorMessage(command, text);
        },
      });
    } else {
      editorController.setText(source);
      editorController.setAppearance(appearance);
      editorController.setVimEnabled(Boolean(vimEnabled));
    }

    editorDocumentIdentifier = documentIdentifier || null;
    showSurface("editing");
    document.title = title ? String(title) : "bmd";
    editorController.restorePosition(editorPositions[editorDocumentIdentifier]);
    editorController.focus();

    return {
      characters: editorController.text.length,
      mode: "editing",
      vimEnabled: Boolean(vimEnabled),
    };
  };

  window.bmdClear = function bmdClear() {
    return window.bmdRender("", "", "light", 820, 1200, false);
  };

  document.addEventListener("DOMContentLoaded", configureMarked);
})();
