defmodule Breeze.InputRouter.SilentGroupLeader do
  @moduledoc false

  def start_link do
    pid = spawn_link(fn -> loop() end)
    {:ok, pid}
  end

  def stop(pid) when is_pid(pid) do
    Process.unlink(pid)
    Process.exit(pid, :shutdown)
    :ok
  end

  def stop(_pid), do: :ok

  defp loop do
    receive do
      {:io_request, from, reply_as, request} ->
        handle_io_request(from, reply_as, request)
        loop()

      _message ->
        loop()
    end
  end

  defp handle_io_request(from, reply_as, request) do
    cond do
      input_request?(request) ->
        :ok

      true ->
        send(from, {:io_reply, reply_as, :ok})
    end
  end

  defp input_request?({:get_chars, _encoding, _prompt, _count}), do: true
  defp input_request?({:get_line, _encoding, _prompt}), do: true
  defp input_request?({:get_until, _encoding, _prompt, _module, _function, _args}), do: true
  defp input_request?({:get_password, _encoding}), do: true
  defp input_request?(_request), do: false
end
