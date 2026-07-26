defmodule Breeze.CodeReloader do
  @moduledoc false

  use GenServer

  @default_paths ["lib", "examples", "storybook"]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %{
      server_pid: Keyword.fetch!(opts, :server_pid),
      paths: Keyword.get(opts, :paths, @default_paths),
      watcher_module: Keyword.get(opts, :watcher_module, FileSystem),
      files_fun: Keyword.get(opts, :files_fun, &list_files/1),
      compile_fun: Keyword.get(opts, :compile_fun, &compile_changed_files/1),
      file_versions: %{},
      watcher_pid: nil
    }

    state =
      state
      |> Map.put(:file_versions, snapshot_files(state.files_fun, state.paths))
      |> start_watcher!()

    {:ok, state}
  end

  @impl true
  def handle_info(
        {:file_event, watcher_pid, {_path, _events}},
        %{watcher_pid: watcher_pid} = state
      ) do
    {:noreply, reload_changed_files(state)}
  end

  def handle_info({:file_event, _watcher_pid, _event}, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if is_pid(state.watcher_pid) and Process.alive?(state.watcher_pid) do
      Process.unlink(state.watcher_pid)
      Process.exit(state.watcher_pid, :shutdown)
    end

    :ok
  end

  defp snapshot_files(files_fun, paths) do
    paths
    |> files_fun.()
    |> Enum.sort()
    |> Enum.reduce(%{}, fn path, acc ->
      case File.stat(path, time: :posix) do
        {:ok, stat} -> Map.put(acc, path, {stat.mtime, stat.size})
        {:error, _reason} -> acc
      end
    end)
  end

  defp changed_files(previous, current) do
    added_or_changed =
      Enum.reduce(current, [], fn {path, mtime}, acc ->
        if Map.get(previous, path) != mtime, do: [path | acc], else: acc
      end)

    removed =
      Enum.reduce(previous, [], fn {path, _mtime}, acc ->
        if Map.has_key?(current, path), do: acc, else: [path | acc]
      end)

    added_or_changed
    |> Kernel.++(removed)
    |> Enum.sort()
  end

  defp list_files(paths) do
    paths
    |> Enum.flat_map(fn path ->
      if File.dir?(path) do
        Path.wildcard(Path.join(path, "**/*.{ex,exs}"))
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp compile_changed_files(files) do
    previous = Code.compiler_options()
    Code.put_compiler_option(:ignore_module_conflict, true)

    try do
      Breeze.ReloadContext.with_compile(fn ->
        files
        |> Enum.filter(&File.regular?/1)
        |> Enum.each(&Code.compile_file/1)
      end)

      :ok
    rescue
      error -> {:error, error}
    after
      Code.compiler_options(previous)
    end
  end

  defp reload_changed_files(state) do
    current_versions = snapshot_files(state.files_fun, state.paths)
    changed_files = changed_files(state.file_versions, current_versions)

    case changed_files do
      [] ->
        %{state | file_versions: current_versions}

      files ->
        notify_reload_result(state, files, current_versions)
    end
  end

  defp notify_reload_result(state, files, current_versions) do
    case state.compile_fun.(files) do
      :ok ->
        send(state.server_pid, {:reload, :code_changed, files})
        %{state | file_versions: current_versions}

      {:error, reason} ->
        send(state.server_pid, {:reload, :compile_error, reason, files})
        %{state | file_versions: current_versions}
    end
  end

  defp start_watcher!(state) do
    watcher_module = state.watcher_module
    paths = Enum.filter(state.paths, &File.dir?/1)

    unless watcher_supported?(watcher_module) do
      raise ArgumentError,
            "live reload requires a watcher module with start_link/1 and subscribe/1, got: #{inspect(watcher_module)}"
    end

    case watcher_module.start_link(dirs: paths) do
      {:ok, watcher_pid} ->
        :ok = watcher_module.subscribe(watcher_pid)
        %{state | watcher_pid: watcher_pid}

      :ignore ->
        raise RuntimeError,
              "live reload failed to start #{inspect(watcher_module)}: watcher returned :ignore"

      {:error, reason} ->
        raise RuntimeError,
              "live reload failed to start #{inspect(watcher_module)}: #{Exception.format_exit(reason)}"
    end
  end

  defp watcher_supported?(watcher_module) do
    Code.ensure_loaded?(watcher_module) and function_exported?(watcher_module, :start_link, 1) and
      function_exported?(watcher_module, :subscribe, 1)
  end
end
