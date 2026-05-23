defmodule Mix.Tasks.Breeze.Inspector do
  use Mix.Task

  @shortdoc "Starts the Breeze remote inspector"
  @switches [connect: :string]

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    unless Node.alive?() do
      Mix.raise(
        "breeze.inspector requires distributed Erlang. Start with --sname or --name, for example: elixir --sname inspector -S mix breeze.inspector"
      )
    end

    {opts, positional, _invalid} = OptionParser.parse(args, strict: @switches)
    maybe_connect_target(Keyword.get(opts, :connect) || List.first(positional))

    {:ok, _pid} = Breeze.RemoteInspector.ensure_server()

    Mix.shell().info("Starting Breeze remote inspector on #{node()}")

    Breeze.Example.run(run_opts())
  end

  def run_opts do
    [
      view: Breeze.RemoteInspector.View,
      reload: true,
      theme: :system,
      mouse: true,
      global_keybindings: Breeze.RemoteInspector.View.global_keybindings(),
      inspector: true
    ]
  end

  def normalize_connect_target(target) when is_binary(target) do
    target =
      if String.contains?(target, "@") do
        target
      else
        "#{target}@#{current_host()}"
      end

    String.to_atom(target)
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
