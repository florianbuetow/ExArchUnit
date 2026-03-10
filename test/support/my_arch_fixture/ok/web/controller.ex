defmodule ExArchFixture.Ok.Web.Controller do
  alias ExArchFixture.Ok.Domain.Service

  def call do
    Service.run()
  end
end
