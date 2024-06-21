defmodule Breeze.View do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import Breeze.View
      import Phoenix.Component, only: [sigil_H: 2]
    end
  end

  def assign(term, values) do
    %{term | assigns: Map.merge(term.assigns, Map.new(values))}
  end

  def style(map) do
    style_keys = Map.keys(Map.from_struct(%BackBreeze.Style{}))
    {style, attributes} = Map.split(map, style_keys)
    struct(Breeze.Element, %{style: style, attributes: attributes})
  end
end

defimpl Phoenix.HTML.Safe, for: Breeze.Element do
  def to_iodata(map) do
    Jason.encode!(map)
    |> Base.encode64()
  end
end

# Start with something like Breeze.start_link(view: MyApp.View)
