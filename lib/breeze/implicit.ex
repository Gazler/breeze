defmodule Breeze.Implicit do
  @moduledoc """
  Behaviour implemented by stateful renderer extensions.

  An implicit owns state for an element without requiring the parent view to
  handle every interaction itself. It must implement `init/3` and
  `handle_modifiers/3`. Event handling and animation are optional.

  ## Initialization

  `children` is a list of attribute maps for elements owned by the implicit.
  `root_attrs` is the implicit root's attribute map with `:id` included.
  `last_state` is the state from the preceding render; once layout is known it
  also contains the previous `Breeze.Viewport` under `:__element__`.

  An initializer can return the state directly, `{:ok, state}`, or
  `{:ok, state, options}`. The options are:

    * `:rerender_every` - a positive interval in milliseconds for asynchronous
      `animate/5` calls. It has no effect unless `animate/5` is implemented.
    * `:active_when_pending` - run periodic animation only while an input event
      is pending. If this and `:active_when_focused` are both true, pending state
      takes precedence.
    * `:active_when_focused` - run periodic animation only while the implicit
      root is focused.
    * `:captures_keys` - `true` to capture every key, or a list of key names to
      capture selectively.
    * `:captures_printable_keys` - capture printable input and supported text
      editing keys.
    * `:captures_control_keys` - capture control-modified key input.
    * `:captures_focus_keys` - capture Tab and Shift-Tab input.
    * `:requires_layout_rerender` - rerender after the implicit's dimensions
      change so layout-dependent state can settle.
    * `:state_change_requires_rerender` - set to `false` when changing only the
      implicit state does not require another render. The default is `true`.

  ## Events

  `handle_event/3` receives a reserved event-kind argument, the event payload,
  and the current implicit state. Breeze adds the target's `Breeze.Viewport` to
  the payload as `"element"` when one is available.

  Every reply stores the returned state. `{:noreply, state}` stops there.
  `{{:change, event}, state}` and `{{:submit, event}, state}` route `event` through
  the root element's `br-change` or `br-submit` handler. A change reply may also
  contain `focus: id` (or `focus: nil`) as its third element. Finally,
  `{{:delegate, id}, state}` sends the original event to another implicit.

  ## Render modifiers

  `handle_modifiers/3` runs for the implicit root and each owned child during
  rendering. Its first argument is `:root` or `:child`; its second is the
  element's attribute keyword list, with `:layout_element` added when a previous
  `Breeze.Viewport` is available.

  It returns a keyword list. `style: value` adds a binary, map, or list of style
  modifiers. `scroll_y: top`, `scroll_x: left`, and
  `scroll: {top, left}` control the viewport offset. Any other atom/value pair
  becomes a renderer flag; common examples include `selected: true`,
  `default_focus: true`, and `focus_scope: :trap`.

  ## Animation

  `animate/5` receives the element type, its rendered `BackBreeze.Box`, the
  element flags, implicit state, and a context map. It may return a box directly,
  `{:ok, box}`, or `{:ok, box, options}`. The only animation option is
  `overlays: overlays`; overlays are applied during asynchronous animation
  passes.

  Breeze calls `animate/5` for roots and children during a normal render.
  `:rerender_every` additionally schedules lightweight asynchronous calls for
  the root. The context contains `:phase`, `:frame`, `:now`, `:pending?`,
  `:focused?`, `:last_render_at`, `:last_interaction_at`, `:theme`, `:id`, and
  `:layout`.
  """

  @typedoc "State owned by an implicit implementation."
  @type state :: term()

  @typedoc "The implicit root or one of its child elements."
  @type element_type :: :root | :child

  @typedoc "Attributes collected from an implicit element."
  @type attributes :: map()

  @typedoc "Renderer flags attached to an implicit element."
  @type flags :: keyword()

  @typedoc "A decoded terminal key name."
  @type key_name :: String.t()

  @typedoc "An option returned while initializing implicit state."
  @type init_option ::
          {:rerender_every, pos_integer()}
          | {:active_when_pending, boolean()}
          | {:active_when_focused, boolean()}
          | {:captures_keys, boolean() | [key_name()]}
          | {:captures_printable_keys, boolean()}
          | {:captures_control_keys, boolean()}
          | {:captures_focus_keys, boolean()}
          | {:requires_layout_rerender, boolean()}
          | {:state_change_requires_rerender, boolean()}
  @typedoc "A valid return value from `c:init/3`."
  @type init_result :: state() | {:ok, state()} | {:ok, state(), [init_option()]}

  @typedoc "An option returned with an implicit event action."
  @type event_option :: {:focus, String.t() | nil}

  @typedoc "A valid return value from `c:handle_event/3`."
  @type event_reply ::
          {:noreply, state()}
          | {{:change, map()}, state()}
          | {{:change, map()}, state(), [event_option()]}
          | {{:submit, map()}, state()}
          | {{:delegate, String.t()}, state()}
  @typedoc "A style, scroll, or state modifier returned during rendering."
  @type modifier ::
          {:style, binary() | map() | list()}
          | {:scroll_y, integer()}
          | {:scroll_x, integer()}
          | {:scroll, {integer(), integer()}}
          | {atom(), term()}
  @typedoc "Runtime context supplied to `c:animate/5`."
  @type animation_context :: %{
          required(:phase) => :base | :async,
          required(:frame) => non_neg_integer(),
          required(:now) => integer() | nil,
          required(:pending?) => boolean(),
          required(:focused?) => boolean(),
          required(:last_render_at) => integer() | nil,
          required(:last_interaction_at) => integer() | nil,
          required(:theme) => Breeze.Theme.t(),
          required(:id) => String.t() | nil,
          required(:layout) => Breeze.Viewport.t() | nil
        }
  @typedoc "An option returned from an animation pass."
  @type animation_option :: {:overlays, [map()]}

  @typedoc "A valid return value from `c:animate/5`."
  @type animation_reply ::
          %BackBreeze.Box{}
          | {:ok, %BackBreeze.Box{}}
          | {:ok, %BackBreeze.Box{}, [animation_option()]}

  @doc """
  Initializes state from the owned children, root attributes, and previous state.
  """
  @callback init([attributes()], attributes(), state()) :: init_result()

  @doc """
  Handles an event captured by the implicit and returns its next state and action.
  """
  @callback handle_event(term(), map(), state()) :: event_reply()

  @doc """
  Returns renderer modifiers for the implicit root or one of its children.
  """
  @callback handle_modifiers(element_type(), flags(), state()) :: [modifier()]

  @doc """
  Transforms a rendered box during the normal render or a periodic animation pass.
  """
  @callback animate(
              element_type(),
              %BackBreeze.Box{},
              flags(),
              state(),
              animation_context()
            ) :: animation_reply()

  @optional_callbacks handle_event: 3, animate: 5
end
