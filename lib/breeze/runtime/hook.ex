defmodule Breeze.Runtime.Hook do
  @moduledoc """
  Opt-in lifecycle hook for tooling built around a Breeze runtime.

  Hooks are configured per server with `:runtime_hooks`:

      runtime_hooks: [
        {MyMetricsHook, []},
        {MyDevelopmentTool, sample_every: 5},
        {MyAnimationHook, notify_animation?: true}
      ]

  Periodic animation passes are quiet by default and require
  `notify_animation?: true`.

  Hooks run synchronously after a committed lifecycle event. The supplied
  `Breeze.Runtime.Context` lazily exposes runtime state and diagnostics, so a
  hook pays for only the data it chooses to read. Slow storage or processing
  should be handed off to another process.
  """

  require Logger

  alias Breeze.Runtime.Context

  defstruct [:module, :state, notify_animation?: false]

  @type t :: %__MODULE__{
          module: module(),
          state: hook_state(),
          notify_animation?: boolean()
        }
  @type config :: module() | {module(), keyword()}
  @type event :: :rendered
  @type hook_state :: term()

  @callback init(keyword(), map()) :: {:ok, hook_state()} | hook_state()
  @callback handle_event(event(), Context.t(), hook_state()) :: {:noreply, hook_state()}

  @optional_callbacks init: 2

  @doc false
  @spec init([config()], map()) :: [t()]
  def init(configs, metadata) when is_list(configs),
    do: Enum.map(configs, &init_hook(&1, metadata))

  @doc false
  def notify(_server_state, [], _event, _metadata), do: []

  def notify(server_state, hooks, event, metadata) when is_list(hooks) do
    context = Context.new(server_state, metadata)

    hooks
    |> Enum.reduce([], fn hook, acc ->
      if notify_hook?(hook, Context.metadata(context)) do
        case invoke_event(hook, event, context) do
          {:ok, hook} ->
            [hook | acc]

          {:disable, reason} ->
            disable_hook(hook.module, reason)
            acc
        end
      else
        [hook | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp init_hook(module, metadata) when is_atom(module), do: init_hook({module, []}, metadata)

  defp init_hook({module, opts}, metadata) when is_atom(module) and is_list(opts) do
    if Code.ensure_loaded?(module) and function_exported?(module, :handle_event, 3) do
      state =
        if function_exported?(module, :init, 2) do
          case module.init(opts, metadata) do
            {:ok, state} -> state
            state -> state
          end
        else
          opts
        end

      %__MODULE__{
        module: module,
        state: state,
        notify_animation?: Keyword.get(opts, :notify_animation?, false) == true
      }
    else
      raise ArgumentError, "runtime hook #{inspect(module)} must export handle_event/3"
    end
  end

  defp init_hook(config, _metadata) do
    raise ArgumentError,
          "runtime hook entries must be a module or {module, keyword}, got: " <> inspect(config)
  end

  defp notify_hook?(%__MODULE__{notify_animation?: enabled?}, %{mode: :animation}), do: enabled?
  defp notify_hook?(%__MODULE__{}, _metadata), do: true

  defp invoke_event(%__MODULE__{module: module, state: hook_state} = hook, event, context) do
    case module.handle_event(event, context, hook_state) do
      {:noreply, next_hook_state} -> {:ok, %{hook | state: next_hook_state}}
      other -> {:disable, "returned an invalid handle_event/3 result: #{inspect(other)}"}
    end
  rescue
    error ->
      {:disable, "raised from handle_event/3: #{Exception.format(:error, error, __STACKTRACE__)}"}
  catch
    kind, reason -> {:disable, "failed in handle_event/3: #{inspect({kind, reason})}"}
  end

  defp disable_hook(module, reason) do
    Logger.warning("Disabling Breeze runtime hook #{inspect(module)} because it #{reason}")
  end
end
