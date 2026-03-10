defmodule ExArchFixture.Behaviour.Impl do
  @behaviour ExArchFixture.Behaviour.Contract

  @impl true
  def ping, do: :ok
end
