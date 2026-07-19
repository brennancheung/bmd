/* global marked */
(function () {
  "use strict";

  function configureMarked() {
    if (typeof marked === "undefined") return;
    marked.setOptions({
      gfm: true,
      breaks: false,
      headerIds: true,
      mangle: false,
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

  /**
   * Called from Swift via evaluateJavaScript.
   * @param {string} markdownSource
   * @param {string} [title]
   */
  window.bmdRender = function bmdRender(markdownSource, title) {
    configureMarked();
    var empty = document.getElementById("empty");
    var content = document.getElementById("content");
    if (!content) return;

    var src = typeof markdownSource === "string" ? markdownSource : "";
    if (!src) {
      if (empty) empty.hidden = false;
      content.hidden = true;
      content.innerHTML = "";
      document.title = "bmd";
      return;
    }

    if (empty) empty.hidden = true;
    content.hidden = false;
    document.title = title ? String(title) : "bmd";

    try {
      content.innerHTML = marked.parse(src);
      wrapTables(content);
    } catch (err) {
      content.innerHTML =
        "<pre class='error'>Render error: " +
        String(err && err.message ? err.message : err) +
        "</pre>";
    }

    window.scrollTo(0, 0);
  };

  window.bmdClear = function bmdClear() {
    window.bmdRender("", "");
  };

  document.addEventListener("DOMContentLoaded", function () {
    configureMarked();
  });
})();
