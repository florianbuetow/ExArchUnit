defmodule ExArchFixture.Cycle.A do
  alias ExArchFixture.Cycle.B

  def ping do
    B.pong()
  end
end
