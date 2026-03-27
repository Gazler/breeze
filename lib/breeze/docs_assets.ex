defmodule Breeze.DocsAssets do
  @moduledoc false

  def head_html do
    """
    <style>
      .breeze-ansi-preview {
        overflow-x: auto;
        overflow-y: visible;
        padding: calc(0.75rem + 1px) 0.75rem;
        margin-bottom: var(--tabsetPadding);
        background: #282828;
        color: #ebdbb2;
        font-family: monospace;
        font-size: 0.875rem;
        line-height: 1;
        white-space: pre;
      }

      .breeze-ansi-line {
        display: block;
        white-space: pre;
        line-height: 1.05;
        margin-bottom: -0.05em;
      }

      .breeze-ansi-line:last-child {
        margin-bottom: 0;
      }

      .breeze-ansi-line span {
        display: inline-block;
        padding-bottom: 2px;
      }

      .breeze-code-toggle {
        margin: 0.5rem 0;
        padding: 0;
        border: 0;
        background: transparent;
        color: var(--linksNoUnderline, inherit);
        font: inherit;
        cursor: pointer;
        text-decoration: underline;
        display: inline-block;
      }

      .breeze-code-toggle:hover {
        color: var(--linksNoUnderlineVisited, inherit);
      }
    </style>
    """
  end

  def body_html do
    """
    <script src="assets/js/ansi_up.js"></script>
    <script>
      (function () {
        function renderAnsiPreviews() {
          if (!window.AnsiUp) return;

          for (const sourceEl of document.querySelectorAll(".breeze-ansi[data-ansi-preview]")) {
            if (sourceEl.dataset.ansiRendered === "true") continue;

            const scriptEl = sourceEl.querySelector(".breeze-ansi-source");
            if (!scriptEl) continue;

            const ansiUp = new AnsiUp();
            const previewEl = document.createElement("div");
            previewEl.className = "breeze-ansi-preview";

            const lines = scriptEl.textContent.split("\\n");

            for (const line of lines) {
              const lineEl = document.createElement("div");
              lineEl.className = "breeze-ansi-line";
              lineEl.innerHTML = ansiUp.ansi_to_html(line);
              previewEl.appendChild(lineEl);
            }

            sourceEl.dataset.ansiRendered = "true";
            sourceEl.replaceWith(previewEl);
          }
        }

        function bindCodeToggles() {
          for (const link of document.querySelectorAll(".breeze-code-toggle")) {
            if (link.dataset.breezeBound === "true") continue;

            let panel = link.nextElementSibling;
            while (panel && panel.tagName !== "PRE") panel = panel.nextElementSibling;
            if (!panel) continue;

            panel.hidden = true;
            link.dataset.breezeBound = "true";

            link.addEventListener("click", function (event) {
              event.preventDefault();

              const expanded = link.getAttribute("aria-expanded") === "true";
              link.setAttribute("aria-expanded", expanded ? "false" : "true");
              panel.hidden = expanded;
              link.textContent = expanded ? "Show code" : "Hide code";
            });
          }
        }

        function initializeBuiltInComponentsPage() {
          renderAnsiPreviews();
          bindCodeToggles();
        }

        document.addEventListener("DOMContentLoaded", initializeBuiltInComponentsPage);
        window.addEventListener("exdoc:loaded", initializeBuiltInComponentsPage);
      })();
    </script>
    """
  end
end
