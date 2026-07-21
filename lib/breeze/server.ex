defmodule Breeze.Server do
  @moduledoc """
  Public server entrypoint for Breeze applications.

  ## Startup Options

  `start_link/1` and `run/1` accept these public startup options:

    * `:view` - the root view module. Required.
    * `:start_opts` - keyword options passed to the root view's
      `mount/2`. Defaults to `[]`.
    * `:theme` - a `Breeze.Theme`, theme map/keyword, or built-in
      theme atom.
    * `:global_keybindings` - app-wide keybindings checked before
      focused event handling.
    * `:reload` - enables live code reload. Defaults to
      `Application.get_env(:breeze, :reload, false)`. Pass `true`
      to enable reload in dev, or a keyword list for reload options.
    * `:inspector` - enables inspector support. Defaults to `false`.
      Pass `true` or keyword options such as `:toggle_key`, `:move_key`,
      and `remote: false` to keep inspection local without starting
      distributed Erlang. See `Breeze.Inspector` for the complete feature and
      option reference.
    * `:logger` - configures Breeze log capture. Pass `:attach` to add a
      handler while preserving existing handlers, `:replace` to temporarily
      silence the default handler, a keyword list with `:mode` and
      `:max_entries`, or `false` to disable capture. Inspector-enabled servers
      default to `:attach`; other servers default to `false`.
    * `:alt_screen` - enters the terminal alternate screen. Defaults
      to `true`.
    * `:hide_cursor` - hides the terminal cursor while the app runs.
      Defaults to `true`.
    * `:enhanced_keyboard` - enables enhanced keyboard reporting.
      Defaults to `true`.
    * `:mouse` - enables mouse tracking. Defaults to `false`. Pass
      `true` for click mode or keyword options for
      `Termite.Screen.enable_mouse/2`.
    * `:terminal_opts` - options passed to `Termite.Terminal.start/1`
      when Breeze starts the terminal.
    * `:terminal` - an existing `%Termite.Terminal{}` to use instead
      of starting one.
    * `:halt_fun` - function called when the input router exits.
      Defaults to `System.halt/0` outside IEx and no-op inside IEx.
      Use `fn -> :ok end` for embedded or SSH sessions.
    * `:render_errors` - crash rendering options. Pass
      `view: MyErrorView` to override the crash screen view. Defaults
      to the built-in crash view. Pass `keybindings: [...]` to configure
      custom crash screen actions as `{key, label, action}` tuples.
      Supported actions are `:restart`, `:stop`, and `:copy_details`.
      Custom error views receive these assigns: `@view`, the crashed
      root view module; `@crash`, the crash map; `@kind`, the crash
      kind; `@reason`, the exception, exit reason, or thrown value;
      `@stacktrace`, the captured stacktrace; and
      `@breeze.keybindings`, the configured visible keybindings.
  """

  use GenServer

  alias Breeze.Server.{Debug, Dimensions, Error, Frame, Input, Inspector, RenderTracking}
  alias Breeze.Server.State

  @flush_input_batch :flush_input_batch
  @logger_collector_attempts 3
  defstruct [
    :terminal,
    :reader,
    :input_router,
    :child_view_supervisor,
    :owns_child_view_supervisor?,
    :remote_inspector_supervisor,
    :view_pid,
    :view,
    :start_opts,
    :alt_screen?,
    :alt_screen_active?,
    :hide_cursor?,
    :mouse_mode,
    :reload_opts,
    :reloader_pid,
    :logger_collector,
    :focused,
    :theme,
    :apply_theme_defaults?,
    :render_errors,
    :child_process_flags,
    :clipboard_opts,
    :crash,
    :crash_scrollback?,
    :terminal_size_override,
    children: %{},
    input: %State.Input{},
    frame: %State.Frame{},
    debug: %State.Debug{},
    inspector_state: %State.Inspector{},
    rendered: %State.Rendered{}
  ]

  @typedoc "A public Breeze server startup option."
  @type option ::
          {:view, module()}
          | {:start_opts, keyword()}
          | {:alt_screen, boolean()}
          | {:hide_cursor, boolean()}
          | {:enhanced_keyboard, boolean()}
          | {:mouse, boolean() | keyword()}
          | {:terminal_opts, keyword()}
          | {:terminal, %Termite.Terminal{}}
          | {:reload, boolean() | keyword()}
          | {:theme, Breeze.Theme.t() | map() | keyword() | atom()}
          | {:halt_fun, (-> term())}
          | {:global_keybindings, list()}
          | {:inspector, boolean() | keyword()}
          | {:logger, false | :attach | :replace | keyword()}
          | {:render_errors, keyword()}

  @doc """
  Start the Breeze application.

  See the module documentation for startup options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    Breeze.InputRouter.start_link(opts)
  end

  @doc """
  Run the Breeze application until it exits.

  This is intended for interactive sessions such as IEx. It starts the terminal
  input router without linking it to the caller, waits for the app to stop, and
  returns `:ok` instead of halting the VM.
  """
  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts) do
    opts =
      opts
      |> Keyword.put_new_lazy(:halt_fun, fn -> fn -> :ok end end)
      |> put_internal_new(:pause_iex, true)

    case Breeze.InputRouter.start(opts) do
      {:ok, pid} ->
        ref = Process.monitor(pid)

        receive do
          {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
          {:DOWN, ^ref, :process, ^pid, :shutdown} -> :ok
          {:DOWN, ^ref, :process, ^pid, {:shutdown, _}} -> :ok
          {:DOWN, ^ref, :process, ^pid, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  @spec start_app_link(keyword()) :: GenServer.on_start()
  def start_app_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc false
  def live_snapshot(pid, child_id, opts \\ []) when is_pid(pid) and is_binary(child_id) do
    GenServer.call(pid, {:live_snapshot, child_id, opts})
  end

  @doc false
  def dispatch_live_input(pid, child_id, input, opts \\ [])
      when is_pid(pid) and is_binary(child_id) do
    GenServer.call(pid, {:live_input, child_id, input, opts})
  end

  @doc false
  def request_live_snapshot(pid, child_id, recipient, ref, opts \\ [])
      when is_pid(pid) and is_binary(child_id) and is_pid(recipient) do
    GenServer.cast(pid, {:live_snapshot, child_id, recipient, ref, opts})
  end

  @doc false
  def focused_implicit_metadata(pid) do
    GenServer.call(pid, :focused_implicit_meta)
  end

  @doc false
  @spec inspector_render_tree(pid(), keyword()) :: map()
  def inspector_render_tree(pid, opts \\ []) do
    GenServer.call(pid, {:inspector_render_tree, opts})
  end

  @doc false
  @spec select_inspector(pid(), String.t()) :: :ok
  def select_inspector(pid, id) when is_pid(pid) and is_binary(id) do
    GenServer.cast(pid, {:select_inspector, id})
  end

  defp internal_opts(opts), do: keyword_group(opts, :internal)

  defp render_errors_opts(opts), do: keyword_group(opts, :render_errors)

  defp put_internal_new(opts, key, value) do
    if Keyword.has_key?(keyword_group(opts, :internal), key) do
      opts
    else
      Keyword.put(opts, :internal, Keyword.put(keyword_group(opts, :internal), key, value))
    end
  end

  defp keyword_group(opts, key) do
    case Keyword.get(opts, key, []) do
      group when is_list(group) -> group
      _other -> []
    end
  end

  defp child_view_supervisor(internal_opts) do
    case Keyword.get(internal_opts, :child_view_supervisor) do
      supervisor when is_pid(supervisor) ->
        {supervisor, false}

      _supervisor ->
        {:ok, supervisor} = Breeze.ChildViewSupervisor.start_link()
        {supervisor, true}
    end
  end

  defp remote_inspector_supervisor(false, _internal_opts), do: nil

  defp remote_inspector_supervisor(true, internal_opts) do
    case Keyword.get(internal_opts, :remote_inspector_supervisor) do
      supervisor when is_pid(supervisor) ->
        supervisor

      _supervisor ->
        {:ok, supervisor} = Breeze.RemoteInspector.Supervisor.start_link()
        supervisor
    end
  end

  defp logger_collector(config, _runtime_opts, _attempts) when config in [false, nil],
    do: {:ok, nil}

  defp logger_collector(config, runtime_opts, attempts) do
    with {:ok, pid} <- ensure_logger_collector(),
         :ok <- Breeze.Logger.Collector.configure(self(), config, runtime_opts) do
      {:ok, pid}
    else
      {:error, :not_started} when attempts > 1 ->
        logger_collector(config, runtime_opts, attempts - 1)

      other ->
        other
    end
  end

  defp ensure_logger_collector do
    case Process.whereis(Breeze.Logger.Collector) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        case Breeze.Logger.Collector.start_link(ephemeral: true) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} when is_pid(pid) -> {:ok, pid}
          other -> other
        end
    end
  end

  @impl true
  def init(opts) do
    view = Keyword.fetch!(opts, :view)
    start_opts = Keyword.get(opts, :start_opts, [])
    internal_opts = internal_opts(opts)
    child_process_flags = Keyword.get(internal_opts, :child_process_flags, [])
    terminal_size_override = Keyword.get(internal_opts, :terminal_size_override)

    {child_view_supervisor, owns_child_view_supervisor?} =
      child_view_supervisor(internal_opts)

    render_errors = Error.normalize(render_errors_opts(opts))

    terminal =
      opts |> Keyword.fetch!(:terminal) |> apply_terminal_size_override(terminal_size_override)

    theme = Breeze.Theme.new(Keyword.get(opts, :theme), terminal: terminal)
    theme_source = Keyword.get(opts, :theme)
    apply_theme_defaults? = Breeze.Theme.defaults_enabled?(Keyword.get(opts, :theme))
    inspector_config = Keyword.get(opts, :inspector, false)
    inspector_enabled? = inspector_enabled?(inspector_config)

    remote_inspector_enabled? =
      inspector_enabled? and Breeze.Inspector.remote?(%{inspector: inspector_config})

    remote_inspector_supervisor =
      remote_inspector_supervisor(remote_inspector_enabled?, internal_opts)

    logger_config =
      if Keyword.has_key?(opts, :logger) do
        Keyword.fetch!(opts, :logger)
      else
        if remote_inspector_enabled?, do: :attach, else: false
      end

    if remote_inspector_enabled? do
      _ = Breeze.RemoteInspector.ensure_app_distribution(view: view)
    end

    {:ok, logger_collector} =
      logger_collector(
        logger_config,
        [remote_inspector: remote_inspector_enabled?, view: view],
        @logger_collector_attempts
      )

    session = self()

    child_start_result =
      Breeze.ChildViewSupervisor.start_child(
        child_view_supervisor,
        view: view,
        start_opts: start_opts,
        terminal: terminal,
        theme: theme,
        theme_source: theme_source,
        apply_theme_defaults?: apply_theme_defaults?,
        process_flags: child_process_flags,
        render_tree?: inspector_enabled?,
        server: self(),
        global_keybindings: Keyword.get(opts, :global_keybindings, []),
        invalidate: fn
          nil -> send(session, :child_invalidated)
          child_id -> send(session, {:child_invalidated, child_id})
        end
      )

    {:ok, view_pid} = child_start_result

    Process.monitor(view_pid)

    {focused, theme, apply_theme_defaults?} =
      case Breeze.ChildServer.metadata(view_pid) do
        %{
          focused: focused,
          theme: child_theme,
          apply_theme_defaults?: child_apply_theme_defaults?
        } ->
          {focused, child_theme, child_apply_theme_defaults?}

        %{focused: focused, theme: child_theme} ->
          {focused, child_theme, apply_theme_defaults?}

        %{focused: focused} ->
          {focused, theme, apply_theme_defaults?}

        _ ->
          {nil, theme, apply_theme_defaults?}
      end

    state =
      %__MODULE__{
        terminal: terminal,
        reader: terminal.reader,
        input_router: Keyword.get(opts, :input_router),
        child_view_supervisor: child_view_supervisor,
        owns_child_view_supervisor?: owns_child_view_supervisor?,
        remote_inspector_supervisor: remote_inspector_supervisor,
        view_pid: view_pid,
        view: view,
        start_opts: start_opts,
        alt_screen?: Keyword.get(opts, :alt_screen, true),
        alt_screen_active?: Keyword.get(opts, :alt_screen, true),
        hide_cursor?: Keyword.get(opts, :hide_cursor, true),
        mouse_mode: Keyword.get(opts, :mouse, false),
        reload_opts:
          normalize_reload_opts(
            Keyword.get(opts, :reload, Application.get_env(:breeze, :reload, false))
          ),
        logger_collector: logger_collector,
        focused: focused,
        theme: theme,
        apply_theme_defaults?: apply_theme_defaults?,
        render_errors: render_errors,
        child_process_flags: child_process_flags,
        clipboard_opts: Keyword.get(internal_opts, :clipboard, []),
        terminal_size_override: terminal_size_override,
        input: %State.Input{
          global_keybindings: Keyword.get(opts, :global_keybindings, [])
        },
        frame: %State.Frame{last_render_at: System.monotonic_time(:millisecond)},
        debug: %State.Debug{},
        inspector_state: %State.Inspector{config: Keyword.get(opts, :inspector, false)},
        rendered: %State.Rendered{tracking_table: RenderTracking.new_table()}
      }

    state = maybe_start_reloader(state)

    if remote_inspector_enabled? do
      :ok = Breeze.RemoteInspector.register_app(self())

      {:ok, _connector} =
        Breeze.RemoteInspector.Supervisor.start_connector(
          state.remote_inspector_supervisor,
          self()
        )
    end

    {:ok, render_base(state)}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    {:reply, Debug.snapshot(state), state}
  end

  def handle_call({:live_snapshot, child_id, opts}, _from, state) do
    {reply, state} = render_live_snapshot(state, child_id, opts)
    {:reply, reply, state}
  end

  def handle_call({:live_input, child_id, input, opts}, _from, state) do
    {reply, state} = dispatch_live_child_input(state, child_id, input, opts)
    {:reply, reply, state}
  end

  def handle_call(:inspector_snapshot, _from, state) do
    {:reply, Breeze.Inspector.snapshot(state), state}
  end

  def handle_call({:inspector_render_tree, opts}, _from, state) do
    {:reply, Breeze.Inspector.render_tree(state, opts), state}
  end

  def handle_call(:focused_implicit_meta, _from, state) do
    {:reply, focused_implicit_meta(state), state}
  end

  @impl true
  def handle_cast({:live_snapshot, child_id, recipient, ref, opts}, state) do
    if is_pid(recipient) do
      {reply, state} = render_live_snapshot(state, child_id, opts)

      send(
        recipient,
        {:breeze_live_snapshot, ref, child_id, reply}
      )

      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:subscribe_debug, subscriber}, state) do
    if is_pid(subscriber), do: Process.monitor(subscriber)

    state = update_debug(state, subscribers: MapSet.put(state.debug.subscribers, subscriber))

    state =
      if state.debug.stats == %{} do
        state
      else
        Debug.push_now(state)
      end

    {:noreply, state}
  end

  def handle_cast({:subscribe_inspector, subscriber}, state) do
    if is_pid(subscriber), do: Process.monitor(subscriber)

    state =
      update_inspector(state,
        subscribers: MapSet.put(state.inspector_state.subscribers, subscriber)
      )

    {:noreply, Inspector.push_snapshot_now(state)}
  end

  def handle_cast({:select_inspector, id}, state) when is_binary(id) do
    state =
      if Breeze.Inspector.enabled?(state) do
        state
        |> update_inspector(selected_id: id, hovered_id: id)
        |> Breeze.Inspector.sync_selected_id()
        |> maybe_render_base(:remote_inspector_select)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info({reader, {:data, data}}, %{reader: reader} = state) do
    started_at = System.monotonic_time(:microsecond)

    state =
      state
      |> Input.enqueue(Breeze.Input.decode(data))
      |> Debug.put_stat(:last_input_us, System.monotonic_time(:microsecond) - started_at)
      |> schedule_input_flush()

    {:noreply, state}
  end

  def handle_info({reader, {:signal, :winch}}, %{reader: reader, crash: crash} = state)
      when not is_nil(crash) do
    terminal = resize_terminal(state)
    {:noreply, render_crash(%{state | terminal: terminal}, force_full_redraw?: true)}
  end

  def handle_info({reader, {:signal, :winch}}, %{reader: reader} = state) do
    terminal = resize_terminal(state)
    state = %{state | terminal: terminal}

    case safe_call(fn ->
           Breeze.ChildServer.dispatch_info(state.view_pid, :resize, terminal)
         end) do
      {:ok, {:stop, _focused}} ->
        stop(state)

      {:ok, {:noreply, focused}} ->
        {:noreply, force_full_redraw(%{state | focused: focused}, :resize)}

      {:crash, crash} ->
        {:noreply, enter_crash_state(state, crash)}
    end
  end

  def handle_info({:ensure_runtime_palette, :system}, %{input_router: pid} = state)
      when is_pid(pid) do
    send(pid, {:ensure_runtime_palette, :system})
    {:noreply, state}
  end

  def handle_info({:clear_crash_notice, ref}, %{crash: %{notice_ref: ref} = crash} = state) do
    crash = Map.drop(crash, [:notice, :notice_ref])
    {:noreply, state |> Map.put(:crash, crash) |> render_crash()}
  end

  def handle_info({:clear_crash_notice, _ref}, state), do: {:noreply, state}

  def handle_info(:child_invalidated, %{crash: crash} = state) when not is_nil(crash) do
    {:noreply, state}
  end

  def handle_info(:child_invalidated, state) do
    state = Debug.increment_stat(state, :child_invalidated_count)
    {:noreply, maybe_render_base(state, :child_invalidated)}
  end

  def handle_info({:child_invalidated, _child_id}, %{crash: crash} = state)
      when not is_nil(crash) do
    {:noreply, state}
  end

  def handle_info({:child_invalidated, child_id}, state) do
    state =
      if debug_child_id?(child_id) do
        state
      else
        Debug.increment_stat(state, :child_invalidated_count)
      end

    {:noreply, maybe_render_invalidated_child(state, child_id)}
  end

  def handle_info(@flush_input_batch, state) do
    state = Debug.increment_stat(state, :flush_input_batch_count)
    state = update_input(state, flush_scheduled?: false)

    case flush_input_batch(state) do
      {:stop, state} ->
        stop(state)

      {:noreply, state} ->
        state =
          state
          |> maybe_render_after_input()
          |> schedule_input_flush()

        {:noreply, state}
    end
  end

  def handle_info(:animation_tick, %{frame: %{decorations: []}} = state) do
    state = Debug.increment_stat(state, :animation_tick_count)
    {:noreply, %{state | frame: %{state.frame | animation_timer: nil, next_tick_at: nil}}}
  end

  def handle_info(:animation_tick, state) do
    started_at = System.monotonic_time(:microsecond)
    state = Debug.increment_stat(state, :animation_tick_count)

    state =
      state
      |> update_frame(animation_timer: nil, next_tick_at: nil)
      |> advance_decorations()
      |> render_frame()
      |> Debug.put_stat(:last_animation_us, System.monotonic_time(:microsecond) - started_at)
      |> schedule_animation()

    {:noreply, state}
  end

  def handle_info(:debug_push, state) do
    state =
      state
      |> update_debug(push_timer: nil)
      |> Debug.push_now()

    {:noreply, state}
  end

  def handle_info({:reload, :code_changed, _files}, state) do
    {:noreply, reload_after_code_change(state)}
  end

  def handle_info({:reload, :compile_error, reason, _files}, state) do
    shutdown_view_processes(state)
    {:noreply, enter_crash_state(state, crash_info(:error, reason, []))}
  end

  def handle_info({:event_reply, ref, reply}, %{input: %{pending_ref: ref}} = state) do
    case apply_event_reply(state, reply) do
      {:noreply, state} -> {:noreply, schedule_input_flush(state)}
      other -> other
    end
  end

  def handle_info({:event_reply, _ref, _reply}, state), do: {:noreply, state}

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{view_pid: pid} = state) do
    handle_root_view_down(reason, state)
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    {:noreply, remove_monitored_process(state, pid, ref)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp handle_root_view_down(_reason, state) when not is_nil(state.crash), do: {:noreply, state}
  defp handle_root_view_down(:normal, state), do: stop(state)

  defp handle_root_view_down(reason, state) do
    {:noreply, enter_crash_state(state, crash_info(:exit, reason, []))}
  end

  defp remove_monitored_process(state, pid, ref) do
    cond do
      MapSet.member?(state.debug.subscribers, pid) ->
        update_debug(state, subscribers: MapSet.delete(state.debug.subscribers, pid))

      MapSet.member?(state.inspector_state.subscribers, pid) ->
        update_inspector(state,
          subscribers: MapSet.delete(state.inspector_state.subscribers, pid)
        )

      true ->
        %{state | children: remove_child_by_ref(state.children, ref)}
    end
  end

  defp remove_child_by_ref(children, ref) do
    children
    |> Enum.reject(fn {_id, child} -> child.ref == ref end)
    |> Map.new()
  end

  defp update_input(state, updates), do: %{state | input: struct!(state.input, updates)}
  defp update_frame(state, updates), do: %{state | frame: struct!(state.frame, updates)}
  defp update_debug(state, updates), do: %{state | debug: struct!(state.debug, updates)}

  defp update_inspector(state, updates),
    do: %{state | inspector_state: struct!(state.inspector_state, updates)}

  defp inspector_enabled?(config), do: config not in [false, nil]

  defp update_rendered(state, updates), do: %{state | rendered: struct!(state.rendered, updates)}

  defp flush_input_batch(state) do
    Input.flush_batch(state, input_handlers())
  end

  defp input_handlers do
    %{
      batchable_printable?: &batchable_printable_input?/2,
      sync_message?: &sync_input_message?/2,
      handle_mouse: &handle_mouse/2,
      handle_sync_or_deferred: &handle_deferred_or_sync_input/2
    }
  end

  defp handle_deferred_or_sync_input(decoded, state) do
    if sync_input_message?(decoded, state) do
      handle_decoded_sync_input(decoded, state)
    else
      handle_deferred_input(decoded, state)
    end
  end

  defp handle_decoded_sync_input({:mouse, _event}, %{crash: crash} = state)
       when not is_nil(crash) do
    {:noreply, state}
  end

  defp handle_decoded_sync_input({:mouse, event}, state) do
    cond do
      Inspector.picks_mouse?(state) ->
        {:noreply,
         state
         |> touch_interaction()
         |> Inspector.select_target(event)
         |> maybe_render_base(:inspector_select)}

      true ->
        handle_mouse(event, state)
    end
  end

  defp handle_decoded_sync_input({:key, key}, %{crash: crash} = state) when not is_nil(crash) do
    handle_crash_input({:key, key}, touch_interaction(state))
  end

  defp handle_decoded_sync_input({:key, key}, state) do
    state
    |> touch_interaction()
    |> handle_sync_key_action(sync_key_action(key, state), key)
  end

  defp handle_deferred_input({:key, _key}, %{input: %{pending_ref: ref}} = state)
       when not is_nil(ref) do
    {:noreply, state}
  end

  defp handle_deferred_input({:key, key}, %{crash: crash} = state) when not is_nil(crash) do
    handle_crash_input({:key, key}, touch_interaction(state))
  end

  defp handle_deferred_input({:key, key}, state) do
    {:noreply, start_async_dispatch(touch_interaction(state), key)}
  end

  defp handle_deferred_input(_decoded, state), do: {:noreply, state}

  defp sync_input_message?({:mouse, _event}, %{input: %{pending_ref: nil}}), do: true
  defp sync_input_message?({:mouse, _event}, _state), do: false

  defp sync_input_message?({:key, _key}, %{crash: crash}) when not is_nil(crash), do: true

  defp sync_input_message?({:key, key}, state) do
    input_key = Input.key_name(key)

    Inspector.toggle_key?(input_key, state) or
      Inspector.move_key?(input_key, state) or
      stop_global_key?(key, state) or
      (is_nil(state.input.pending_ref) and
         (tab_input?(key) or sync_input?(state, input_key)))
  end

  defp sync_input_message?(_, _state), do: false

  defp apply_input_reply(state, reply) do
    case reply do
      {:stop, _focused} ->
        {:stop, state}

      {:stop, _focused, _consumed} ->
        {:stop, state}

      {:noreply, focused} ->
        {:noreply, state |> Map.put(:focused, focused) |> mark_input_render_after_flush(true)}

      {:noreply, focused, render?} ->
        {:noreply, state |> Map.put(:focused, focused) |> mark_input_render_after_flush(render?)}
    end
  end

  defp apply_hierarchy_input_reply(state, reply) do
    case apply_input_reply(state, reply) do
      {:noreply, next_state} ->
        {:noreply, maybe_schedule_sync_child_render(next_state, state.focused, reply)}

      other ->
        other
    end
  end

  defp mark_input_render_after_flush(state, true),
    do: update_input(state, render_after_flush?: true)

  defp mark_input_render_after_flush(state, _render?), do: state

  defp apply_event_reply(state, {:crash, crash}) do
    {:noreply, enter_crash_state(state, crash)}
  end

  defp apply_event_reply(state, {:stop, _focused}), do: stop(state)
  defp apply_event_reply(state, {:stop, _focused, _consumed}), do: stop(state)

  defp apply_event_reply(state, {:noreply, focused}) do
    {:noreply, finish_event_reply(state, focused, true)}
  end

  defp apply_event_reply(state, {:noreply, focused, render?}) do
    {:noreply, finish_event_reply(state, focused, render?)}
  end

  defp finish_event_reply(state, focused, true) do
    state
    |> finish_event_reply_state(focused)
    |> maybe_render_base(:event_reply)
  end

  defp finish_event_reply(state, focused, _render?) do
    finish_event_reply_state(state, focused)
  end

  defp finish_event_reply_state(state, focused) do
    state
    |> update_input(pending_ref: nil, pending_started_at: nil)
    |> Map.put(:focused, focused)
  end

  defp sync_key_action(key, state) do
    cond do
      stop_global_key?(key, state) -> :global_stop
      Inspector.toggle_key?(key, state) -> :inspector_toggle
      Inspector.move_key?(key, state) -> :inspector_move
      focused_implicit_captures_key?(state, key) -> :hierarchy
      tab_input?(key) -> :tab
      true -> :hierarchy
    end
  end

  defp handle_sync_key_action(state, :global_stop, _key) do
    {:stop, state}
  end

  defp handle_sync_key_action(state, :inspector_toggle, _key) do
    {:noreply,
     state
     |> Breeze.Inspector.toggle()
     |> maybe_render_base(:inspector_toggle)}
  end

  defp handle_sync_key_action(state, :inspector_move, _key) do
    {:noreply,
     state
     |> Breeze.Inspector.toggle_position()
     |> maybe_render_base(:inspector_move)}
  end

  defp handle_sync_key_action(state, :tab, key) do
    safe_apply_tab_input_reply(state, fn state ->
      Breeze.ChildServer.dispatch_input(state.view_pid, normalize_tab_input(key),
        invalidate: false
      )
    end)
  end

  defp handle_sync_key_action(state, :hierarchy, key) do
    safe_apply_hierarchy_input_reply(state, fn state ->
      dispatch_input_hierarchy(state, key)
    end)
  end

  defp touch_interaction(state) do
    update_input(state, last_interaction_at: System.monotonic_time(:millisecond))
  end

  defp sync_input?(state, key) do
    key in ["\t", "ShiftTab"] or focused_implicit?(state)
  end

  defp tab_input?(key), do: normalize_tab_input(key) in ["\t", "ShiftTab"]

  defp normalize_tab_input(%{"key" => key} = event) when key in ["\t", "Tab"] do
    if truthy_input_modifier?(Map.get(event, "shiftKey")) do
      "ShiftTab"
    else
      "\t"
    end
  end

  defp normalize_tab_input(key), do: key
  defp truthy_input_modifier?(value), do: value in [true, "true"]

  defp batchable_printable_input?(key, state) do
    Breeze.InputCapture.printable_key?(key) and
      focused_implicit_captures_printable_key?(state, key)
  end

  defp stop_global_key?(key, state) do
    Breeze.GlobalKeybindings.stop_action?(%{"key" => key}, state) and
      not focused_implicit_captures_key?(state, key)
  end

  defp focused_implicit?(%{focused: nil}), do: false

  defp focused_implicit?(state) do
    match?(%{focused_implicit_id: id} when not is_nil(id), focused_child_or_root_metadata(state))
  end

  defp focused_implicit_meta(%{focused: nil}), do: %{}

  defp focused_implicit_meta(state) do
    Map.get(focused_child_or_root_metadata(state), :focused_implicit_meta, %{})
  end

  defp focused_implicit_captures_printable_key?(state, key) do
    Breeze.InputCapture.captures_printable_key?(focused_implicit_meta(state), key)
  end

  defp focused_implicit_captures_key?(state, key) do
    Breeze.InputCapture.captures_key?(focused_implicit_meta(state), key)
  end

  defp focused_child_or_root_metadata(state) do
    case focused_child_chain(state) do
      [{_child_id, %{pid: pid}} | _] ->
        case safe_call(fn -> Breeze.ChildServer.metadata(pid) end) do
          {:ok, metadata} -> metadata
          {:crash, _crash} -> %{}
        end

      [] ->
        case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
          {:ok, metadata} -> metadata
          {:crash, _crash} -> %{}
        end
    end
  end

  defp handle_mouse(event, state) do
    state
    |> touch_interaction()
    |> safe_apply_input_reply(fn state ->
      Breeze.ChildServer.dispatch_input(state.view_pid, %{"mouse" => event},
        live_children: state.children
      )
    end)
  end

  defp render_base(state, cause \\ :unknown, attempts \\ 1)

  defp render_base(%{crash: crash} = state, _cause, _attempts) when not is_nil(crash),
    do: state

  defp render_base(state, cause, attempts) do
    try do
      tracking_ref = RenderTracking.begin(state.rendered.tracking_table)
      started_at = System.monotonic_time(:microsecond)
      profile_scope = make_ref()
      Breeze.DebugProfiler.reset(profile_scope)
      root_started_at = System.monotonic_time(:microsecond)

      {acc, box, decorations} =
        case safe_render_snapshot(state, tracking_ref, profile_scope) do
          {:ok, acc, box, decorations} ->
            {acc, box, decorations}

          :stopped ->
            throw({:stopped, state})
        end

      root_snapshot_us = System.monotonic_time(:microsecond) - root_started_at

      {metadata_focused, metadata_theme, metadata_apply_theme_defaults?} =
        safe_focused_metadata(state)

      focused = metadata_focused || state.focused

      %{
        missing: missing,
        seen: seen,
        decorations: child_decorations,
        child_timings: child_timings
      } = RenderTracking.finish(tracking_ref)

      profile_entries = Breeze.DebugProfiler.snapshot(profile_scope)
      state = reconcile_live_children(state, seen)
      {state, started?} = ensure_children(state, missing)

      continue_base_render(state, %{
        started?: started?,
        cause: cause,
        attempts: attempts,
        focused: focused,
        metadata_theme: metadata_theme,
        metadata_apply_theme_defaults?: metadata_apply_theme_defaults?,
        acc: acc,
        box: box,
        decorations: decorations,
        child_decorations: child_decorations,
        child_timings: child_timings,
        profile_entries: profile_entries,
        root_snapshot_us: root_snapshot_us,
        started_at: started_at
      })
    catch
      {:stopped, state} -> state
      {:crash_state, crash_state} -> crash_state
    end
  end

  defp continue_base_render(state, %{started?: true, cause: cause, attempts: attempts}) do
    render_base(state, cause, attempts)
  end

  defp continue_base_render(
         %{focused: previous_focused} = state,
         %{attempts: attempts, focused: focused, cause: cause}
       )
       when attempts > 0 and focused != previous_focused do
    render_base(%{state | focused: focused}, cause, attempts - 1)
  end

  defp continue_base_render(
         %{
           theme: previous_theme,
           apply_theme_defaults?: previous_apply_theme_defaults?
         } = state,
         %{
           attempts: attempts,
           metadata_theme: metadata_theme,
           metadata_apply_theme_defaults?: metadata_apply_theme_defaults?,
           cause: cause
         }
       )
       when attempts > 0 and
              (metadata_theme != previous_theme or
                 metadata_apply_theme_defaults? != previous_apply_theme_defaults?) do
    state =
      %{
        state
        | theme: metadata_theme,
          apply_theme_defaults?: metadata_apply_theme_defaults?
      }
      |> cascade_live_child_theme_if_changed(
        previous_theme,
        previous_apply_theme_defaults?
      )

    render_base(state, cause, attempts - 1)
  end

  defp continue_base_render(state, result) do
    finish_base_render(state, result)
  end

  defp finish_base_render(state, result) do
    decorations =
      RenderTracking.dedupe_decorations(result.decorations ++ result.child_decorations)

    previous_theme = state.theme
    previous_apply_theme_defaults? = state.apply_theme_defaults?

    state =
      %{
        state
        | focused: result.focused,
          theme: result.metadata_theme,
          apply_theme_defaults?: result.metadata_apply_theme_defaults?
      }
      |> cascade_live_child_theme_if_changed(
        previous_theme,
        previous_apply_theme_defaults?
      )

    prep_started_at = System.monotonic_time(:microsecond)
    {base_output, decorations} = prepare_decorations(result.box.content, decorations, state)
    prepare_decorations_us = System.monotonic_time(:microsecond) - prep_started_at
    render_base_us = System.monotonic_time(:microsecond) - result.started_at

    debug_live_child_us = Debug.debug_live_child_us(result.child_timings)
    app_live_children = Debug.non_debug_child_timings(result.child_timings)

    state
    |> Debug.increment_stat(:render_base_count)
    |> update_frame(base_output: base_output)
    |> update_rendered(elements: viewports_from_acc(result.acc), boxes: result.acc.boxes)
    |> Inspector.merge_render_data(result.acc, safe_root_metadata(state))
    |> update_frame(decorations: decorations)
    |> Map.put(:focused, result.focused)
    |> update_frame(last_render_at: System.monotonic_time(:millisecond))
    |> Debug.put_stat(:last_render_cause, result.cause)
    |> Debug.put_stat(:last_root_snapshot_us, result.root_snapshot_us)
    |> Debug.put_stat(
      :last_root_snapshot_app_us,
      max(result.root_snapshot_us - debug_live_child_us, 0)
    )
    |> Debug.put_stat(:last_live_children_us, Debug.sum_timing_us(result.child_timings))
    |> Debug.put_stat(:last_live_children_app_us, Debug.sum_timing_us(app_live_children))
    |> Debug.put_stat(:last_live_children, Debug.normalize_child_timings(app_live_children))
    |> Debug.put_stat(:last_render_profile, Debug.summarize_profile(result.profile_entries))
    |> Debug.put_stat(:last_reconcile_passes, 0)
    |> Debug.put_stat(:last_reconcile_changed_ids, nil)
    |> Debug.put_stat(:last_prepare_decorations_us, prepare_decorations_us)
    |> Debug.put_stat(:last_render_base_us, render_base_us)
    |> Debug.put_stat(
      :last_render_base_app_us,
      max(render_base_us - debug_live_child_us, 0)
    )
    |> render_frame()
    |> schedule_animation()
  end

  defp maybe_render_base(%{crash: crash} = state, _cause) when not is_nil(crash), do: state

  defp maybe_render_base(%{view_pid: pid} = state, cause) do
    state = prune_dead_children(state)

    if Process.alive?(pid), do: render_base(state, cause), else: state
  end

  defp maybe_render_invalidated_child(state, child_id) do
    case render_invalidated_child(state, child_id) do
      {:ok, state} -> state
      {:crash, state} -> state
      {:error, _reason} -> maybe_render_base(state, :child_invalidated)
      :error -> maybe_render_base(state, :child_invalidated)
    end
  end

  defp safe_render_snapshot(state, tracking_ref, profile_scope) do
    Breeze.ChildServer.render_snapshot(state.view_pid,
      implicit_state: %{},
      terminal: state.terminal,
      theme: state.theme,
      render_tree?: Breeze.Inspector.enabled?(state),
      render_tracking_ref: tracking_ref,
      profile_scope: profile_scope,
      profile_label: inspect(root_view_module(state)),
      compact_snapshot: true,
      live_view: fn attrs, opts ->
        render_live_child(attrs, opts, state, profile_scope, tracking_ref)
      end
    )
    |> then(fn
      {:ok, acc, box, decorations} -> {:ok, acc, box, decorations}
      _ -> :stopped
    end)
  catch
    :exit, _reason -> :stopped
  end

  defp safe_focused_metadata(state) do
    case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
      {:ok,
       %{
         focused: focused,
         theme: theme,
         apply_theme_defaults?: apply_theme_defaults?
       }} ->
        {focused, theme, apply_theme_defaults?}

      {:ok, %{focused: focused, theme: theme}} ->
        {focused, theme, state.apply_theme_defaults?}

      {:ok, %{focused: focused}} ->
        {focused, state.theme, state.apply_theme_defaults?}

      {:crash, _crash} ->
        {nil, state.theme, state.apply_theme_defaults?}

      _ ->
        {nil, state.theme, state.apply_theme_defaults?}
    end
  end

  defp maybe_render_after_input(%{input: %{pending_ref: ref}} = state) when not is_nil(ref),
    do: state

  defp maybe_render_after_input(%{input: %{pending_sync_child_render_id: child_id}} = state)
       when is_binary(child_id) do
    state
    |> update_input(pending_sync_child_render_id: nil, render_after_flush?: false)
    |> maybe_render_invalidated_child(child_id)
  end

  defp maybe_render_after_input(%{input: %{render_after_flush?: true}} = state) do
    state
    |> update_input(render_after_flush?: false)
    |> maybe_render_base(:input_flush)
  end

  defp maybe_render_after_input(state), do: update_input(state, render_after_flush?: false)

  defp force_full_redraw(state, cause) do
    state
    |> update_frame(last_payload: nil, last_lines: nil, last_overlays: [])
    |> maybe_render_base(cause)
  end

  defp resize_terminal(state) do
    state.terminal
    |> Termite.Terminal.resize()
    |> apply_terminal_size_override(state.terminal_size_override)
  end

  defp apply_terminal_size_override(%Termite.Terminal{} = terminal, fun)
       when is_function(fun, 1) do
    %{terminal | size: fun.(terminal.size)}
  end

  defp apply_terminal_size_override(%Termite.Terminal{} = terminal, _fun), do: terminal

  defp render_live_child(attrs, opts, state, profile_scope, tracking_ref) do
    ctx = live_child_context(attrs, opts, state)
    RenderTracking.track_seen_live_child(tracking_ref, {ctx.full_id, ctx.attrs})

    case Map.get(state.children, ctx.full_id) do
      nil ->
        missing_live_child(ctx, tracking_ref)

      child ->
        render_live_child_instance(child, ctx, state, profile_scope, tracking_ref)
    end
  end

  defp live_child_context(attrs, opts, state) do
    id = fetch_live_attr!(attrs, :id)
    full_id = live_id(Keyword.get(opts, :live_prefix), id)
    expected_view = fetch_live_attr!(attrs, :view)
    viewport = Keyword.get(opts, :live_viewport)

    %{
      id: id,
      full_id: full_id,
      attrs: attrs,
      preload_only?: fetch_live_attr(attrs, :preload_only, false),
      expected_view: expected_view,
      expected_start_opts:
        child_start_opts(fetch_live_attr(attrs, :start_opts, []), expected_view, state),
      expected_assigns: fetch_live_attr(attrs, :assigns, %{}) |> Map.new(),
      terminal: Keyword.get(opts, :live_terminal, state.terminal),
      viewport: viewport,
      decoration_viewport:
        accumulate_live_viewport(
          viewport,
          Keyword.get(opts, :live_decoration_parent_viewport)
        )
    }
  end

  defp render_live_child_instance(child, ctx, state, profile_scope, tracking_ref) do
    cond do
      stale_live_child?(child, ctx) ->
        missing_live_child(ctx, tracking_ref)

      ctx.preload_only? ->
        :preloaded

      true ->
        render_current_live_child(child, ctx, state, profile_scope, tracking_ref)
    end
  end

  defp stale_live_child?(%{pid: pid}, _ctx) when not is_pid(pid), do: true

  defp stale_live_child?(child, ctx) do
    not Process.alive?(child.pid) or child.view != ctx.expected_view or
      child.start_opts != ctx.expected_start_opts or child.assigns != ctx.expected_assigns
  end

  defp missing_live_child(ctx, tracking_ref) do
    RenderTracking.track_missing_live_child(tracking_ref, {ctx.full_id, ctx.attrs})
    if ctx.preload_only?, do: :preloaded, else: :missing
  end

  defp render_current_live_child(child, ctx, state, profile_scope, tracking_ref) do
    child_started_at = System.monotonic_time(:microsecond)

    case safe_call(fn ->
           Breeze.ChildServer.render_snapshot(child.pid,
             focused: strip_live_prefix(state.focused, ctx.full_id),
             implicit_state: %{},
             terminal: ctx.terminal,
             theme: state.theme,
             live_prefix: ctx.full_id,
             render_tree?: Breeze.Inspector.enabled?(state),
             render_tracking_ref: tracking_ref,
             profile_scope: profile_scope,
             profile_label: "#{ctx.full_id} #{inspect(child.view)}",
             live_view: fn child_attrs, child_opts ->
               child_opts =
                 Keyword.put(
                   child_opts,
                   :live_decoration_parent_viewport,
                   ctx.decoration_viewport
                 )

               render_live_child(
                 child_attrs,
                 child_opts,
                 state,
                 profile_scope,
                 tracking_ref
               )
             end
           )
         end) do
      {:ok, {:ok, child_acc, child_box, child_decorations}} ->
        finish_live_child_render(
          child,
          ctx,
          tracking_ref,
          child_started_at,
          child_acc,
          child_box,
          child_decorations
        )

      {:crash, %{reason: {:noproc, _}}} ->
        missing_live_child(ctx, tracking_ref)

      {:crash, crash} ->
        throw({:crash_state, enter_crash_state(state, crash)})
    end
  end

  defp finish_live_child_render(
         child,
         ctx,
         tracking_ref,
         child_started_at,
         child_acc,
         child_box,
         child_decorations
       ) do
    RenderTracking.track_child_timing(tracking_ref, %{
      id: ctx.full_id,
      view: child.view,
      us: System.monotonic_time(:microsecond) - child_started_at
    })

    Enum.each(child_decorations, fn decoration ->
      RenderTracking.track_decoration(
        tracking_ref,
        namespace_decoration(decoration, ctx.full_id, ctx.decoration_viewport)
      )
    end)

    child_dimensions =
      case safe_call(fn -> Breeze.ChildServer.layout_snapshot(child.pid) end) do
        {:ok, snapshot} ->
          Dimensions.translate_live(snapshot.elements, ctx.viewport, ctx.full_id, child_box)

        _ ->
          %{}
      end

    {:rendered, ctx.id, child_acc, child_box, child_dimensions}
  end

  defp render_invalidated_child(state, child_id) do
    try do
      with {:ok, ctx} <- invalidated_child_context(state, child_id),
           {:ok, ctx} <- render_invalidated_child_snapshot(ctx),
           :ok <- validate_child_patch_render(ctx) do
        {:ok, write_invalidated_child_patch(ctx)}
      end
    catch
      {:crash_state, crash_state} -> {:crash, crash_state}
    end
  end

  defp render_live_snapshot(state, child_id, opts) do
    result =
      try do
        with {:ok, ctx} <- invalidated_child_context(state, child_id),
             {:ok, ctx} <- render_invalidated_child_snapshot(ctx) do
          {:ok, live_snapshot_from_context(ctx, opts)}
        end
      catch
        {:crash_state, crash_state} -> {:crash, crash_state}
      end

    case result do
      {:crash, crash_state} -> {{:crash, crash_state.crash}, crash_state}
      reply -> {reply, state}
    end
  end

  defp live_snapshot_from_context(ctx, _opts) do
    child_box = ctx.child_box

    %{
      id: ctx.child_id,
      content: child_box.content || "",
      width: child_box.width || ctx.viewport.width,
      height: child_box.height || ctx.viewport.height
    }
  end

  defp dispatch_live_child_input(state, child_id, input, opts) do
    with true <- patchable_live_child?(child_id),
         %{pid: pid} when is_pid(pid) <- Map.get(state.children, child_id),
         true <- Process.alive?(pid) do
      case safe_call(fn -> Breeze.ChildServer.dispatch_input(pid, input, opts) end) do
        {:ok, reply} ->
          reply = namespace_child_reply(reply, child_id)
          {reply, apply_live_input_reply(state, child_id, reply)}

        {:crash, crash} ->
          {{:crash, crash}, enter_crash_state(state, crash)}
      end
    else
      false -> {{:error, :not_patchable}, state}
      nil -> {{:error, :missing_child}, state}
      _other -> {{:error, :missing_child}, state}
    end
  end

  defp apply_live_input_reply(state, child_id, {:noreply, focused, true}) do
    state
    |> Map.put(:focused, focused)
    |> maybe_render_invalidated_child(child_id)
  end

  defp apply_live_input_reply(state, _child_id, {:noreply, focused, _render?}) do
    %{state | focused: focused}
  end

  defp apply_live_input_reply(state, _child_id, {:stop, focused}) do
    %{state | focused: focused}
  end

  defp apply_live_input_reply(state, _child_id, {:stop, focused, _consumed}) do
    %{state | focused: focused}
  end

  defp apply_live_input_reply(state, _child_id, _reply), do: state

  defp invalidated_child_context(state, child_id) do
    with true <- patchable_live_child?(child_id),
         %{view: view} = child <- Map.get(state.children, child_id),
         %Breeze.Viewport{} = viewport <- Map.get(state.rendered.elements, child_id) do
      terminal = Dimensions.live_child_terminal(state.terminal, viewport)
      profile_scope = make_ref()
      Breeze.DebugProfiler.reset(profile_scope)

      {:ok,
       %{
         state: state,
         child_id: child_id,
         child: child,
         view: view,
         viewport: viewport,
         terminal: terminal,
         tracking_ref: RenderTracking.begin(state.rendered.tracking_table),
         profile_scope: profile_scope,
         started_at: System.monotonic_time(:microsecond)
       }}
    else
      false -> {:error, :not_patchable}
      nil -> {:error, :missing_child}
      _ -> {:error, :missing_viewport}
    end
  end

  defp render_invalidated_child_snapshot(ctx) do
    case safe_call(fn ->
           Breeze.ChildServer.render_snapshot(ctx.child.pid,
             focused: strip_live_prefix(ctx.state.focused, ctx.child_id),
             implicit_state: %{},
             terminal: ctx.terminal,
             theme: ctx.state.theme,
             live_prefix: ctx.child_id,
             render_tree?: Breeze.Inspector.enabled?(ctx.state),
             render_tracking_ref: ctx.tracking_ref,
             profile_scope: ctx.profile_scope,
             profile_label: "#{ctx.child_id} #{inspect(ctx.view)}",
             live_view: fn child_attrs, child_opts ->
               render_live_child(
                 child_attrs,
                 child_opts,
                 ctx.state,
                 ctx.profile_scope,
                 ctx.tracking_ref
               )
             end
           )
         end) do
      {:ok, {:ok, _child_acc, child_box, child_decorations}} ->
        tracking = RenderTracking.finish(ctx.tracking_ref)

        {:ok,
         ctx
         |> Map.put(:child_box, child_box)
         |> Map.put(:child_decorations, child_decorations)
         |> Map.put(:tracking, tracking)
         |> Map.put(:child_render_us, System.monotonic_time(:microsecond) - ctx.started_at)}

      {:crash, crash} ->
        throw({:crash_state, enter_crash_state(ctx.state, crash)})
    end
  end

  defp validate_child_patch_render(%{tracking: %{missing: missing}}) when missing != [] do
    {:error, {:missing_live_children, missing}}
  end

  defp validate_child_patch_render(%{
         child_decorations: child_decorations,
         tracking: %{decorations: tracked_decorations}
       })
       when child_decorations != [] or tracked_decorations != [] do
    {:error, {:decorations_present, %{child: child_decorations, tracked: tracked_decorations}}}
  end

  defp validate_child_patch_render(_ctx), do: :ok

  defp write_invalidated_child_patch(ctx) do
    fragment = invalidated_child_fragment(ctx)
    composed_at = System.monotonic_time(:microsecond)
    payload = Frame.child_patch_payload(fragment, ctx.viewport)
    terminal = Termite.Terminal.write(ctx.state.terminal, payload)
    written_at = System.monotonic_time(:microsecond)

    ctx.state
    |> Map.put(:terminal, terminal)
    |> update_frame(
      last_payload: nil,
      last_lines: Frame.invalidate_patched_rows(ctx.state.frame.last_lines, ctx.viewport)
    )
    |> Debug.put_child_patch_stats(ctx, fragment, composed_at, written_at)
  end

  defp invalidated_child_fragment(ctx) do
    ctx.child_box
    |> wrap_child_fragment(
      ctx.viewport,
      live_placeholder_style(ctx.child, ctx.state, ctx.terminal)
    )
    |> BackBreeze.Box.render(terminal: ctx.terminal)
    |> Map.fetch!(:content)
  end

  defp render_frame(state) do
    started_at = System.monotonic_time(:microsecond)

    {output, decorations} =
      apply_decorations(state.frame.base_output, state.frame.decorations, state)

    overlays = terminal_overlays(decorations, state)

    lines =
      output
      |> Frame.normalize_lines(state.terminal.size.height)

    frame_payload =
      Frame.build_payload(
        state.frame.last_lines,
        lines,
        state.frame.last_overlays || [],
        overlays,
        state.terminal.size.width
      )

    composed_at = System.monotonic_time(:microsecond)

    {terminal, write_duration} =
      if frame_payload == state.frame.last_payload do
        {state.terminal, 0}
      else
        terminal = Termite.Terminal.write(state.terminal, frame_payload)
        written_at = System.monotonic_time(:microsecond)
        {terminal, written_at - composed_at}
      end

    state
    |> Map.put(:terminal, terminal)
    |> update_frame(
      decorations: decorations,
      last_payload: frame_payload,
      last_lines: lines,
      last_overlays: overlays
    )
    |> Debug.put_stat(:last_frame_compose_us, composed_at - started_at)
    |> Debug.put_stat(:last_terminal_write_us, write_duration)
    |> Debug.put_stat(:last_frame_us, System.monotonic_time(:microsecond) - started_at)
    |> Debug.put_stat(:last_frame_bytes, byte_size(frame_payload))
    |> Debug.put_stat(:overlay_count, length(overlays))
    |> Inspector.push_snapshot_now()
  end

  defp initialize_decorations(decorations) do
    Enum.map(decorations, fn decoration ->
      decoration
      |> Map.put_new(:frame_index, 0)
      |> Map.put_new(:every_ms, 500)
    end)
  end

  defp prepare_decorations(output, decorations, state) do
    decorations
    |> initialize_decorations()
    |> Enum.reduce({output, []}, fn decoration, {acc, updated} ->
      {_animated_box, current_content, current_overlays} = render_decoration(decoration, state)

      {
        String.replace(
          acc,
          rendered_fragment(decoration.box, state, decoration[:layout]),
          current_content,
          global: false
        ),
        [
          decoration
          |> Map.put(:current_content, current_content)
          |> Map.put(:current_overlays, current_overlays)
          | updated
        ]
      }
    end)
    |> then(fn {prepared_output, updated} -> {prepared_output, Enum.reverse(updated)} end)
  end

  defp advance_decorations(state) do
    decorations =
      Enum.map(state.frame.decorations, fn decoration ->
        if decoration_active?(decoration, state) do
          Map.update(decoration, :frame_index, 1, &(&1 + 1))
        else
          decoration
        end
      end)

    update_frame(state, decorations: decorations)
  end

  defp apply_decorations(output, decorations, state) do
    Enum.reduce(decorations, {output, []}, fn decoration, {acc, updated} ->
      if decoration_active?(decoration, state) do
        {_animated_box, current_content, current_overlays} = render_decoration(decoration, state)

        {
          String.replace(acc, decoration.current_content, current_content, global: false),
          [
            decoration
            |> Map.put(:current_content, current_content)
            |> Map.put(:current_overlays, current_overlays)
            | updated
          ]
        }
      else
        {acc, [decoration | updated]}
      end
    end)
    |> then(fn {final_output, updated} -> {final_output, Enum.reverse(updated)} end)
  end

  defp render_decoration(decoration, state) do
    now = System.monotonic_time(:millisecond)

    ctx = decoration_ctx(decoration, state, now)

    {animated_box, animate_opts} =
      if function_exported?(decoration.mod, :animate, 5) do
        decoration.mod
        |> apply(:animate, [:root, decoration.box, decoration.flags, decoration.state, ctx])
        |> normalize_animation_result()
      else
        {decoration.box, %{}}
      end

    {animated_box, rendered_fragment(animated_box, state, decoration[:layout]),
     Map.get(animate_opts, :overlays, [])}
  end

  defp decoration_ctx(decoration, state, now) do
    %{
      phase: :async,
      frame: decoration.frame_index,
      now: now,
      pending?: pending_active?(state),
      focused?: (decoration[:owner_id] || decoration.id) == state.focused,
      last_render_at: state.frame.last_render_at,
      last_interaction_at: state.input.last_interaction_at,
      theme: state.theme,
      id: decoration.id,
      layout: decoration[:layout]
    }
  end

  defp rendered_fragment(box, state, layout) do
    terminal = render_fragment_terminal(state.terminal, layout)

    box
    |> BackBreeze.Box.render(terminal: terminal)
    |> Map.get(:content)
  end

  defp render_fragment_terminal(%Termite.Terminal{} = terminal, %{width: width, height: height})
       when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    %{terminal | size: %{width: width, height: height}}
  end

  defp render_fragment_terminal(terminal, _layout), do: terminal

  defp schedule_animation(%{frame: %{decorations: []}} = state), do: state

  defp schedule_animation(state) do
    case next_tick_delay(state) do
      nil ->
        update_frame(state, next_tick_at: nil)

      delay ->
        schedule_animation_tick(state, delay)
    end
  end

  defp schedule_animation_tick(state, delay) do
    next_tick_at = System.monotonic_time(:millisecond) + delay

    case state.frame do
      %{animation_timer: timer, next_tick_at: current_tick_at}
      when is_reference(timer) and is_integer(current_tick_at) and current_tick_at <= next_tick_at ->
        state

      %{animation_timer: timer} when is_reference(timer) ->
        Process.cancel_timer(timer)
        put_animation_timer(state, next_tick_at, delay)

      _ ->
        put_animation_timer(state, next_tick_at, delay)
    end
  end

  defp put_animation_timer(state, next_tick_at, delay) do
    timer = Process.send_after(self(), :animation_tick, delay)

    %{
      state
      | frame: %{
          state.frame
          | animation_timer: timer,
            next_tick_at: next_tick_at
        }
    }
  end

  defp next_tick_delay(state) do
    state.frame.decorations
    |> Enum.map(&decoration_delay(&1, state))
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp accumulate_live_viewport(
         %{left: left, top: top} = viewport,
         %{left: parent_left, top: parent_top}
       ) do
    %{viewport | left: left + parent_left, top: top + parent_top}
  end

  defp accumulate_live_viewport(viewport, _parent_viewport), do: viewport

  defp namespace_decoration(decoration, full_id, viewport) do
    decoration
    |> Map.update(:id, nil, &namespace_live_id(&1, full_id))
    |> Map.update(:owner_id, full_id, &namespace_live_id(&1, full_id))
    |> Map.update(:layout, nil, &translate_decoration_layout(&1, viewport))
  end

  defp translate_decoration_layout(%Breeze.Viewport{} = layout, %{left: left, top: top}) do
    %{layout | left: layout.left + left, top: layout.top + top}
  end

  defp translate_decoration_layout(layout, _viewport), do: layout

  defp namespace_live_id(nil, _full_id), do: nil
  defp namespace_live_id(id, full_id), do: full_id <> "::" <> id

  defp decoration_active?(decoration, state) do
    cond do
      decoration[:active_when_pending] ->
        pending_active?(state)

      decoration[:active_when_focused] ->
        (decoration[:owner_id] || decoration[:id]) == state.focused

      true ->
        true
    end
  end

  defp pending_active?(%{input: %{pending_ref: nil}}), do: false

  defp pending_active?(%{
         input: %{pending_started_at: started_at},
         debug: %{busy_delay_ms: delay}
       })
       when is_integer(started_at) do
    System.monotonic_time(:millisecond) - started_at >= delay
  end

  defp pending_active?(_state), do: false

  defp decoration_delay(decoration, state) do
    cond do
      decoration[:active_when_pending] && is_nil(state.input.pending_ref) ->
        nil

      decoration[:active_when_pending] && pending_active?(state) ->
        Map.get(decoration, :every_ms, state.debug.frame_delay_ms)

      decoration[:active_when_pending] ->
        remaining_busy_delay(state)

      decoration_active?(decoration, state) ->
        Map.get(decoration, :every_ms, state.debug.frame_delay_ms)

      true ->
        nil
    end
  end

  defp remaining_busy_delay(%{
         input: %{pending_started_at: started_at},
         debug: %{busy_delay_ms: delay}
       })
       when is_integer(started_at) do
    max(delay - (System.monotonic_time(:millisecond) - started_at), 0)
  end

  defp remaining_busy_delay(_state), do: nil

  defp terminal_overlays(decorations, state) do
    decoration_overlays =
      decorations
      |> Enum.filter(&decoration_active?(&1, state))
      |> Enum.flat_map(&Map.get(&1, :current_overlays, []))
      |> Enum.reject(&is_nil/1)

    decoration_overlays ++ Breeze.Inspector.overlays(state)
  end

  defp normalize_animation_result({:ok, %BackBreeze.Box{} = box, opts}) when is_list(opts) do
    {box, Map.new(opts)}
  end

  defp normalize_animation_result({:ok, %BackBreeze.Box{} = box}) do
    {box, %{}}
  end

  defp normalize_animation_result(%BackBreeze.Box{} = box) do
    {box, %{}}
  end

  defp viewports_from_acc(acc) do
    acc
    |> Breeze.RenderState.build_dimensions()
    |> Map.merge(Map.get(acc, :live_dimensions, %{}))
    |> Map.new(fn {id, dims} -> {id, Breeze.Viewport.from_dimensions(dims)} end)
  end

  defp patchable_live_child?(child_id) when is_binary(child_id), do: true
  defp patchable_live_child?(_child_id), do: false

  defp debug_child_id?("debug"), do: true
  defp debug_child_id?(_child_id), do: false

  defp wrap_child_fragment(child_box, viewport, fill_style) do
    fill_style = fill_style || %{}
    child_box = disable_rendered_child_cache(child_box)

    BackBreeze.Box.new(
      style:
        Map.merge(fill_style, %{
          width: viewport.width,
          height: viewport.height,
          overflow: :hidden
        }),
      children: [child_box]
    )
  end

  defp disable_rendered_child_cache(%BackBreeze.Box{state: :rendered} = box) do
    # BackBreeze's cache key for an already-rendered box does not include its
    # layer map. Mark this snapshot as volatile so overlays cannot reuse the
    # previous child patch while leaving its materialized content unchanged.
    cache_marker =
      BackBreeze.Box.new(content: %{BackBreeze.VirtualText.new("") | cache?: false})

    %{box | children: [cache_marker | box.children]}
  end

  defp disable_rendered_child_cache(box), do: box

  defp live_placeholder_style(%{attrs: attrs}, state, terminal)
       when is_list(attrs) or is_map(attrs) do
    style_state =
      Breeze.Style.empty()
      |> Breeze.Style.put_class(fetch_live_attr(attrs, :class, nil))
      |> Breeze.Style.put_style(fetch_live_attr(attrs, :style, nil))

    element =
      Breeze.Style.to_element(style_state,
        theme: state.theme,
        terminal: terminal,
        apply_theme_defaults: state.apply_theme_defaults?
      )

    element.style
    |> Map.take([:background_color, :foreground_color, :bold, :italic, :reverse])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp live_placeholder_style(_child, _state, _terminal), do: %{}

  defp stop(state) do
    shutdown_root_view(state.child_view_supervisor, state.view_pid)

    terminal =
      state.terminal
      |> Termite.Screen.disable_mouse()
      |> Termite.Screen.clear_screen()
      |> Termite.Screen.show_cursor()
      |> maybe_exit_alt_screen(state.alt_screen_active?)

    terminal = Termite.Terminal.write(terminal, "\r")
    {:stop, :normal, %{state | terminal: terminal}}
  end

  @impl true
  def terminate(_reason, state) do
    shutdown_view_processes(state)

    if state.logger_collector do
      _ = Breeze.Logger.Collector.release(self())
    end

    if state.owns_child_view_supervisor?,
      do: Breeze.ChildViewSupervisor.stop(state.child_view_supervisor)

    Breeze.RemoteInspector.Supervisor.stop(state.remote_inspector_supervisor)

    :ok
  end

  defp maybe_exit_alt_screen(terminal, true), do: Termite.Screen.exit_alt_screen(terminal)
  defp maybe_exit_alt_screen(terminal, _active?), do: terminal

  defp safe_apply_input_reply(state, fun) do
    case safe_call(fn -> fun.(state) end) do
      {:ok, {:crash, crash}} -> {:noreply, enter_crash_state(state, crash)}
      {:ok, reply} -> apply_input_reply(state, reply)
      {:crash, crash} -> {:noreply, enter_crash_state(state, crash)}
    end
  end

  defp safe_apply_tab_input_reply(state, fun) do
    previous_focused = state.focused

    case safe_call(fn -> fun.(state) end) do
      {:ok, {:crash, crash}} ->
        {:noreply, enter_crash_state(state, crash)}

      {:ok, reply} ->
        apply_tab_input_reply(state, previous_focused, reply)

      {:crash, crash} ->
        {:noreply, enter_crash_state(state, crash)}
    end
  end

  defp safe_apply_hierarchy_input_reply(state, fun) do
    case safe_call(fn -> fun.(state) end) do
      {:ok, {:crash, crash}} -> {:noreply, enter_crash_state(state, crash)}
      {:ok, reply} -> apply_hierarchy_input_reply(state, reply)
      {:crash, crash} -> {:noreply, enter_crash_state(state, crash)}
    end
  end

  defp apply_tab_input_reply(state, previous_focused, reply) do
    case apply_input_reply(state, reply) do
      {:noreply, next_state} ->
        {:noreply, maybe_schedule_sync_child_render(next_state, previous_focused, reply)}

      other ->
        other
    end
  end

  defp maybe_schedule_sync_child_render(state, previous_focused, {:noreply, focused, true}),
    do: put_sync_child_render_id(state, previous_focused, focused)

  defp maybe_schedule_sync_child_render(state, _previous_focused, _reply), do: state

  defp put_sync_child_render_id(state, previous_focused, focused) do
    case live_child_id_for_focus(state, focused) ||
           live_child_id_for_focus(state, previous_focused) do
      nil -> state
      child_id -> update_input(state, pending_sync_child_render_id: child_id)
    end
  end

  defp live_child_id_for_focus(%{children: children}, focused) when is_binary(focused) do
    children
    |> Map.keys()
    |> Enum.filter(fn child_id ->
      focused == child_id or String.starts_with?(focused, child_id <> "::")
    end)
    |> Enum.max_by(&String.length/1, fn -> nil end)
  end

  defp live_child_id_for_focus(_state, _focused), do: nil

  defp safe_call(fun) when is_function(fun, 0) do
    try do
      {:ok, fun.()}
    rescue
      exception ->
        {:crash, crash_info(:error, exception, __STACKTRACE__)}
    catch
      :exit, reason ->
        {:crash, crash_info(:exit, reason, __STACKTRACE__)}

      kind, reason ->
        {:crash, crash_info(kind, reason, __STACKTRACE__)}
    end
  end

  defp crash_info(kind, reason, stacktrace) do
    {kind, reason, stacktrace} = normalize_crash_info(kind, reason, stacktrace)

    %{
      kind: kind,
      reason: reason,
      stacktrace: stacktrace,
      selected_index: nil,
      focused: "error-stacktrace",
      implicit_state: %{}
    }
  end

  defp normalize_crash_info(:exit, {{%_exception{} = exception, stacktrace}, _call}, _stacktrace)
       when is_list(stacktrace) do
    {:error, exception, stacktrace}
  end

  defp normalize_crash_info(:exit, {%_exception{} = exception, stacktrace}, _stacktrace)
       when is_list(stacktrace) do
    {:error, exception, stacktrace}
  end

  defp normalize_crash_info(:exit, {{{kind, reason, stacktrace}, _location}, _call}, _stacktrace)
       when is_list(stacktrace) do
    {kind, reason, stacktrace}
  end

  defp normalize_crash_info(:exit, {kind, reason, stacktrace}, _stacktrace)
       when is_list(stacktrace) do
    {kind, reason, stacktrace}
  end

  defp normalize_crash_info(kind, reason, stacktrace), do: {kind, reason, stacktrace}

  defp enter_crash_state(state, crash) do
    cancel_timer(state.frame.animation_timer)
    terminal = apply_mouse_mode(state.terminal, false)
    crash = Error.prepare_crash(state.render_errors, state.view, crash, terminal.size)

    state
    |> Map.put(:terminal, terminal)
    |> Map.put(:crash, crash)
    |> update_input(
      pending_ref: nil,
      pending_started_at: nil,
      flush_scheduled?: false,
      queued_input: :queue.new()
    )
    |> update_frame(animation_timer: nil, next_tick_at: nil, decorations: [])
    |> Debug.put_stat(:last_render_cause, :crash)
    |> render_crash(force_full_redraw?: true)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(timer), do: Process.cancel_timer(timer)

  defp render_crash(state, opts \\ []) do
    crash = Error.prepare_crash(state.render_errors, state.view, state.crash, state.terminal.size)

    content =
      Error.render_assigns(state.render_errors, state.view, crash, state.terminal.size)
      |> then(
        &Breeze.Renderer.render_to_string(Error.view(state.render_errors), &1,
          terminal: state.terminal,
          focused: crash.focused,
          implicit_state: crash.implicit_state
        )
      )

    state = Map.put(state, :crash, crash)

    frame_opts =
      if Keyword.get(opts, :force_full_redraw?, false) do
        [base_output: content, last_payload: nil, last_lines: nil, last_overlays: []]
      else
        [base_output: content]
      end

    state
    |> update_frame(frame_opts)
    |> render_frame()
  end

  defp handle_crash_input(input, %{crash: crash} = state) do
    case Error.handle_input(state.render_errors, state.view, crash, input, state.terminal.size) do
      :ignore ->
        {:noreply, state}

      :restart ->
        {:noreply, restart_root(state, :restart)}

      :stop ->
        {:stop, state}

      {:copy_details, crash} ->
        copy_or_print_crash_details(state, crash)

      {:update, updated_crash} ->
        {:noreply, state |> Map.put(:crash, updated_crash) |> render_crash()}
    end
  end

  defp copy_or_print_crash_details(state, crash) do
    details = Error.details_text(state.render_errors, state.view, crash)

    case Breeze.ErrorView.Clipboard.copy(details, state.clipboard_opts || []) do
      {:ok, command} ->
        {:noreply,
         show_temporary_crash_notice(state, crash, "Copied crash details to #{command}.")}

      {:error, :unavailable} ->
        print_crash_details_to_scrollback(state, details)

      {:error, reason} ->
        details = details <> "\n\nClipboard copy failed: #{inspect(reason)}"
        print_crash_details_to_scrollback(state, details)
    end
  end

  defp show_temporary_crash_notice(state, crash, notice) do
    ref = make_ref()
    Process.send_after(self(), {:clear_crash_notice, ref}, 1_000)

    crash =
      crash
      |> Map.put(:notice, notice)
      |> Map.put(:notice_ref, ref)

    state
    |> Map.put(:crash, crash)
    |> render_crash()
  end

  defp print_crash_details_to_scrollback(state, details) do
    terminal =
      state.terminal
      |> Termite.Screen.disable_mouse()
      |> Termite.Screen.show_cursor()
      |> maybe_exit_alt_screen(state.alt_screen_active?)
      |> Termite.Terminal.write("\r\n" <> details <> "\r\n\nPress q to quit, r to restart.\r\n")

    {:noreply, %{state | terminal: terminal, alt_screen_active?: false, crash_scrollback?: true}}
  end

  defp restore_terminal_after_crash_scrollback(%{crash_scrollback?: true} = state) do
    terminal =
      state.terminal
      |> maybe_enter_alt_screen(state.alt_screen?, state.alt_screen_active?)
      |> maybe_hide_cursor(state.hide_cursor?)
      |> Termite.Screen.clear_screen()

    state
    |> Map.put(:terminal, terminal)
    |> Map.put(:alt_screen_active?, state.alt_screen?)
    |> update_frame(last_payload: nil, last_lines: nil, last_overlays: [])
  end

  defp restore_terminal_after_crash_scrollback(state), do: state

  defp maybe_enter_alt_screen(terminal, true, false), do: Termite.Screen.alt_screen(terminal)
  defp maybe_enter_alt_screen(terminal, _configured?, _active?), do: terminal

  defp maybe_hide_cursor(terminal, true), do: Termite.Screen.hide_cursor(terminal)
  defp maybe_hide_cursor(terminal, _), do: terminal

  defp reload_after_code_change(state) do
    state = prune_dead_children(state)

    case refresh_reload_state(state) do
      {:ok, state} ->
        maybe_render_base(state, :reload)

      {:restart, state} ->
        restart_root(state, :reload)

      {:error, crash} ->
        enter_crash_state(state, crash)
    end
  end

  defp restart_root(state, cause) do
    state =
      state
      |> restore_terminal_after_crash_scrollback()
      |> then(&%{&1 | terminal: apply_mouse_mode(&1.terminal, &1.mouse_mode)})

    shutdown_view_processes(state)

    case start_root_view(state) do
      {:ok, pid, focused, theme} ->
        state
        |> Map.put(:view_pid, pid)
        |> Map.put(:focused, focused)
        |> Map.put(:theme, theme)
        |> Map.put(:crash, nil)
        |> Map.put(:crash_scrollback?, false)
        |> Map.put(:children, %{})
        |> update_frame(
          decorations: [],
          base_output: "",
          last_payload: nil,
          last_lines: nil,
          last_overlays: []
        )
        |> update_input(
          pending_ref: nil,
          pending_started_at: nil,
          queued_input: :queue.new(),
          flush_scheduled?: false
        )
        |> maybe_render_base(cause)

      {:error, crash} ->
        enter_crash_state(state, crash)
    end
  end

  defp apply_mouse_mode(terminal, false), do: Termite.Screen.disable_mouse(terminal)
  defp apply_mouse_mode(terminal, nil), do: Termite.Screen.disable_mouse(terminal)
  defp apply_mouse_mode(terminal, true), do: Termite.Screen.enable_mouse(terminal)

  defp apply_mouse_mode(terminal, opts) when is_list(opts),
    do: Termite.Screen.enable_mouse(terminal, opts)

  defp start_root_view(state) do
    session = self()

    case safe_call(fn ->
           Breeze.ChildViewSupervisor.start_child(
             state.child_view_supervisor,
             view: state.view,
             start_opts: state.start_opts || [],
             terminal: state.terminal,
             theme: state.theme,
             process_flags: state.child_process_flags || [],
             server: self(),
             render_tree?: Breeze.Inspector.enabled?(state),
             global_keybindings: state.input.global_keybindings || [],
             invalidate: fn -> send(session, :child_invalidated) end
           )
         end) do
      {:ok, {:ok, pid}} ->
        Process.monitor(pid)

        {focused, theme} =
          case safe_call(fn -> Breeze.ChildServer.metadata(pid) end) do
            {:ok, %{focused: focused, theme: child_theme}} -> {focused, child_theme}
            {:ok, %{focused: focused}} -> {focused, state.theme}
            _ -> {nil, state.theme}
          end

        {:ok, pid, focused, theme}

      {:ok, other} ->
        {:error,
         crash_info(
           :error,
           RuntimeError.exception("unexpected child start result: #{inspect(other)}"),
           []
         )}

      {:crash, crash} ->
        {:error, crash}
    end
  end

  defp shutdown_root_view(_supervisor, nil), do: :ok

  defp shutdown_root_view(supervisor, pid) do
    shutdown_view_process(supervisor, pid)
  end

  defp shutdown_view_processes(state) do
    state.children
    |> Map.values()
    |> Enum.map(&Map.get(&1, :pid))
    |> then(&[state.view_pid | &1])
    |> Enum.uniq()
    |> Enum.each(&shutdown_view_process(state.child_view_supervisor, &1))
  end

  defp shutdown_view_process(supervisor, pid) when is_pid(pid),
    do: Breeze.ChildViewSupervisor.terminate_child(supervisor, pid)

  defp shutdown_view_process(_supervisor, _pid), do: :ok

  defp refresh_reload_state(state) do
    case Keyword.get(state.reload_opts || [], :refresh_server_opts) do
      nil ->
        {:ok, state}

      refresh ->
        context = %{metadata: safe_root_metadata(state)}

        with {:ok, refreshed_opts} <- call_refresh_server_opts(refresh, context),
             {:ok, state} <- apply_refreshed_server_opts(state, refreshed_opts) do
          {:ok, state}
        else
          {:restart, state} -> {:restart, state}
          {:error, crash} -> {:error, crash}
        end
    end
  end

  defp call_refresh_server_opts({module, function, args}, context)
       when is_atom(module) and is_atom(function) and is_list(args) do
    callback_args =
      if function_exported?(module, function, length(args) + 1) do
        args ++ [context]
      else
        args
      end

    case safe_call(fn -> apply(module, function, callback_args) end) do
      {:ok, opts} when is_list(opts) ->
        {:ok, opts}

      {:ok, other} ->
        {:error,
         crash_info(
           :error,
           RuntimeError.exception(
             "refresh_server_opts must return a keyword list, got: #{inspect(other)}"
           ),
           []
         )}

      {:crash, crash} ->
        {:error, crash}
    end
  end

  defp apply_refreshed_server_opts(state, refreshed_opts) do
    refreshed_view = Keyword.get(refreshed_opts, :view, state.view)
    refreshed_start_opts = Keyword.get(refreshed_opts, :start_opts, state.start_opts)
    current_global_keybindings = state.input.global_keybindings

    if refreshed_view != state.view or refreshed_start_opts != state.start_opts do
      {:restart,
       state
       |> Map.put(:view, refreshed_view)
       |> Map.put(:start_opts, refreshed_start_opts)
       |> Map.put(:mouse_mode, Keyword.get(refreshed_opts, :mouse, state.mouse_mode))
       |> update_input(
         global_keybindings:
           Keyword.get(refreshed_opts, :global_keybindings, current_global_keybindings)
       )}
    else
      global_keybindings =
        Keyword.get(refreshed_opts, :global_keybindings, current_global_keybindings)

      mouse_mode = Keyword.get(refreshed_opts, :mouse, state.mouse_mode)

      terminal =
        if mouse_mode == state.mouse_mode,
          do: state.terminal,
          else: apply_mouse_mode(state.terminal, mouse_mode)

      case update_live_global_keybindings(state, global_keybindings) do
        :ok ->
          {:ok,
           state
           |> update_input(global_keybindings: global_keybindings)
           |> Map.put(:mouse_mode, mouse_mode)
           |> Map.put(:terminal, terminal)}

        {:error, crash} ->
          {:error, crash}
      end
    end
  end

  defp update_live_global_keybindings(state, global_keybindings) do
    if is_pid(state.view_pid) and Process.alive?(state.view_pid) do
      case safe_call(fn ->
             Breeze.ChildServer.put_global_keybindings(state.view_pid, global_keybindings)
           end) do
        {:ok, :ok} ->
          :ok

        {:ok, other} ->
          {:error,
           crash_info(
             :error,
             RuntimeError.exception("unexpected child update result: #{inspect(other)}"),
             []
           )}

        {:crash, crash} ->
          {:error, crash}
      end
    else
      :ok
    end
  end

  defp cascade_live_child_theme_if_changed(
         %{theme: theme} = state,
         previous_theme,
         previous_apply_theme_defaults?
       ) do
    if theme == previous_theme and
         state.apply_theme_defaults? == previous_apply_theme_defaults? do
      state
    else
      Enum.each(state.children, fn
        {_id, %{pid: pid}} when is_pid(pid) ->
          if Process.alive?(pid) do
            safe_call(fn ->
              Breeze.ChildServer.put_theme(pid, theme,
                apply_theme_defaults?: state.apply_theme_defaults?,
                notify?: false
              )
            end)
          end

        _child ->
          :ok
      end)

      state
    end
  end

  defp prune_dead_children(state) do
    alive_children =
      state.children
      |> Enum.filter(fn {_id, child} -> is_pid(child.pid) and Process.alive?(child.pid) end)
      |> Map.new()

    %{state | children: alive_children}
  end

  defp maybe_start_reloader(%{reload_opts: nil} = state), do: state

  defp maybe_start_reloader(state) do
    {:ok, pid} =
      Breeze.CodeReloader.start_link(Keyword.put(state.reload_opts, :server_pid, self()))

    %{state | reloader_pid: pid}
  end

  defp normalize_reload_opts(false), do: nil
  defp normalize_reload_opts(nil), do: nil

  defp normalize_reload_opts(true) do
    if reload_supported?(), do: [enabled?: true], else: nil
  end

  defp normalize_reload_opts(opts) when is_list(opts) do
    enabled? = Keyword.get(opts, :enabled?, true)
    force? = Keyword.get(opts, :force?, false)

    if enabled? and (force? or reload_supported?()) do
      opts
    else
      nil
    end
  end

  defp reload_supported? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :dev
  end

  defp ensure_children(state, missing) do
    Enum.reduce(missing, {state, false}, fn {id, attrs}, {state, started?} ->
      view = fetch_live_attr!(attrs, :view)
      start_opts = child_start_opts(fetch_live_attr(attrs, :start_opts, []), view, state)
      assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()

      case Map.get(state.children, id) do
        %{pid: pid, view: ^view, start_opts: ^start_opts} = child when is_pid(pid) ->
          if Process.alive?(pid) do
            if Map.get(child, :assigns, %{}) == assigns do
              {state, started?}
            else
              :ok = Breeze.ChildServer.update_assigns(pid, assigns)
              child = %{child | assigns: assigns}
              {%{state | children: Map.put(state.children, id, child)}, true}
            end
          else
            ref = Map.get(child, :ref)
            if is_reference(ref), do: Process.demonitor(ref, [:flush])

            child = start_child!(attrs, state.terminal, state.theme, state)
            {%{state | children: Map.put(state.children, id, child)}, true}
          end

        %{pid: _pid, ref: _ref} = child ->
          shutdown_tracked_child(state.child_view_supervisor, child)

          child = start_child!(attrs, state.terminal, state.theme, state)
          {%{state | children: Map.put(state.children, id, child)}, true}

        nil ->
          child = start_child!(attrs, state.terminal, state.theme, state)
          {%{state | children: Map.put(state.children, id, child)}, true}
      end
    end)
  end

  defp reconcile_live_children(state, :disabled), do: state

  defp reconcile_live_children(state, seen) do
    seen = Map.new(seen)

    children =
      Enum.reduce(state.children, %{}, fn {id, child}, acc ->
        case Map.fetch(seen, id) do
          {:ok, attrs} ->
            child =
              child
              |> Map.put(:attrs, attrs)
              |> Map.put(:persistent, fetch_live_attr(attrs, :persistent, false))

            Map.put(acc, id, child)

          :error ->
            if Map.get(child, :persistent, false) do
              Map.put(acc, id, child)
            else
              shutdown_tracked_child(state.child_view_supervisor, child)
              acc
            end
        end
      end)

    %{state | children: children}
  end

  defp shutdown_tracked_child(supervisor, child) do
    shutdown_view_process(supervisor, Map.get(child, :pid))

    case Map.get(child, :ref) do
      ref when is_reference(ref) -> Process.demonitor(ref, [:flush])
      _ref -> :ok
    end
  end

  defp start_async_dispatch(state, key) do
    caller = self()
    ref = make_ref()

    Task.start(fn ->
      reply = dispatch_input_hierarchy(state, key)
      send(caller, {:event_reply, ref, reply})
    end)

    state
    |> update_input(pending_ref: ref, pending_started_at: System.monotonic_time(:millisecond))
    |> Debug.put_stat(:last_async_key, key)
    |> schedule_animation()
  end

  defp start_child!(attrs, terminal, theme, state) do
    view = fetch_live_attr!(attrs, :view)
    start_opts = child_start_opts(fetch_live_attr(attrs, :start_opts, []), view, state)
    assigns = fetch_live_attr(attrs, :assigns, %{}) |> Map.new()
    persistent = fetch_live_attr(attrs, :persistent, false)
    parent = self()
    child_id = fetch_live_attr!(attrs, :id)
    invalidate = fn -> send(parent, {:child_invalidated, child_id}) end

    {:ok, pid} =
      Breeze.ChildViewSupervisor.start_child(
        state.child_view_supervisor,
        view: view,
        start_opts: start_opts,
        assigns: assigns,
        server: self(),
        terminal: terminal,
        theme: theme,
        apply_theme_defaults?: state.apply_theme_defaults?,
        process_flags: state.child_process_flags || [],
        render_tree?: Breeze.Inspector.enabled?(state),
        invalidate: invalidate
      )

    ref = Process.monitor(pid)

    %{
      pid: pid,
      ref: ref,
      view: view,
      start_opts: start_opts,
      assigns: assigns,
      attrs: attrs,
      persistent: persistent
    }
  end

  defp child_start_opts(start_opts, Breeze.Debug, state) do
    Keyword.put_new(start_opts, :stats, Debug.snapshot(state))
  end

  defp child_start_opts(start_opts, _view, _state), do: start_opts

  defp safe_root_metadata(state) do
    case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
      {:ok, metadata} -> metadata
      {:crash, _crash} -> %{}
    end
  end

  defp schedule_input_flush(%{input: %{pending_ref: ref}} = state) when not is_nil(ref),
    do: state

  defp schedule_input_flush(state) do
    Input.schedule_flush(state, @flush_input_batch)
  end

  defp root_view_module(%{children: _} = state) do
    case safe_call(fn -> Breeze.ChildServer.metadata(state.view_pid) end) do
      {:ok, %{view: view}} -> view
      _ -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp dispatch_input_hierarchy(state, key) do
    state =
      case safe_root_metadata(state) do
        %{focused: focused} -> %{state | focused: focused}
        _metadata -> state
      end

    root_global_reply =
      if Breeze.InputCapture.printable_key?(key) or focused_implicit_captures_key?(state, key) do
        nil
      else
        case safe_call(fn ->
               Breeze.ChildServer.dispatch_global_keybindings(state.view_pid, key)
             end) do
          {:ok, {:noreply, _focused, false}} -> nil
          {:ok, reply} -> reply
          {:crash, crash} -> {:crash, crash}
        end
      end

    if root_global_reply do
      root_global_reply
    else
      dispatch_focused_input_hierarchy(state, key)
    end
  end

  defp dispatch_focused_input_hierarchy(state, key) do
    child_reply =
      state
      |> focused_child_chain()
      |> Enum.reduce_while(nil, fn {child_id, %{pid: pid}}, _acc ->
        case safe_call(fn -> Breeze.ChildServer.dispatch_input(pid, key) end) do
          {:ok, reply} ->
            reply = namespace_child_reply(reply, child_id)

            case reply do
              {:noreply, _focused, true} -> {:halt, reply}
              {:stop, _focused, _consumed} -> {:halt, reply}
              _ -> {:cont, nil}
            end

          {:crash, crash} ->
            {:halt, {:crash, crash}}
        end
      end)

    case child_reply do
      {:crash, _crash} = crash ->
        crash

      nil ->
        case safe_call(fn ->
               if state.focused, do: Breeze.ChildServer.set_focus(state.view_pid, state.focused)

               Breeze.ChildServer.dispatch_input(state.view_pid, key,
                 skip_global: focused_implicit_captures_key?(state, key)
               )
             end) do
          {:ok, reply} -> reply
          {:crash, crash} -> {:crash, crash}
        end

      reply ->
        reply
    end
  end

  defp focused_child_chain(%{focused: nil}), do: []

  defp focused_child_chain(%{focused: focused, children: children}) do
    children
    |> Enum.filter(fn {id, _child} ->
      focused == id or String.starts_with?(focused, id <> "::")
    end)
    |> Enum.sort_by(fn {id, _child} -> String.length(id) end, :desc)
  end

  defp namespace_child_reply({:stop, focused}, child_id),
    do: {:stop, namespace_child_focus(focused, child_id)}

  defp namespace_child_reply({:stop, focused, consumed}, child_id),
    do: {:stop, namespace_child_focus(focused, child_id), consumed}

  defp namespace_child_reply({:noreply, focused}, child_id),
    do: {:noreply, namespace_child_focus(focused, child_id)}

  defp namespace_child_reply({:noreply, nil, true}, child_id),
    do: {:noreply, child_id, true}

  defp namespace_child_reply({:noreply, focused, consumed}, child_id),
    do: {:noreply, namespace_child_focus(focused, child_id), consumed}

  defp namespace_child_focus(nil, _child_id), do: nil
  defp namespace_child_focus(focused, child_id), do: child_id <> "::" <> focused

  defp strip_live_prefix(nil, _live_id), do: nil

  defp strip_live_prefix(id, live_id) do
    prefix = live_id <> "::"

    if String.starts_with?(id, prefix) do
      String.replace_prefix(id, prefix, "")
    end
  end

  defp live_id(nil, id), do: id
  defp live_id(prefix, id), do: prefix <> "::" <> id

  defp fetch_live_attr!(attrs, key) do
    Map.get(attrs, key) || Map.fetch!(attrs, Atom.to_string(key))
  end

  defp fetch_live_attr(attrs, key, default) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key), default)
  end
end
