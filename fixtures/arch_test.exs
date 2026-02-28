layers do
  layer(:bad_domain, "ExArchFixture.Bad.Domain.*")
  layer(:bad_web, "ExArchFixture.Bad.Web.*")
  layer(:cycle, "ExArchFixture.Cycle.*")

  forbid(:bad_domain, depends_on: [:bad_web])
end
