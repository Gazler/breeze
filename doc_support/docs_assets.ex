defmodule Breeze.Docs.Assets do
  @moduledoc false

  def head_html do
    """
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Cascadia+Mono:wght@400;700&amp;display=swap" rel="stylesheet">
    <style>
      .breeze-ansi-preview {
        overflow-x: auto;
        overflow-y: visible;
        padding: calc(0.75rem + 1px) 0.75rem;
        margin-bottom: var(--tabsetPadding);
        background: #282828;
        color: #ebdbb2;
        font-family: "Cascadia Mono", monospace;
        font-size: 0.875rem;
        line-height: 1;
        white-space: pre;
      }

      .breeze-theme-picker {
        display: flex;
        align-items: center;
        gap: 0.75rem;
        margin: 1rem 0 1.5rem;
      }

      .breeze-theme-picker label {
        font-weight: 600;
      }

      .breeze-theme-picker select {
        min-width: 12rem;
        padding: 0.35rem 2rem 0.35rem 0.55rem;
        border: 1px solid var(--borderColor, #888);
        border-radius: 0.25rem;
        background: var(--background, inherit);
        color: inherit;
        font: inherit;
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
        const themeStorageKey = "breeze-component-preview-theme";

        function storedTheme() {
          try {
            return window.localStorage.getItem(themeStorageKey);
          } catch (_error) {
            return null;
          }
        }

        function storeTheme(theme) {
          try {
            window.localStorage.setItem(themeStorageKey, theme);
          } catch (_error) {
            // Storage may be unavailable in privacy-restricted contexts.
          }
        }

        function selectedTheme() {
          const select = document.querySelector("[data-breeze-theme-select]");
          if (!select) return storedTheme() || "gruvbox";

          const saved = storedTheme();
          const available = Array.from(select.options, function (option) { return option.value; });
          return available.includes(saved) ? saved : select.value;
        }

        function sourcesFor(container) {
          if (container.breezeAnsiSources) return container.breezeAnsiSources;

          const script = container.querySelector(".breeze-ansi-sources");
          if (!script) return [];

          try {
            container.breezeAnsiSources = JSON.parse(script.textContent);
          } catch (_error) {
            container.breezeAnsiSources = [];
          }

          return container.breezeAnsiSources;
        }

        function sourceForTheme(container, theme) {
          const sources = sourcesFor(container);
          return sources.find(function (source) { return source.theme === theme; }) || sources[0];
        }

        function decodeAnsiSource(source) {
          const binary = window.atob(source.content);
          const bytes = Uint8Array.from(binary, function (character) {
            return character.charCodeAt(0);
          });

          return new TextDecoder().decode(bytes);
        }

        function renderAnsiPreviews(theme) {
          if (!window.AnsiUp) return;

          for (const container of document.querySelectorAll(".breeze-ansi[data-ansi-preview]")) {
            const scriptEl = sourceForTheme(container, theme);
            if (!scriptEl) continue;

            const ansiUp = new AnsiUp();
            let previewEl = container.querySelector(".breeze-ansi-preview");

            if (!previewEl) {
              previewEl = document.createElement("div");
              previewEl.className = "breeze-ansi-preview";
              container.appendChild(previewEl);
            }

            if (previewEl.dataset.theme === scriptEl.theme) continue;

            previewEl.replaceChildren();
            previewEl.dataset.theme = scriptEl.theme;
            previewEl.style.backgroundColor = scriptEl.background || "";
            previewEl.style.color = scriptEl.foreground || "";

            const lines = decodeAnsiSource(scriptEl).split("\\n");

            for (const line of lines) {
              const lineEl = document.createElement("div");
              lineEl.className = "breeze-ansi-line";
              lineEl.innerHTML = ansiUp.ansi_to_html(line);
              previewEl.appendChild(lineEl);
            }
          }
        }

        function bindThemeSelectors() {
          const selects = Array.from(document.querySelectorAll("[data-breeze-theme-select]"));
          if (selects.length === 0) return selectedTheme();

          const theme = selectedTheme();

          for (const select of selects) {
            select.value = theme;
            if (select.dataset.breezeBound === "true") continue;

            select.dataset.breezeBound = "true";
            select.addEventListener("change", function () {
              storeTheme(select.value);

              for (const other of document.querySelectorAll("[data-breeze-theme-select]")) {
                other.value = select.value;
              }

              renderAnsiPreviews(select.value);
            });
          }

          return theme;
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
          renderAnsiPreviews(bindThemeSelectors());
          bindCodeToggles();
        }

        document.addEventListener("DOMContentLoaded", initializeBuiltInComponentsPage);
        window.addEventListener("exdoc:loaded", initializeBuiltInComponentsPage);
      })();
    </script>
    """
  end
end
