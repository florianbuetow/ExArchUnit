layers do
  layer(:fixtures_web, "ExArchFixture.*.Web.*")
  layer(:fixtures_domain, "ExArchFixture.*.Domain.*")

  allow(:fixtures_web, depends_on: [:fixtures_domain])
  forbid(:fixtures_domain, depends_on: [:fixtures_web])
end
