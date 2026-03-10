defmodule ExArchFixture.Cycle.B do
  alias ExArchFixture.Cycle.A

  def pong do
    A.ping()
  end
end
