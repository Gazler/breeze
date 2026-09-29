defmodule Breeze.CrashSafetyTest do
  use ExUnit.Case, async: true

  defmodule BrokenView do
    use Breeze.View
    def mount(_opts, term), do: {:ok, term}
    def render(_assigns), do: raise("render failed")
  end

  test "both child rendering paths retain structured failures without killing the child" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}
    pid = start_supervised!({Breeze.ChildServer, view: BrokenView, terminal: terminal})

    for callback <- [:render, :render_snapshot] do
      assert {:crash, crash} = apply(Breeze.ChildServer, callback, [pid, [terminal: terminal]])
      assert %RuntimeError{message: "render failed"} = crash.reason
      assert [{BrokenView, :render, 1, _} | _] = crash.stacktrace
      assert Process.alive?(pid)
    end
  end

  test "crash details and screen accept argument-list stack frames with unavailable structs" do
    reason = UndefinedFunctionError.exception(module: MissingView, function: :render, arity: 1)
    stack = [{MissingView, :render, [%{__struct__: MissingScope, org_id: 77}], []}]
    crash = Breeze.Server.Error.crash_info(:error, reason, stack)
    assert Breeze.ErrorView.details_text(MissingView, crash) =~ "render/1"
    assigns = Breeze.ErrorView.render_assigns(MissingView, crash, %{width: 100, height: 30})

    output =
      Breeze.Renderer.render_to_string(Breeze.ErrorView, assigns,
        terminal: %Termite.Terminal{size: %{width: 100, height: 30}}
      )

    assert output =~ "Breeze Error"
  end
end
