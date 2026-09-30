defmodule Breeze.ErrorView.BehaviourTest do
  use ExUnit.Case, async: true

  alias Breeze.Server.Error

  defmodule MinimalView do
    use Breeze.ErrorView

    @impl Breeze.View
    def render(assigns), do: ~H"<box>{inspect(@reason)}</box>"
  end

  defmodule CustomView do
    use Breeze.ErrorView

    @impl Breeze.ErrorView
    def prepare_crash(view, crash, size) do
      Map.merge(crash, %{focused: nil, prepared_for: {view, size}})
    end

    @impl Breeze.ErrorView
    def render_assigns(view, crash, size) do
      %{view: view, crash: crash, size: size, breeze: %{custom: true}}
    end

    @impl Breeze.ErrorView
    def details_text(view, crash), do: "#{inspect(view)}: #{Exception.message(crash.reason)}"

    @impl Breeze.View
    def render(assigns), do: ~H"<box>{inspect(@crash.reason)}</box>"
  end

  test "custom callbacks prepare state, build assigns, and format details" do
    config = Error.normalize(view: CustomView, keybindings: [{"r", "Restart", :restart}])
    size = %{width: 80, height: 24}
    crash = Error.crash_info(:error, RuntimeError.exception("boom"), [])

    prepared = Error.prepare_crash(config, __MODULE__, crash, size)
    assert prepared.prepared_for == {__MODULE__, size}
    assert prepared.focused == nil

    assigns = Error.render_assigns(config, __MODULE__, prepared, size)
    assert assigns.crash == prepared
    assert assigns.size == size
    assert assigns.breeze.custom
    assert [%{key: "r", label: "Restart"}] = assigns.breeze.keybindings
    assert Error.details_text(config, __MODULE__, prepared) == "#{inspect(__MODULE__)}: boom"
  end

  test "a render-only error view retains the default callbacks" do
    config = Error.normalize(view: MinimalView)
    size = %{width: 80, height: 24}
    crash = Error.crash_info(:error, RuntimeError.exception("boom"), [])

    prepared = Error.prepare_crash(config, __MODULE__, crash, size)
    assert prepared == Breeze.ErrorView.prepare_crash(__MODULE__, crash, size)

    assigns = Error.render_assigns(config, __MODULE__, prepared, size)

    assert Map.delete(assigns, :breeze) ==
             Breeze.ErrorView.render_assigns(__MODULE__, prepared, size)

    assert assigns.breeze.keybindings == []

    assert Error.details_text(config, __MODULE__, prepared) ==
             Breeze.ErrorView.details_text(__MODULE__, prepared)
  end
end
