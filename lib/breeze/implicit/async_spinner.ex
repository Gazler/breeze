defmodule Breeze.Implicit.AsyncSpinner do
  @moduledoc false

  @behaviour Breeze.Implicit

  @bars_frames ["|", "/", "-", "\\"]
  @dots_frames ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

  def init(_items, root_attrs, last_state) do
    variant = root_attrs |> Map.get(:"spinner-variant", :dots) |> normalize_variant()
    active? = root_attrs |> Map.get(:"spinner-active", false) |> active?()
    interval = if variant == :dots, do: 80, else: 120
    state = last_state |> Map.put(:variant, variant) |> Map.put(:active?, active?)

    {:ok, state, rerender_every: interval, active_when_pending: not active?}
  end

  def handle_modifiers(:root, _flags, _state), do: []
  def handle_modifiers(:child, _flags, _state), do: []

  def animate(:root, box, _flags, state, %{frame: frame, pending?: pending?} = ctx) do
    frames = frames(state)
    active? = pending? or Map.get(state, :active?, false)
    content = if active?, do: Enum.at(frames, rem(frame, length(frames))), else: "·"

    case Map.get(ctx, :layout) do
      %Breeze.Viewport{left: left, top: top} when active? ->
        overlay_content = styled_content(box, content)

        {:ok, %{box | content: "·"}, overlays: [%{x: left, y: top, content: overlay_content}]}

      _ ->
        %{box | content: content}
    end
  end

  def animate(:child, box, _flags, _state, _ctx), do: box

  defp frames(%{variant: :bars}), do: @bars_frames
  defp frames(_state), do: @dots_frames

  defp normalize_variant(value) when value in [:bars, "bars"], do: :bars
  defp normalize_variant(_value), do: :dots

  defp active?(value), do: value in [true, "true", ""]

  defp styled_content(%{style: %BackBreeze.Style{} = style}, content) do
    BackBreeze.Style.render(style, content,
      terminal: %Termite.Terminal{size: %{width: 1, height: 1}}
    )
  end

  defp styled_content(_box, content), do: content
end
