defmodule Breeze.RemoteInspector.Page do
  @moduledoc """
  Behaviour for custom Breeze remote inspector pages.

  Remote inspector pages are configured with `:remote_inspector_pages`:

      config :breeze, :remote_inspector_pages, [
        {MyApp.LLMInspectorPage, id: "llm", label: "LLM", render_tree: true}
      ]

  Page modules render normal Breeze markup from `render/1`. The assigns include the active
  source, source entry, snapshot, selected and hovered element snapshots, all known
  snapshots, current screen size, page config, page state, and the cached render tree when
  available.

  A page can also implement `page/0` to provide default options such as `:id`, `:label`,
  and `:render_tree`.

  Interactive pages can implement `handle_event/3` and return `{:noreply, state}`. The
  returned state map is stored for that page id and merged into future render assigns.
  Pages can receive asynchronous work with messages sent to the inspector process as
  `{:remote_inspector_page, page_id, message}` and handled with `handle_info/2`.
  """

  @callback render(map()) :: any()
  @callback page() :: keyword() | map()
  @callback handle_event(term(), map(), map()) :: {:noreply, map()} | :noreply
  @callback handle_info(term(), map()) :: {:noreply, map()} | :noreply

  @optional_callbacks page: 0, handle_event: 3, handle_info: 2
end
