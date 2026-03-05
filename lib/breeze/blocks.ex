defmodule Breeze.Blocks do
  @moduledoc """
  Reusable built-in components for Breeze views.

  Import this module in your view to use the provided components:

      defmodule MyView do
        use Breeze.View
        import Breeze.Blocks
        ...
      end

  ## Style merging

  All components expose a `style` attribute (and where applicable an
  `item_style` attribute) that are merged with the component's defaults using
  `merge_style/2`.  Style tokens are grouped by their *property key*, everything
  before the last `-` segment, so an override of `"width-32"` replaces the
  default `"width-24"` while leaving other properties intact (including `focus:`
  prefixes).
  """

  use Breeze.View

  attr :id, :string, required: true
  attr :loop, :boolean, default: true
  attr :style, :string, default: nil
  attr :item_style, :string, default: nil
  attr :rest, :global

  slot :item do
    attr :value, :string, required: true
  end

  def list(assigns) do
    assigns =
      assigns
      |> assign(
        style:
          merge_style(
            "border width-24 height-8 overflow-scroll scrollbar-arrows focus:border-3",
            assigns[:style]
          )
      )
      |> assign(
        item_style: merge_style("selected:bg-4 selected:text-7 width-24", assigns[:item_style])
      )

    ~H"""
    <box
      id={@id}
      implicit={Breeze.Implicit.List}
      list-loop={@loop}
      list-scroll-padding={1}
      focusable
      style={@style}
      {@rest}
    >
      <box :for={item <- @item} value={item.value} style={@item_style}>
        <%= render_slot(item, %{}) %>
      </box>
    </box>
    """
  end

  attr :id, :string, required: true
  attr :content, :string, required: true
  attr :width, :integer, required: true
  attr :style, :string, default: nil

  def markdown(assigns) do
    assigns =
      assign(assigns,
        style:
          merge_style(
            "height-full overflow-scroll scrollbar-arrows focus:scrollbar-3",
            assigns[:style]
          )
      )

    ~H"""
    <box focusable id={@id} implicit={Breeze.Implicit.Scroll} style={@style}>
      {Breeze.Markdown.render(@content, @width)}
    </box>
    """
  end

  @doc """
  Merge two style strings, with `override` taking precedence over `default` for
  matching style properties.

  The *property key* for each style token is everything before its final `-`
  segment, so tokens that share the same prefix override one another:

      iex> Breeze.Blocks.merge_style("border width-24 height-8", "width-32")
      "border width-32 height-8"

      iex> Breeze.Blocks.merge_style("overflow-scroll", "overflow-hidden")
      "overflow-hidden"

  Tokens from `override` that do not match any default key are appended:

      iex> Breeze.Blocks.merge_style("border width-24", "bg-4")
      "border width-24 bg-4"

  `nil` or an empty string override returns the default unchanged.
  """
  @spec merge_style(String.t(), String.t() | nil) :: String.t()
  def merge_style(default, override) when override in [nil, ""], do: default

  def merge_style(default, override) do
    default_tokens = String.split(default, " ", trim: true)
    override_tokens = String.split(override, " ", trim: true)

    default_key_set = MapSet.new(default_tokens, &style_key/1)
    override_map = Map.new(override_tokens, fn token -> {style_key(token), token} end)

    merged =
      Enum.map(default_tokens, fn token -> Map.get(override_map, style_key(token), token) end)

    new_tokens = Enum.reject(override_tokens, &MapSet.member?(default_key_set, style_key(&1)))

    Enum.join(merged ++ new_tokens, " ")
  end

  defp style_key(token) do
    case String.split(token, "-") do
      [_only] -> token
      parts -> parts |> Enum.drop(-1) |> Enum.join("-")
    end
  end
end
