defmodule Breeze.Test do
  @moduledoc """
  Public helpers for deterministic Breeze view tests.

  `Breeze.Test` can render a view against a fixed terminal size, dispatch input
  and events without starting the interactive server. It also provides
  element-oriented interaction helpers so tests do not need to construct mouse
  coordinates or call Breeze's private runtime processes directly.

  ## Example

  ```elixir
  defmodule MyApp.CounterTest do
    use ExUnit.Case, async: true

    test "counter snapshot" do
      session = Breeze.Test.start!(MyApp.CounterView, size: {30, 5})
      on_exit(fn -> Breeze.Test.stop(session) end)

      assert Breeze.Test.render_text!(session) =~ "Counter: 0"

      assert {:noreply, _focused, true} = Breeze.Test.input(session, "ArrowUp")
      assert Breeze.Test.render_text!(session) =~ "Counter: 1"
    end
  end
  ```

  `focus/2`, `click/3`, and `wheel/4` target rendered element IDs. These
  helpers settle the current layout before interacting, so they work without a
  separate initial render. `resize/2` returns an updated session and must be
  rebound before the next render or event:

  ```elixir
  assert {:noreply, "save", _changed?} = Breeze.Test.focus(session, "save")
  assert {:noreply, "save", _changed?} = Breeze.Test.click(session, "save")

  session = Breeze.Test.resize(session, {100, 30})
  assert %Breeze.Viewport{} = Breeze.Test.element!(session, "page")
  ```
  """

  defstruct [:pid, :terminal]

  alias Breeze.ChildServer

  @typedoc "A deterministic view-test session."
  @type t :: %__MODULE__{pid: pid(), terminal: %Termite.Terminal{}}

  @typedoc "A fixed terminal size used by a deterministic test session."
  @type size ::
          {pos_integer(), pos_integer()}
          | %{required(:width) => pos_integer(), required(:height) => pos_integer()}

  @typedoc "A vertical mouse-wheel direction."
  @type wheel_direction :: :up | :down

  @typedoc "An error returned by an element-oriented interaction helper."
  @type interaction_error ::
          {:element_not_found, String.t()}
          | {:mouse_target_not_found, String.t()}
          | {:invalid_mouse_target, String.t()}
          | {:point_outside_element, String.t(), {non_neg_integer(), non_neg_integer()}}

  @default_size %{width: 80, height: 24}

  @doc """
  Starts a deterministic test session for `view`.

  Options include:

    * `:size` - terminal size as `{width, height}` or a dimensions map. Defaults
      to `80x24`.
    * `:terminal` - an existing `%Termite.Terminal{}`. Takes precedence over
      `:size`.
    * `:theme` - the theme used to render the view.
    * `:start_opts` - options passed to the view's `mount/2` callback.
    * `:global_keybindings` - keybindings active for the test session.
  """
  @spec start(module(), keyword()) :: {:ok, t()} | {:error, term()}
  def start(view, opts \\ []) do
    terminal =
      Keyword.get(opts, :terminal, build_terminal(Keyword.get(opts, :size, @default_size)))

    child_opts = [
      view: view,
      terminal: terminal,
      theme: Keyword.get(opts, :theme),
      theme_source: Keyword.get(opts, :theme),
      apply_theme_defaults?: Breeze.Theme.defaults_enabled?(Keyword.get(opts, :theme)),
      start_opts: Keyword.get(opts, :start_opts, []),
      global_keybindings: Keyword.get(opts, :global_keybindings, [])
    ]

    with {:ok, pid} <- ChildServer.start(child_opts) do
      {:ok, %__MODULE__{pid: pid, terminal: terminal}}
    end
  end

  @doc "Starts a deterministic test session and returns it, raising on failure."
  @spec start!(module(), keyword()) :: t()
  def start!(view, opts \\ []) do
    {:ok, session} = start(view, opts)
    session
  end

  @doc "Renders the current view state and returns its terminal content."
  @spec render(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render(%__MODULE__{} = session, opts \\ []) do
    render_opts =
      opts
      |> Keyword.put_new(:terminal, session.terminal)
      |> Keyword.put_new(:implicit_state, %{})
      |> Keyword.put_new(:theme_source, Keyword.get(opts, :theme))

    case ChildServer.render_snapshot(session.pid, render_opts) do
      {:ok, _acc, box, _decorations} -> {:ok, box.content}
      other -> other
    end
  end

  @doc "Renders the current view state, raising on failure."
  @spec render!(t(), keyword()) :: String.t()
  def render!(%__MODULE__{} = session, opts \\ []) do
    {:ok, content} = render(session, opts)
    content
  end

  @doc "Renders the current view state with ANSI styling removed."
  @spec render_text(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def render_text(%__MODULE__{} = session, opts \\ []) do
    case render(session, opts) do
      {:ok, content} -> {:ok, BackBreeze.Utils.strip_escape_chars(content)}
      other -> other
    end
  end

  @doc "Renders the current view state without ANSI styling, raising on failure."
  @spec render_text!(t(), keyword()) :: String.t()
  def render_text!(%__MODULE__{} = session, opts \\ []) do
    {:ok, content} = render_text(session, opts)
    content
  end

  @doc """
  Changes the fixed terminal size and returns the updated session.

  Rebind the returned session before subsequent calls:

      session = Breeze.Test.resize(session, {100, 30})
  """
  @spec resize(t(), size()) :: t()
  def resize(%__MODULE__{} = session, size) do
    size = normalize_size!(size)
    terminal = %{session.terminal | size: size}
    :ok = ChildServer.put_terminal(session.pid, terminal)
    %{session | terminal: terminal}
  end

  @doc "Sets focus to a rendered element ID, or clears it when passed `nil`."
  @spec focus(t(), String.t() | nil) :: term() | {:error, term()}
  def focus(%__MODULE__{} = session, nil) do
    with {:ok, _layout} <- settle_layout(session) do
      ChildServer.set_focus(session.pid, nil)
    end
  end

  def focus(%__MODULE__{} = session, focused) when is_binary(focused) do
    with {:ok, _viewport} <- element(session, focused) do
      ChildServer.set_focus(session.pid, focused)
    end
  end

  @doc "Returns the currently focused element ID, or `nil`."
  @spec focused(t()) :: String.t() | nil
  def focused(%__MODULE__{} = session) do
    session
    |> metadata()
    |> Map.get(:focused)
  end

  @doc """
  Returns the rendered viewport for an element ID.

  The layout is rendered and settled before lookup. Missing IDs return
  `{:error, {:element_not_found, id}}`.
  """
  @spec element(t(), String.t()) ::
          {:ok, Breeze.Viewport.t()} | {:error, interaction_error() | term()}
  def element(%__MODULE__{} = session, id) when is_binary(id) do
    with {:ok, %{elements: elements}} <- settle_layout(session) do
      case Map.fetch(elements, id) do
        {:ok, viewport} -> {:ok, viewport}
        :error -> {:error, {:element_not_found, id}}
      end
    end
  end

  @doc "Returns the rendered viewport for an element ID, raising when it is missing."
  @spec element!(t(), String.t()) :: Breeze.Viewport.t()
  def element!(%__MODULE__{} = session, id) when is_binary(id) do
    case element(session, id) do
      {:ok, viewport} ->
        viewport

      {:error, reason} ->
        raise ArgumentError,
              "could not find rendered Breeze element #{inspect(id)}: #{inspect(reason)}"
    end
  end

  @doc """
  Dispatches a left-button mouse event at a rendered element ID.

  The default action is `:press`; pass `action: :release` when an application
  deliberately handles mouse release. `:at` can be `{column, row}` using
  zero-based coordinates relative to the element; otherwise the center of the
  visible target is used. The `:shift`, `:alt`, and `:ctrl` boolean options add
  terminal modifier flags.
  """
  @spec click(t(), String.t(), keyword()) :: term() | {:error, interaction_error() | term()}
  def click(%__MODULE__{} = session, id, opts \\ []) when is_binary(id) and is_list(opts) do
    action = opts |> Keyword.get(:action, :press) |> normalize_mouse_action!()

    with {:ok, {x, y}} <- mouse_position(session, id, Keyword.get(opts, :at, :center)) do
      mouse =
        %{"button" => "left", "action" => action, "x" => x, "y" => y}
        |> put_mouse_modifiers(opts)

      input(session, %{"mouse" => mouse})
    end
  end

  @doc """
  Dispatches a mouse-wheel event at a rendered element ID.

  `direction` is `:up` or `:down`. Use the positive integer `:repeat` option to
  represent a coalesced wheel burst; `:at` and modifier options behave as in
  `click/3`.
  """
  @spec wheel(t(), String.t(), wheel_direction(), keyword()) ::
          term() | {:error, interaction_error() | term()}
  def wheel(session, id, direction, opts \\ [])

  def wheel(%__MODULE__{} = session, id, direction, opts)
      when is_binary(id) and direction in [:up, :down] and is_list(opts) do
    repeat = opts |> Keyword.get(:repeat, 1) |> normalize_wheel_repeat!()
    button = if direction == :up, do: "wheel_up", else: "wheel_down"

    with {:ok, {x, y}} <- mouse_position(session, id, Keyword.get(opts, :at, :center)) do
      mouse =
        %{
          "button" => button,
          "action" => "press",
          "repeat" => repeat,
          "x" => x,
          "y" => y
        }
        |> put_mouse_modifiers(opts)

      input(session, %{"mouse" => mouse})
    end
  end

  def wheel(%__MODULE__{}, id, direction, opts) when is_binary(id) and is_list(opts) do
    raise ArgumentError, "expected wheel direction to be :up or :down, got: #{inspect(direction)}"
  end

  @doc "Dispatches a decoded key or input event to the view."
  @spec input(t(), term()) :: term()
  def input(%__MODULE__{} = session, key) do
    ChildServer.dispatch_input(session.pid, key)
  end

  @doc "Dispatches a named event and unrestricted payload directly to the view."
  @spec event(t(), Breeze.View.event_name(), Breeze.View.named_event_payload()) :: term()
  def event(%__MODULE__{} = session, change, event) do
    ChildServer.dispatch_event(session.pid, change, event)
  end

  @doc "Dispatches a message to the view's `handle_info/2` callback."
  @spec info(t(), term()) :: term()
  def info(%__MODULE__{} = session, message) do
    ChildServer.dispatch_info(session.pid, message, session.terminal)
  end

  @doc "Returns the current metadata for the view session."
  @spec metadata(t()) :: term()
  def metadata(%__MODULE__{} = session) do
    ChildServer.metadata(session.pid)
  end

  @doc "Stops a test session."
  @spec stop(t()) :: :ok
  def stop(%__MODULE__{pid: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
    :ok
  end

  defp settle_layout(session) do
    case render(session) do
      {:ok, _content} -> {:ok, ChildServer.layout_snapshot(session.pid)}
      other -> other
    end
  end

  defp mouse_position(session, id, at) do
    with {:ok, %{mouse_targets: targets}} <- settle_layout(session) do
      case Map.fetch(targets, id) do
        {:ok, bounds} -> position_in_bounds(id, bounds, at)
        :error -> {:error, {:mouse_target_not_found, id}}
      end
    end
  end

  defp position_in_bounds(id, bounds, at) when is_map(bounds) do
    with {:ok, visible} <- visible_bounds(id, bounds) do
      position_in_visible_bounds(id, bounds, visible, at)
    end
  end

  defp position_in_bounds(id, _bounds, _at), do: {:error, {:invalid_mouse_target, id}}

  defp visible_bounds(id, bounds) do
    with left when is_integer(left) <- Map.get(bounds, :left),
         top when is_integer(top) <- Map.get(bounds, :top),
         right when is_integer(right) <- Map.get(bounds, :right),
         bottom when is_integer(bottom) <- Map.get(bounds, :bottom) do
      visible = %{
        left: max(left, integer_bound(bounds, :clip_left, left)),
        top: max(top, integer_bound(bounds, :clip_top, top)),
        right: min(right, integer_bound(bounds, :clip_right, right)),
        bottom: min(bottom, integer_bound(bounds, :clip_bottom, bottom))
      }

      if visible.left <= visible.right and visible.top <= visible.bottom do
        {:ok, visible}
      else
        {:error, {:mouse_target_not_found, id}}
      end
    else
      _ -> {:error, {:invalid_mouse_target, id}}
    end
  end

  defp position_in_visible_bounds(_id, _bounds, visible, :center) do
    {:ok, {div(visible.left + visible.right, 2), div(visible.top + visible.bottom, 2)}}
  end

  defp position_in_visible_bounds(id, bounds, visible, {column, row})
       when is_integer(column) and column >= 0 and is_integer(row) and row >= 0 do
    point = {Map.fetch!(bounds, :left) + column, Map.fetch!(bounds, :top) + row}

    if point_in_bounds?(point, visible) do
      {:ok, point}
    else
      {:error, {:point_outside_element, id, {column, row}}}
    end
  end

  defp position_in_visible_bounds(_id, _bounds, _visible, at) do
    raise ArgumentError,
          "expected :at to be :center or a non-negative {column, row}, got: #{inspect(at)}"
  end

  defp point_in_bounds?({x, y}, bounds) do
    x >= bounds.left and x <= bounds.right and y >= bounds.top and y <= bounds.bottom
  end

  defp integer_bound(bounds, key, fallback) do
    case Map.get(bounds, key) do
      value when is_integer(value) -> value
      _value -> fallback
    end
  end

  defp put_mouse_modifiers(mouse, opts) do
    mouse
    |> maybe_put_mouse_modifier("shiftKey", Keyword.get(opts, :shift, false))
    |> maybe_put_mouse_modifier("altKey", Keyword.get(opts, :alt, false))
    |> maybe_put_mouse_modifier("ctrlKey", Keyword.get(opts, :ctrl, false))
  end

  defp maybe_put_mouse_modifier(mouse, key, true), do: Map.put(mouse, key, true)
  defp maybe_put_mouse_modifier(mouse, _key, _value), do: mouse

  defp normalize_mouse_action!(action) when action in [:press, "press"], do: "press"
  defp normalize_mouse_action!(action) when action in [:release, "release"], do: "release"

  defp normalize_mouse_action!(action) do
    raise ArgumentError, "expected :action to be :press or :release, got: #{inspect(action)}"
  end

  defp normalize_wheel_repeat!(repeat) when is_integer(repeat) and repeat > 0, do: repeat

  defp normalize_wheel_repeat!(repeat) do
    raise ArgumentError, "expected :repeat to be a positive integer, got: #{inspect(repeat)}"
  end

  defp normalize_size!({width, height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{width: width, height: height}
  end

  defp normalize_size!(%{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{width: width, height: height}
  end

  defp normalize_size!(size) do
    raise ArgumentError,
          "expected size to be a positive {width, height} tuple or dimensions map, got: #{inspect(size)}"
  end

  defp build_terminal({width, height}) when is_integer(width) and is_integer(height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end

  defp build_terminal(%{width: width, height: height})
       when is_integer(width) and is_integer(height) do
    %Termite.Terminal{size: %{width: width, height: height}}
  end
end
