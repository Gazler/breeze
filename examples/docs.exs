defmodule Docs do
  use Breeze.View
  import Breeze.Blocks

  def mount(opts, term) do
    docs =
      case Keyword.get(opts, :docs) do
        nil ->
          {:ok, docs} = :application.get_key(:kernel, :modules)
          docs

        docs ->
          docs
      end

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
      <box style="grid grid-cols-1 grid-rows-2 width-full height-full">
        <.list id="docs" br-change="change" style="width-full height-full">
          <:item :for={doc <- @docs} value={inspect(doc)}>{inspect(doc)}</:item>
        </.list>
        <.list id="functions" br-change="function" style="width-full height-full">
          <:item :for={function <- @functions || []} value={function}>{function}</:item>
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

  def handle_info(:resize, term) do
    {screen_width, _} = BackBreeze.screen_dimensions(term.terminal)
    doc_width = div(screen_width, 2) - 2

    {:noreply, assign(term, doc_width: doc_width)}
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
        {:docs_v1, _, lang, _, _, _, docs} when lang in [:erlang, :elixir] ->
          funs =
            Enum.reduce(docs, [], fn doc, acc ->
              head = elem(doc, 0)

              case head do
                {:function, fun, arity} ->
                  if documented_function?(fun) do
                    ["#{fun}/#{arity}" | acc]
                  else
                    acc
                  end

                _ ->
                  acc
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

  def handle_event(_, _, term), do: {:noreply, term}

  defp documented_function?(fun) do
    fun
    |> Atom.to_string()
    |> String.starts_with?("__")
    |> Kernel.not()
  end

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

Breeze.Example.run(
  [
    view: Docs,
    hide_cursor: true,
    reload: true,
    mouse: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
