defmodule Breeze.SnapshotAssertionsTest do
  use ExUnit.Case, async: false

  alias Breeze.SnapshotAssertions

  @moduletag :tmp_dir

  setup do
    previous = System.get_env("BREEZE_UPDATE_SNAPSHOTS")
    System.delete_env("BREEZE_UPDATE_SNAPSHOTS")

    on_exit(fn ->
      if previous,
        do: System.put_env("BREEZE_UPDATE_SNAPSHOTS", previous),
        else: System.delete_env("BREEZE_UPDATE_SNAPSHOTS")
    end)

    :ok
  end

  test "normalizes both snapshot and rendered line endings before trimming spaces", %{
    tmp_dir: dir
  } do
    path = Path.join(dir, "output.ansi")
    expected = "one  \r\ntwo\nthree\r\n"
    File.write!(path, expected)

    assert :ok =
             SnapshotAssertions.assert_snapshot!(
               "one\ntwo  \r\nthree\n",
               "output.ansi",
               __ENV__.file, snapshot_dir: dir)

    assert File.read!(path) == expected
    refute File.exists?(path <> ".actual")
  end

  test "still reports real differences and writes normalized actual output", %{tmp_dir: dir} do
    path = Path.join(dir, "output.ansi")
    File.write!(path, "one\r\ntwo\r\n")

    error =
      assert_raise ExUnit.AssertionError, fn ->
        SnapshotAssertions.assert_snapshot!("one\r\nwrong\r\n", "output.ansi", __ENV__.file,
          snapshot_dir: dir
        )
      end

    assert error.message =~ "snapshot mismatch"
    assert error.message =~ "line 2, column 1"
    assert File.read!(path <> ".actual") == "one\nwrong\n"
  end
end
