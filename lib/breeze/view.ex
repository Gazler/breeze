defmodule Breeze.View do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import Breeze.View
    end
  end

  def assign(term, values) do
    %{term | assigns: Map.merge(term.assigns, Map.new(values))}
  end
end

# Start with something like Breeze.start_link(view: MyApp.View)
