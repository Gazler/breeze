defmodule Breeze.InputRouter.IExShellProxy do
  @moduledoc false

  def start_link(target) do
    previous_group_leader = Process.group_leader()

    with {:ok, user_drv, previous_group, reader} <- start_reader(target) do
      {:ok,
       %{
         pid: reader,
         user_drv: user_drv,
         previous_group: previous_group,
         previous_group_leader: previous_group_leader
       }}
    end
  end

  def stop(nil), do: :ok

  def stop(%{
        pid: pid,
        user_drv: user_drv,
        previous_group: previous_group,
        previous_group_leader: previous_group_leader
      }) do
    restore_user_drv_group(user_drv, previous_group)
    restore_process_group_leader(previous_group_leader)
    stop_proxy(pid)

    :ok
  end

  defp start_reader(target) do
    with user_drv when is_pid(user_drv) <- Process.whereis(:user_drv),
         {:ok, previous_group, _user_group} <- current_user_drv_groups(user_drv) do
      proxy = spawn_link(fn -> proxy_loop(target, user_drv, %{}) end)
      set_user_drv_group(user_drv, proxy)
      Process.group_leader(self(), proxy)

      {:ok, user_drv, previous_group, proxy}
    else
      _ -> :error
    end
  catch
    _kind, _reason -> :error
  end

  defp proxy_loop(target, user_drv, pending) do
    receive do
      {^user_drv, {:data, data}} ->
        send(target, {:data, data})
        proxy_loop(target, user_drv, pending)

      {^user_drv, {:signal, signal}} ->
        send(target, {:signal, signal})
        proxy_loop(target, user_drv, pending)

      {:io_request, from, reply_as, request} ->
        proxy_loop(
          target,
          user_drv,
          handle_io_request(user_drv, from, reply_as, request, pending)
        )

      {reply_kind, reply_key, reply} when reply_kind in [:reply, :io_reply] ->
        reply_io_request(reply_key, reply)
        proxy_loop(target, user_drv, Map.delete(pending, reply_key))

      {^user_drv, :tty_geometry, geometry} ->
        {pending_geometry, pending} = Map.pop(pending, :tty_geometry, [])
        Enum.each(Enum.reverse(pending_geometry), &reply_geometry(&1, geometry))
        proxy_loop(target, user_drv, pending)

      :stop ->
        :ok

      _message ->
        proxy_loop(target, user_drv, pending)
    end
  end

  defp handle_io_request(user_drv, from, reply_as, {:requests, requests}, pending)
       when is_list(requests) do
    Enum.reduce(requests, pending, fn request, acc ->
      handle_io_request(user_drv, from, reply_as, request, acc)
    end)
  end

  defp handle_io_request(user_drv, from, reply_as, {:get_geometry, what}, pending) do
    send(user_drv, {self(), :tty_geometry})

    Map.update(
      pending,
      :tty_geometry,
      [{from, reply_as, what}],
      &[{from, reply_as, what} | &1]
    )
  end

  defp handle_io_request(user_drv, from, reply_as, request, pending) do
    case put_chars_request(request) do
      {:ok, encoding, chars} ->
        reply_key = {from, reply_as}
        send(user_drv, {self(), {:put_chars_sync, encoding, chars, reply_key}})
        Map.put(pending, reply_key, true)

      :ignore ->
        send(from, {:io_reply, reply_as, :ok})
        pending

      :error ->
        send(from, {:io_reply, reply_as, {:error, :request}})
        pending
    end
  end

  defp put_chars_request({:put_chars, encoding, chars})
       when encoding in [:unicode, :latin1] do
    {:ok, encoding, IO.iodata_to_binary(chars)}
  end

  defp put_chars_request({:put_chars, chars}), do: {:ok, :latin1, IO.iodata_to_binary(chars)}

  defp put_chars_request({:put_chars, encoding, module, function, args})
       when encoding in [:unicode, :latin1] do
    {:ok, encoding, IO.iodata_to_binary(apply(module, function, args))}
  rescue
    _ -> :error
  end

  defp put_chars_request({:put_chars, module, function, args}) do
    {:ok, :latin1, IO.iodata_to_binary(apply(module, function, args))}
  rescue
    _ -> :error
  end

  defp put_chars_request({:setopts, _opts}), do: :ignore
  defp put_chars_request(:getopts), do: :ignore
  defp put_chars_request(_request), do: :error

  defp reply_io_request({from, reply_as}, reply) when is_pid(from) do
    send(from, {:io_reply, reply_as, reply})
  end

  defp reply_io_request(_reply_key, _reply), do: :ok

  defp reply_geometry({from, reply_as, :columns}, {columns, _rows}) when is_integer(columns),
    do: send(from, {:io_reply, reply_as, columns})

  defp reply_geometry({from, reply_as, :rows}, {_columns, rows}) when is_integer(rows),
    do: send(from, {:io_reply, reply_as, rows})

  defp reply_geometry({from, reply_as, _what}, _geometry),
    do: send(from, {:io_reply, reply_as, {:error, :enotsup}})

  defp stop_proxy(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      Process.unlink(pid)
      send(pid, :stop)
    end
  end

  defp stop_proxy(_pid), do: :ok

  defp current_user_drv_groups(user_drv) do
    case :sys.get_state(user_drv) do
      {_state_name, data} -> {:ok, elem(data, 8), elem(data, 7)}
      _state -> :error
    end
  rescue
    _ -> :error
  end

  defp set_user_drv_group(user_drv, group) when is_pid(user_drv) and is_pid(group) do
    :sys.replace_state(user_drv, fn
      {state_name, data} ->
        Process.put(:current_group, group)
        {state_name, put_elem(data, 8, group)}

      state ->
        state
    end)

    :ok
  catch
    _kind, _reason -> :ok
  end

  defp restore_user_drv_group(user_drv, previous_group)
       when is_pid(user_drv) and is_pid(previous_group) do
    set_user_drv_group(user_drv, previous_group)
    send(previous_group, {user_drv, :activate})
  end

  defp restore_user_drv_group(_user_drv, _previous_group), do: :ok

  defp restore_process_group_leader(previous_group_leader) when is_pid(previous_group_leader) do
    Process.group_leader(self(), previous_group_leader)
  end

  defp restore_process_group_leader(_previous_group_leader), do: :ok
end
