defmodule Mix.Tasks.Breeze.Inspector do
  @moduledoc """
  Starts the Breeze remote inspector.

  Run the inspector locally:

      mix breeze.inspector

  Pass a distributed Erlang node name with `--connect` to inspect a remote
  Breeze application:

      mix breeze.inspector --connect app@host
  """

  use Mix.Task

  @shortdoc "Starts the Breeze remote inspector"
  @switches [connect: :string]

  @impl true
  def run(args) do
    Mix.Task.run("compile")
    {:ok, _started} = Application.ensure_all_started(:breeze)

    ensure_distribution!()

    {opts, positional, _invalid} = OptionParser.parse(args, strict: @switches)
    maybe_connect_target(Keyword.get(opts, :connect) || List.first(positional))

    {:ok, _pid} = Breeze.RemoteInspector.ensure_server()

    Mix.shell().info("Starting Breeze remote inspector on #{node()}")

    Breeze.Example.run(run_opts())
  end

  @doc false
  def run_opts do
    [
      view: Breeze.RemoteInspector.View,
      reload: watcher_available?(),
      theme: :system,
      mouse: true,
      global_keybindings: Breeze.RemoteInspector.View.global_keybindings(),
      inspector: true
    ]
  end

  @doc false
  def watcher_available?(watcher_module \\ FileSystem) do
    Code.ensure_loaded?(watcher_module) and
      function_exported?(watcher_module, :start_link, 1) and
      function_exported?(watcher_module, :subscribe, 1)
  end

  @doc false
  def normalize_connect_target(target) when is_binary(target) do
    target =
      if String.contains?(target, "@") do
        target
      else
        "#{target}@#{current_host()}"
      end

    String.to_atom(target)
  end

  @doc false
  def distribution_error_message(reason) do
    if distribution_epmd_unavailable?(reason) do
      """
      breeze.inspector could not start distributed Erlang because epmd appears to be unavailable.

      Start epmd, then run `mix breeze.inspector` again:

          epmd -daemon

      You may also need to restart your application so it can start distributed Erlang.
      """
      |> String.trim()
    else
      "breeze.inspector could not start distributed Erlang as inspector: #{inspect(reason)}"
    end
  end

  defp maybe_connect_target(nil), do: :ok

  defp maybe_connect_target(target) do
    node_name = normalize_connect_target(target)

    case Node.connect(node_name) do
      true ->
        Mix.shell().info("Connected to #{node_name}")
        :ok

      false ->
        Mix.raise("Could not connect remote inspector to #{node_name}")

      :ignored ->
        Mix.raise("Connection to #{node_name} was ignored")
    end
  end

  defp ensure_distribution! do
    case Breeze.RemoteInspector.ensure_inspector_distribution() do
      :ok ->
        :ok

      {:error, reason} ->
        Mix.raise(distribution_error_message(reason))
    end
  end

  defp distribution_epmd_unavailable?(reason) do
    term_contains?(reason, :nodistribution)
  end

  defp term_contains?(term, value) when term == value, do: true

  defp term_contains?(term, value) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.any?(&term_contains?(&1, value))

  defp term_contains?(term, value) when is_list(term),
    do: Enum.any?(term, &term_contains?(&1, value))

  defp term_contains?(term, value) when is_map(term) do
    Enum.any?(term, fn {key, item} ->
      term_contains?(key, value) or term_contains?(item, value)
    end)
  end

  defp term_contains?(_term, _value), do: false

  defp current_host do
    case String.split(to_string(node()), "@", parts: 2) do
      [_name, host] when host != "" ->
        host

      _ ->
        case :inet.gethostname() do
          {:ok, hostname} -> to_string(hostname)
          _ -> "localhost"
        end
    end
  end
end
