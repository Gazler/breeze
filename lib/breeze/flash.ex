defmodule Breeze.Flash do
  @moduledoc false

  @state_key :__breeze_flash__
  @default_max 3
  @default_duration 5_000

  @doc false
  def put(flash, kind, message, opts \\ []) do
    opts = normalize_opts(opts)
    flash = normalize_state(flash, opts)

    flash
    |> enqueue_entry(entry(kind, message, opts, flash.duration))
    |> fill_visible()
  end

  @doc false
  def clear(_flash, nil), do: []

  def clear(%{@state_key => true} = flash, key) do
    key = flash_key(key)

    flash
    |> Map.update!(:entries, &reject_matching(&1, key))
    |> Map.update!(:queue, &reject_matching(&1, key))
    |> fill_visible()
  end

  def clear(flash, key) do
    key = flash_key(key)

    flash
    |> entries()
    |> Enum.reject(&matches_key?(&1, key))
  end

  @doc false
  def expire(%{@state_key => true} = flash, id, token) do
    id = flash_key(id)

    {expired?, entries} =
      Enum.reduce(flash.entries, {false, []}, fn entry, {expired?, entries} ->
        if flash_key(Map.get(entry, :id)) == id and Map.get(entry, :timer_token) == token do
          {true, entries}
        else
          {expired?, [entry | entries]}
        end
      end)

    if expired? do
      flash
      |> Map.put(:entries, Enum.reverse(entries))
      |> fill_visible()
    else
      flash
    end
  end

  def expire(flash, _id, _token), do: flash

  @doc false
  def schedule_visible(%{@state_key => true} = flash, schedule_fun)
      when is_function(schedule_fun, 2) do
    entries =
      Enum.map(flash.entries, fn entry ->
        cond do
          Map.has_key?(entry, :timer_token) ->
            entry

          not scheduleable_duration?(Map.get(entry, :duration)) ->
            entry

          true ->
            token = make_ref()
            schedule_fun.({:breeze_flash_timeout, Map.fetch!(entry, :id), token}, entry.duration)
            Map.put(entry, :timer_token, token)
        end
      end)

    %{flash | entries: entries}
  end

  def schedule_visible(flash, _schedule_fun), do: flash

  @doc false
  def entries(%{@state_key => true, entries: entries}) do
    Enum.map(entries, &public_entry/1)
  end

  def entries(nil), do: []
  def entries(false), do: []

  def entries(%{} = flash) do
    if entry_map?(flash) do
      [normalize_entry_map(flash, 0)]
    else
      flash
      |> Enum.with_index()
      |> Enum.flat_map(fn {{kind, message}, index} ->
        entries_from_kind(kind, message, index)
      end)
    end
  end

  def entries(flash) when is_list(flash) do
    cond do
      flash == [] ->
        []

      Keyword.keyword?(flash) and entry_keyword?(flash) ->
        [normalize_entry_map(Map.new(flash), 0)]

      Keyword.keyword?(flash) ->
        flash
        |> Enum.with_index()
        |> Enum.flat_map(fn {{kind, message}, index} ->
          entries_from_kind(kind, message, index)
        end)

      true ->
        flash
        |> Enum.with_index()
        |> Enum.flat_map(fn {entry, index} ->
          normalize_entry(entry, index)
        end)
    end
  end

  def entries({kind, message}), do: entries_from_kind(kind, message, 0)
  def entries(message) when is_binary(message), do: [normalize_entry_map(%{message: message}, 0)]
  def entries(_flash), do: []

  @doc false
  def queued_entries(%{@state_key => true, queue: queue}) do
    Enum.map(queue, &public_entry/1)
  end

  def queued_entries(_flash), do: []

  defp normalize_state(%{@state_key => true} = flash, opts) do
    max = option(opts, [:max], Map.get(flash, :max, @default_max)) |> normalize_max()

    duration =
      option(
        opts,
        [:duration, :duration_ms, :timeout],
        Map.get(flash, :duration, @default_duration)
      )
      |> normalize_duration()

    flash
    |> Map.put(:max, max)
    |> Map.put(:duration, duration)
    |> Map.update(
      :entries,
      [],
      &Enum.map(&1, fn entry -> ensure_entry_duration(entry, duration) end)
    )
    |> Map.update(
      :queue,
      [],
      &Enum.map(&1, fn entry -> ensure_entry_duration(entry, duration) end)
    )
    |> fill_visible()
  end

  defp normalize_state(flash, opts) do
    max = option(opts, [:max], @default_max) |> normalize_max()

    duration =
      option(opts, [:duration, :duration_ms, :timeout], @default_duration) |> normalize_duration()

    {visible, queue} =
      flash
      |> entries()
      |> Enum.map(&ensure_entry_duration(&1, duration))
      |> Enum.split(max)

    %{
      @state_key => true,
      entries: visible,
      queue: queue,
      max: max,
      duration: duration
    }
  end

  defp enqueue_entry(%{entries: entries, queue: queue, max: max} = flash, entry) do
    if length(entries) < max do
      %{flash | entries: entries ++ [entry]}
    else
      %{flash | queue: queue ++ [entry]}
    end
  end

  defp fill_visible(%{entries: entries, queue: queue, max: max} = flash) do
    {entries, overflow} = Enum.split(entries, max)
    queue = overflow ++ queue
    capacity = max(max - length(entries), 0)
    {promoted, queue} = Enum.split(queue, capacity)

    %{flash | entries: entries ++ Enum.map(promoted, &Map.delete(&1, :timer_token)), queue: queue}
  end

  defp entry(kind, message, opts, default_duration) do
    kind = normalize_kind(kind)

    duration =
      option(opts, [:duration, :duration_ms, :timeout], default_duration) |> normalize_duration()

    %{
      id: option(opts, [:id], generated_id(kind)),
      kind: kind,
      message: message_text(message),
      duration: duration
    }
    |> maybe_put(:title, option(opts, [:title], nil))
    |> maybe_put(:highlight, option(opts, [:highlight, :color], nil))
  end

  defp entries_from_kind(_kind, value, _index) when value in [nil, false], do: []

  defp entries_from_kind(kind, value, index) when is_list(value) and not is_binary(value) do
    if Keyword.keyword?(value) and entry_keyword?(value) do
      [normalize_entry_map(value |> Map.new() |> Map.put_new(:kind, kind), index)]
    else
      value
      |> Enum.with_index()
      |> Enum.flat_map(fn {entry, child_index} ->
        normalize_entry(
          Map.put(normalize_entry_payload(entry), :kind, kind),
          {index, child_index}
        )
      end)
    end
  end

  defp entries_from_kind(kind, value, index) when is_map(value) do
    [normalize_entry_map(Map.put_new(value, :kind, kind), index)]
  end

  defp entries_from_kind(kind, value, index) do
    [normalize_entry_map(%{kind: kind, message: value}, index)]
  end

  defp normalize_entry(entry, _index) when entry in [nil, false], do: []
  defp normalize_entry(%{} = entry, index), do: [normalize_entry_map(entry, index)]

  defp normalize_entry({kind, message}, index) do
    entries_from_kind(kind, message, index)
  end

  defp normalize_entry(message, index) do
    [normalize_entry_map(%{message: message}, index)]
  end

  defp normalize_entry_map(entry, index) do
    entry = normalize_entry_payload(entry)
    kind = normalize_kind(Map.get(entry, :kind, :info))

    %{
      id: Map.get(entry, :id) || indexed_id(kind, index),
      kind: kind,
      message: message_text(Map.get(entry, :message, Map.get(entry, :text, "")))
    }
    |> maybe_put(:title, Map.get(entry, :title))
    |> maybe_put(:highlight, Map.get(entry, :highlight, Map.get(entry, :color)))
  end

  defp normalize_entry_payload(%{} = entry) do
    Map.new(entry, fn {key, value} -> {normalize_entry_key(key), value} end)
  end

  defp normalize_entry_payload(entry), do: %{message: entry}

  defp normalize_entry_key(key) when is_atom(key), do: key

  defp normalize_entry_key(key) when is_binary(key) do
    case key do
      "id" -> :id
      "kind" -> :kind
      "message" -> :message
      "text" -> :text
      "title" -> :title
      "highlight" -> :highlight
      "color" -> :color
      _ -> key
    end
  end

  defp normalize_entry_key(key), do: key

  defp entry_keyword?(keyword) do
    Enum.any?(keyword, fn {key, _value} ->
      normalize_entry_key(key) in [:id, :kind, :message, :text, :title, :highlight, :color]
    end)
  end

  defp entry_map?(map) do
    map
    |> Map.keys()
    |> Enum.any?(
      &(normalize_entry_key(&1) in [:id, :kind, :message, :text, :title, :highlight, :color])
    )
  end

  defp normalize_opts(opts) when is_map(opts), do: opts

  defp normalize_opts(opts) when is_list(opts) do
    if Keyword.keyword?(opts), do: Map.new(opts), else: %{}
  end

  defp normalize_opts(_opts), do: %{}

  defp option(opts, keys, default) when is_list(keys) do
    Enum.reduce_while(keys, default, fn key, _default ->
      string_key = Atom.to_string(key)

      cond do
        Map.has_key?(opts, key) -> {:halt, Map.get(opts, key)}
        Map.has_key?(opts, string_key) -> {:halt, Map.get(opts, string_key)}
        true -> {:cont, default}
      end
    end)
  end

  defp normalize_kind(nil), do: :info
  defp normalize_kind(kind), do: kind

  defp normalize_max(value) when is_integer(value) and value > 0, do: value

  defp normalize_max(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> @default_max
    end
  end

  defp normalize_max(_value), do: @default_max

  defp normalize_duration(value) when value in [false, :infinity, "infinity"], do: false
  defp normalize_duration(value) when is_integer(value) and value > 0, do: value

  defp normalize_duration(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> @default_duration
    end
  end

  defp normalize_duration(_value), do: @default_duration

  defp ensure_entry_duration(entry, duration) do
    Map.put_new(entry, :duration, duration)
  end

  defp scheduleable_duration?(duration), do: is_integer(duration) and duration > 0

  defp message_text(nil), do: ""
  defp message_text(value) when is_binary(value), do: value
  defp message_text(value) when is_atom(value), do: Atom.to_string(value)

  defp message_text(value) do
    to_string(value)
  rescue
    Protocol.UndefinedError -> inspect(value)
  end

  defp generated_id(kind), do: "flash-#{kind_token(kind)}-#{System.unique_integer([:positive])}"

  defp indexed_id(kind, index), do: "flash-#{kind_token(kind)}-#{index_token(index)}"

  defp index_token({left, right}), do: "#{left}-#{right}"
  defp index_token(index), do: to_string(index)

  defp reject_matching(entries, key), do: Enum.reject(entries, &matches_key?(&1, key))

  defp matches_key?(entry, key) do
    flash_key(Map.get(entry, :id)) == key or flash_key(Map.get(entry, :kind)) == key
  end

  defp flash_key(nil), do: nil
  defp flash_key(value), do: value |> to_string() |> String.replace("_", "-")

  defp kind_token(kind) do
    kind
    |> flash_key()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]+/, "-")
  end

  defp public_entry(entry), do: Map.drop(entry, [:duration, :timer_token])

  defp maybe_put(map, _key, value) when value in [nil, ""], do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
