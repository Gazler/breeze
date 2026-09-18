defmodule Breeze.Clipboard.ProbeTest do
  use ExUnit.Case, async: true
  alias Breeze.Clipboard.Probe

  test "DA1 advertises support without reading the clipboard" do
    assert Probe.query() == "\e[c"
    {probe, "", []} = Probe.feed(Probe.new(), "\e[?62;22;52c")
    assert probe.clipboard == %{osc52: :supported, supported: true}
  end

  test "fragmented replies preserve surrounding keyboard input" do
    {probe, "a", []} = Probe.feed(Probe.new(), "a\e[?62;")
    {probe, "b\e[A", []} = Probe.feed(probe, "52cb\e[A")
    assert probe.clipboard == %{osc52: :supported, supported: true}
    assert probe.buffer == ""
  end

  test "XTGETTCAP fallback requires an OSC 52 Ms value" do
    {probe, "", [query]} = Probe.feed(Probe.new(), "\e[?62;22c")
    assert query == "\eP+q4d73\e\\"
    encoded = Base.encode16("\e]52;%p1%s;%p2%s\a")
    {probe, "", []} = Probe.feed(probe, "\eP1+r4D73=" <> encoded <> "\e")
    {probe, "z", []} = Probe.feed(probe, "\\z")
    assert probe.clipboard == %{osc52: :supported, supported: true}
  end

  test "negative and unrelated capabilities stay unknown" do
    for reply <- ["\eP0+r4d73\e\\", "\eP1+r4d73=6869\e\\"] do
      {probe, "", []} = Probe.feed(Probe.new(), reply)
      assert probe.clipboard == %{osc52: :unknown, supported: false}
    end

    {_, input, []} = Probe.feed(Probe.new(), "\eP1+r544e=787465726d\e\\")
    assert input == "\eP1+r544e=787465726d\e\\"
  end

  test "late replies are swallowed but cannot change an expired result" do
    {probe, "x", []} = Probe.feed(Probe.expire(Probe.new()), "\e[?62;52cx")
    assert probe.clipboard == %{osc52: :unknown, supported: false}
  end

  test "incomplete Escape is released and incomplete replies are discarded" do
    {probe, "", []} = Probe.feed(Probe.new(), "\e")
    assert {_, "\e"} = Probe.flush(probe)
    {probe, "", []} = Probe.feed(Probe.new(), "\e[?62;")
    assert {_, ""} = Probe.flush(probe)
  end
end
