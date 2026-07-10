defmodule Breeze.Implicit.AsyncSpinner do
  @moduledoc false

  @behaviour Breeze.Implicit

  @frames ["|", "/", "-", "\\"]

  def init(_items, _root_attrs, last_state),
    do: {:ok, last_state, rerender_every: 120, active_when_pending: true}

  def handle_modifiers(:root, _flags, _state), do: []
  def handle_modifiers(:child, _flags, _state), do: []

  def animate(:root, box, _flags, _state, %{frame: frame, pending?: pending?} = ctx) do
    content = if pending?, do: Enum.at(@frames, rem(frame, length(@frames))), else: "·"

    case Map.get(ctx, :layout) do
      %Breeze.Viewport{left: left, top: top} when pending? ->
        {:ok, %{box | content: "·"}, overlays: [%{x: left, y: top, content: content}]}

      _ ->
        %{box | content: content}
    end
  end

  def animate(:child, box, _flags, _state, _ctx), do: box
end
