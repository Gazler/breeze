defmodule Breeze.Snapshot do
  @moduledoc false

  defdelegate start(view, opts \\ []), to: Breeze.Test
  defdelegate start!(view, opts \\ []), to: Breeze.Test
  defdelegate render(session, opts \\ []), to: Breeze.Test
  defdelegate render!(session, opts \\ []), to: Breeze.Test
  defdelegate input(session, key), to: Breeze.Test
  defdelegate event(session, change, event), to: Breeze.Test
  defdelegate info(session, message), to: Breeze.Test
  defdelegate metadata(session), to: Breeze.Test
  defdelegate stop(session), to: Breeze.Test
end
