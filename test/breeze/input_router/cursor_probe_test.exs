defmodule Breeze.InputRouter.CursorProbeTest do
  use ExUnit.Case, async: true

  alias Breeze.InputRouter.CursorProbe

  test "extracts a cursor report without consuming surrounding input" do
    assert CursorProbe.feed("", "a\e[12;34Rb") == {{12, 34}, "ab", ""}
    assert CursorProbe.feed("", "\e[A") == {nil, "\e[A", ""}
  end

  test "handles reports split at every byte boundary" do
    report = "\e[12;34R"

    for split <- 1..(byte_size(report) - 1) do
      <<prefix::binary-size(^split), suffix::binary>> = report
      assert {nil, "a", ^prefix} = CursorProbe.feed("", "a" <> prefix)
      assert {{12, 34}, "b", ""} = CursorProbe.feed(prefix, suffix <> "b")
    end
  end

  test "releases incomplete candidates when they become normal input" do
    assert CursorProbe.feed("\e[1", ";5A") == {nil, "\e[1;5A", ""}
  end

  test "waiting buffers input until a fragmented report completes the active query" do
    probe = CursorProbe.waiting()
    {probe, [], nil} = CursorProbe.consume(probe, "before")
    ref = make_ref()
    recipient = self()
    probe = CursorProbe.start(probe, ref, recipient)
    {probe, [], nil} = CursorProbe.consume(probe, "during\e[12;")

    assert {nil, ["before", "during", "after"],
            {^recipient, {:inline_cursor_reply, ^ref, {12, 3}}}} =
             CursorProbe.consume(probe, "3Rafter")
  end

  test "replacement preserves partial input and ignores the previous timer" do
    probe = CursorProbe.draining()
    old_ref = probe.ref
    {probe, [], nil} = CursorProbe.consume(probe, "a\e[1;")
    probe = CursorProbe.start(probe, make_ref(), self())
    assert {^probe, []} = CursorProbe.expire(probe, old_ref)
    {probe, [], nil} = CursorProbe.consume(probe, "5Ab")
    assert {nil, ["a", "\e[1;5Ab"]} = CursorProbe.expire(probe, probe.ref)
  end

  test "expiration releases buffered chunks and incomplete reports in their original order" do
    probe = CursorProbe.start(nil, make_ref(), self())
    {probe, [], nil} = CursorProbe.consume(probe, "a")
    {probe, [], nil} = CursorProbe.consume(probe, "b\e[12;")
    assert {nil, ["a", "b", "\e[12;"]} = CursorProbe.expire(probe, probe.ref)
    assert {nil, []} = CursorProbe.expire(nil, probe.ref)
    assert {nil, ["c"], nil} = CursorProbe.consume(nil, "c")
  end

  test "waiting expires and late reports are drained without replying to a finished query" do
    waiting = CursorProbe.waiting()
    {waiting, [], nil} = CursorProbe.consume(waiting, "typed")
    assert {nil, ["typed"]} = CursorProbe.expire(waiting, waiting.ref)

    probe = CursorProbe.draining()
    assert {nil, ["ab"], nil} = CursorProbe.consume(probe, "a\e[12;3Rb")
  end
end
