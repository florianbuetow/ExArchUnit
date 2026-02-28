defmodule ExArch.Rule do
  @moduledoc """
  Struct representing a layer dependency rule (`:allow` or `:forbid`).
  """

  @type t :: %__MODULE__{
          type: :forbid | :allow,
          source: atom(),
          depends_on: [atom()]
        }

  defstruct [:type, :source, depends_on: []]
end
