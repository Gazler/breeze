defmodule Breeze.TestImportedComponentDefaults do
  use Breeze.View

  attr :label, :string, default: "default label"
  attr :enabled, :boolean, default: true
  attr :rest, :global
  slot :item

  def badge(assigns) do
    ~H|<box enabled={@enabled} {@rest}>{@label}:{render_slot(@item)}</box>|
  end
end
