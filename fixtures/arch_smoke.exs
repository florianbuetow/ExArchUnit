layers do
  layer(:smoke_a, "ExArchFixture.Smoke.A")
  layer(:smoke_b, "ExArchFixture.Smoke.B")

  forbid(:smoke_a, depends_on: [:smoke_b])
end
