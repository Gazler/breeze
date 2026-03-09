defmodule Docs do
  use Breeze.View
  import Breeze.Blocks

  def mount(_opts, term) do
    {:ok, docs} = :application.get_key(:kernel, :modules)

    {screen_width, _} = BackBreeze.screen_dimensions(term.terminal)
    doc_width = div(screen_width, 2) - 2

    term =
      term
      |> focus("docs")
      |> assign(
        docs: docs,
        functions: nil,
        selected: nil,
        fun_selected: nil,
        fun_doc: nil,
        doc_width: doc_width
      )

    {:ok, term}
  end

  def render(assigns) do
    ~H"""
    <box style="grid grid-cols-2 height-screen width-screen">
      <box style="grid grid-cols-1 grid-rows-2 height-screen">
        <.list
          id="docs"
          br-change="change"
          style="height-screen focus:scrollbar-3"
          item_style="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4 width-full"
        >
          <:item :for={doc <- @docs} value={inspect(doc)}>{inspect(doc)}</:item>
        </.list>
        <.list
          :if={@selected}
          id="functions"
          br-change="function"
          style="height-screen focus:scrollbar-3"
          item_style="selected:bg-24 selected:text-0 focus:selected:text-7 focus:selected:bg-4 width-full"
        >
          <:item :for={function <- @functions} value={function}>{function}</:item>
        </.list>
      </box>
      <.markdown
        :if={@fun_doc}
        id="doc"
        content={@fun_doc}
        width={@doc_width}
        style="border focus:border-3"
      />
    </box>
    """
  end

  def handle_info(_, term) do
    {:noreply, term}
  end

  def handle_event("change", %{value: value}, term) do
    module =
      case value do
        ":" <> mod -> String.to_existing_atom(mod)
        _ -> String.to_existing_atom("Elixir." <> value)
      end

    term =
      case Code.fetch_docs(module) do
        {:docs_v1, _, lang, _, _, _, props} when lang in [:erlang, :elixir] ->
          funs =
            Enum.reduce(props, [], fn prop, acc ->
              head = elem(prop, 0)

              case head do
                {:function, fun, arity} -> ["#{fun}/#{arity}" | acc]
                _ -> acc
              end
            end)

          term
          |> assign(
            functions: Enum.reverse(funs),
            selected: value,
            fun_selected: nil,
            fun_doc: nil
          )
          |> reset("doc")
          |> reset("functions")

        _ ->
          term
      end

    {:noreply, term}
  end

  def handle_event("function", %{value: value}, term) do
    doc = fetch_function_doc(term.assigns.selected, value)
    term = assign(term, fun_selected: value, fun_doc: doc)
    term = reset(term, "doc")
    {:noreply, term}
  end

  def handle_event(_, %{"key" => "q"}, term), do: {:stop, term}
  def handle_event(_, _, term), do: {:noreply, term}

  defp fetch_function_doc(module_str, function_str) do
    module =
      case module_str do
        ":" <> mod -> String.to_existing_atom(mod)
        _ -> String.to_existing_atom("Elixir." <> module_str)
      end

    [fun_name, arity_str] = String.split(function_str, "/")
    fun_name = String.to_atom(fun_name)
    arity = String.to_integer(arity_str)

    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, _, _, docs} ->
        Enum.find_value(docs, fn
          {{:function, ^fun_name, ^arity}, _, signature, doc_map, _} ->
            heading =
              case signature do
                [] -> "#{fun_name}/#{arity}"
                sigs -> Enum.join(sigs, "\n")
              end

            doc_text =
              case doc_map do
                %{"en" => text} -> text
                _ -> ""
              end

            "## #{heading}\n\n" <> doc_text

          _ ->
            nil
        end) || ""

      _ ->
        ""
    end
  end
end

Breeze.Server.start_link(view: Docs, hide_cursor: true)

receive do
end
