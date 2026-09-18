defmodule Breeze.ErrorView.ClipboardNoticeTest do
  use ExUnit.Case, async: true

  test "copy notice uses the view's supported boolean" do
    terminal = %Termite.Terminal{size: %{width: 80, height: 24}}

    assigns =
      Breeze.Server.Error.crash_info(:error, RuntimeError.exception("boom"), [])
      |> Map.put(:notice, :clipboard_sent)
      |> then(&Breeze.ErrorView.render_assigns(__MODULE__, &1, terminal.size))

    for {supported, message} <- [
          {true, "Sent crash details to terminal clipboard."},
          {false, "Copy attempted; OSC 52 support unknown. Press p to print details."}
        ] do
      output =
        Breeze.Renderer.render_to_string(
          Breeze.ErrorView,
          Map.put(assigns, :breeze, %{clipboard: %{supported: supported}}),
          terminal: terminal
        )

      assert output =~ message
    end

    # Standalone renders without session metadata also get the boolean default.
    output = Breeze.Renderer.render_to_string(Breeze.ErrorView, assigns, terminal: terminal)
    assert output =~ "OSC 52 support unknown"
  end
end
