defmodule Breeze.Logger.Handler do
  @moduledoc false

  @behaviour :logger_handler

  @handler_id :breeze_logger
  @formatter_config %{single_line: true}

  def handler_id, do: @handler_id

  def ensure_installed(collector) when is_pid(collector) do
    config = %{config: %{collector: collector}}

    case :logger.add_handler(@handler_id, __MODULE__, config) do
      :ok ->
        :ok

      {:error, {:already_exist, @handler_id}} ->
        :logger.set_handler_config(@handler_id, :config, %{collector: collector})

      other ->
        other
    end
  end

  def remove do
    case :logger.remove_handler(@handler_id) do
      :ok -> :ok
      {:error, {:not_found, @handler_id}} -> :ok
      other -> other
    end
  end

  @impl true
  def adding_handler(config), do: {:ok, config}

  @impl true
  def changing_config(_set_or_update, _old_config, new_config), do: {:ok, new_config}

  @impl true
  def filter_config(config), do: config

  @impl true
  def removing_handler(_config), do: :ok

  @impl true
  def log(event, %{config: %{collector: collector}}) when is_pid(collector) do
    entry = %{
      level: Map.get(event, :level, :info),
      line: format_event(event)
    }

    GenServer.cast(collector, {:log, entry})
  rescue
    _ -> :ok
  end

  def log(_event, _config), do: :ok

  defp format_event(event) do
    event
    |> :logger_formatter.format(@formatter_config)
    |> unicode_chardata_to_binary()
    |> String.trim_trailing()
  rescue
    _ -> inspect(event)
  end

  defp unicode_chardata_to_binary(chardata) do
    case :unicode.characters_to_binary(chardata) do
      binary when is_binary(binary) ->
        binary

      {:error, _valid, _rest} ->
        chardata_to_valid_binary(chardata)

      {:incomplete, _valid, _rest} ->
        chardata_to_valid_binary(chardata)
    end
  end

  defp chardata_to_valid_binary(chardata) do
    binary = IO.iodata_to_binary(chardata)

    if String.valid?(binary) do
      binary
    else
      :unicode.characters_to_binary(binary, :latin1, :utf8)
    end
  end
end
