defmodule Breeze.Runtime.State.View do
  @moduledoc false

  defstruct version: 1, term: nil, children: %{}

  @type child :: %{
          required(:view) => module(),
          required(:start_opts) => keyword(),
          required(:assigns) => map(),
          optional(:persistent) => boolean(),
          required(:state) => t()
        }

  @type t :: %__MODULE__{
          version: pos_integer(),
          term: Breeze.Term.t(),
          children: %{optional(String.t()) => child()}
        }
end
