defmodule Breeze.Theme.Probe.SessionTest do
  use ExUnit.Case, async: true

  alias Breeze.Theme.Probe
  alias Breeze.Theme.Probe.Session

  defmodule Adapter do
    def write(owner, bytes) do
      send(owner, {:output, bytes})
      {:ok, owner}
    end
  end

  defp terminal, do: %Termite.Terminal{reader: make_ref(), adapter: {Adapter, self()}}

  defp replies do
    "\e]10;rgb:eeee/eeee/eeee\e\\\e]11;rgb:1111/1111/1111\a" <>
      Enum.map_join(1..6, &"\e]4;#{&1};rgb:aaaa/bbbb/cccc\e\\")
  end

  for outcome <- [:timeout, :complete] do
    @outcome outcome

    test "consumes late replies after #{@outcome}, at every packet boundary" do
      terminal = terminal()
      probe = Session.start_probe(terminal, timeout: 60_000)

      {probe, ""} =
        case @outcome do
          :timeout -> Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})
          :complete -> Session.feed(probe, replies())
        end

      {probe, ""} =
        Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})

      palette = Probe.cached_terminal_palette(terminal)

      for terminator <- ["\a", "\e\\"], command <- ["10", "11", "4;1"] do
        reply = "\e]#{command};rgb:1111/2222/3333" <> terminator

        for split <- 0..byte_size(reply) do
          <<first::binary-size(^split), rest::binary>> = reply
          {next, "/before"} = Session.feed(probe, "/before" <> first)
          assert {_, "/after"} = Session.feed(next, rest <> "/after")
        end
      end

      assert Probe.cached_terminal_palette(terminal) == palette
    end

    test "retains partial replies across #{@outcome} drain expiry" do
      probe = Session.start_probe(terminal(), timeout: 60_000)

      {probe, ""} =
        case @outcome do
          :timeout -> Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})
          :complete -> Session.feed(probe, replies())
        end

      reply = "\e]10;rgb:eeee/eeee/eeee\e\\"

      for split <- 1..(byte_size(reply) - 1) do
        <<first::binary-size(^split), rest::binary>> = reply
        {next, ""} = Session.feed(probe, first)

        {next, ""} =
          Session.handle_timeout(next, {:theme_probe_drain_timeout, next.key, next.ref})

        assert {_, "/filter"} = Session.feed(next, rest <> "/filter")
      end
    end
  end

  test "custom transports can probe and preserve input around fragmented OSC replies" do
    terminal = terminal()
    probe = Session.start_probe(terminal, timeout: 1000)
    assert_receive {:output, query}
    assert query =~ "\e]10;?"
    assert query =~ "\e]4;6;?"

    {probe, input} =
      for <<byte <- "x" <> replies() <> "y">>, reduce: {probe, ""} do
        {probe, input} ->
          {probe, remaining} = Session.feed(probe, <<byte>>)
          {probe, input <> remaining}
      end

    assert input == "xy"
    assert probe.status == :draining
    assert Probe.probe_status(terminal) == :ready
    assert Probe.cached_terminal_palette(terminal).background == {17, 17, 17}

    assert {%{status: :closed, finished?: true}, ""} =
             Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})
  end

  test "late replies complete a timed out probe during its drain window" do
    terminal = terminal()
    probe = Session.start_probe(terminal)
    {probe, ""} = Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})
    {probe, ""} = Session.feed(probe, replies())
    assert Probe.probe_status(terminal) == :ready

    assert {%{status: :closed, finished?: true}, ""} =
             Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})
  end

  test "timeout falls back and releases a pending escape key" do
    terminal = terminal()
    probe = Session.start_probe(terminal)
    {probe, ""} = Session.feed(probe, "\e")
    {probe, ""} = Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})

    {probe, ""} =
      Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})

    assert probe.status == :closed
    refute probe.finished?
    ref = probe.escape_ref
    assert_receive {:theme_probe_escape_timeout, _, ^ref} = message
    {probe, "\e"} = Session.handle_timeout(probe, message)
    assert {^probe, ""} = Session.handle_timeout(probe, message)

    assert Probe.probe_status(terminal) == :unavailable
  end

  test "a closed probe preserves ordinary input and ignores a stale Escape timeout" do
    probe = Session.start_probe(terminal(), timeout: 60_000)
    {probe, ""} = Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})

    {probe, ""} =
      Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})

    {probe, ""} = Session.feed(probe, "\e")
    stale_message = {:theme_probe_escape_timeout, probe.key, probe.escape_ref}
    {probe, "\e[A"} = Session.feed(probe, "[A")
    assert {^probe, ""} = Session.handle_timeout(probe, stale_message)

    data = "\x03/filter\e]52;c;clipboard\a"
    assert {_, ^data} = Session.feed(probe, data)
    assert {_, ""} = Session.feed(probe, replies())
    assert Probe.probe_status(probe.terminal) == :unavailable
  end

  test "unrelated OSC replies and ordinary input pass through unchanged" do
    probe = Session.start_probe(terminal())
    data = "\e[A\e]52;c;hello\aabc"
    assert {_probe, ^data} = Session.feed(probe, data)

    assert {^probe, ""} =
             Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, make_ref()})

    assert {nil, ^data} = Session.feed(nil, data)
  end
end
