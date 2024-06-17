defmodule Breeze.View do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import Breeze.View
    end
  end

  defmacro sigil_H({:<<>>, _meta, [expr]}, []) do
    unless Macro.Env.has_var?(__CALLER__, {:assigns, nil}) do
      raise "~H requires a variable named \"assigns\" to exist and be set to a map"
    end

    # TODO
    # Walk all tokens
    # Convert any starting tags to a BackBreeze.Box struct
    # format: %{style: BackBreeze.Style, children: [], width: x, height: x}
    # The height is calculated from the height of the children

    quote do
      assigns = var!(assigns)
      acc = %{env: __ENV__, mod: __MODULE__, assigns: assigns, depth: 0, current: %{type: :string, content: "", children: []}, elements: []}

      Breeze.Renderer.tokenize(unquote(expr))
      |> Enum.reduce(acc, fn x, acc ->
        acc = Breeze.View.__render_token__(x, acc)
        acc
      end)
      |> Map.drop([:env, :assigns])
    end
  end

  def __render_token__({:tag, "box", attrs, _meta}, acc) do
    attrs =
      Enum.map(attrs, fn
        {"style", {:expr, expr, _}, _} -> {:style, struct(BackBreeze.Style, eval_expr(expr, acc))}
        {attr, _, _} -> raise "Invalid attribute #{attr} on box"
      end)

    style = Keyword.get(attrs, :style)

    elements = [acc.current | acc.elements]

    %{acc | elements: elements, current: current_box(style), depth: acc.depth + 1}
  end

  def __render_token__({:text, text, _meta}, acc) do
    if String.trim(text || "", " ") == "\n" do
      acc
    else
      update_in(acc, [:current, :content], fn current -> current <> text end)
    end
  end

  def __render_token__({:local_component, fun, attrs, _meta}, acc) do
    attrs = Enum.map(attrs, fn
      {attr, {:expr, expr, _}, _} -> {String.to_atom(attr), eval_expr(expr, acc)}
      {attr, {:string, str, _}, _} -> {String.to_atom(attr), str}
    end)

    elements = [acc.current | acc.elements]

    current = %{type: :component, assigns: Map.new(attrs), fun: String.to_atom(fun), content: ""}

    %{acc | elements: elements, current: current, depth: acc.depth + 1}
  end

  def __render_token__({:eex, :expr, expr, _meta}, acc) do
    text = eval_expr(expr, acc) || ""
    if String.trim(text, " ") == "\n" do
      acc
    else
      update_in(acc, [:current, :content], fn current -> current <> text end)
    end
  end

  def __render_token__({:close, :tag, "box", _meta}, acc) do
    %{current: current} = acc
    [prev | elements] = acc.elements
    %{acc | elements: elements, current: %{prev | children: prev.children ++ [current]}, depth: acc.depth - 1}
  end

  def __render_token__({:close, :local_component, _, _meta}, acc) do
    %{current: current} = acc
    %{fun: fun, assigns: assigns, content: content} = current
    assigns = Map.put(assigns, :inner_block, content)
    content = apply(acc.mod, fun, [assigns])

    [prev | elements] = acc.elements

    %{acc | elements: elements, current: %{prev | children: prev.children ++ [content]}, depth: acc.depth - 1}
  end

  defp eval_expr(expr, %{assigns: assigns} = acc) do
    {result, _} =
      Regex.replace(~r/@([a-z0-9A-Z_]+)/, expr, fn _, x -> "assigns[:#{x}]" end)
      |> Code.eval_string([assigns: assigns], acc.env)

    result
  end

  def assign(term, values) do
    %{term | assigns: Map.merge(term.assigns, Map.new(values))}
  end

  def render_slot(x) do
    x
  end

  defp current_box(style) do
    %{type: :box, style: style, content: "", children: []}
  end
end

# Start with something like Breeze.start_link(view: MyApp.View)
