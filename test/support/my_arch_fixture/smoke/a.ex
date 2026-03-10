defmodule ExArchFixture.Smoke.A do
  alias ExArchFixture.Smoke.B

  def run, do: B.call()
end
