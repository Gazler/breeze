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

    assert {nil, ""} =
             Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})
  end

  test "late replies complete a timed out probe during its drain window" do
    terminal = terminal()
    probe = Session.start_probe(terminal)
    {probe, ""} = Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})
    {probe, ""} = Session.feed(probe, replies())
    assert Probe.probe_status(terminal) == :ready

    assert {nil, ""} =
             Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})
  end

  test "timeout falls back and releases a pending escape key" do
    terminal = terminal()
    probe = Session.start_probe(terminal)
    {probe, ""} = Session.feed(probe, "\e")
    {probe, ""} = Session.handle_timeout(probe, {:theme_probe_timeout, probe.key, probe.ref})

    assert {nil, "\e"} =
             Session.handle_timeout(probe, {:theme_probe_drain_timeout, probe.key, probe.ref})

    assert Probe.probe_status(terminal) == :unavailable
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
