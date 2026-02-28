layers do
  layer(:ok_web, "ExArchFixture.Ok.Web.*")
  layer(:ok_domain, "ExArchFixture.Ok.Domain.*")

  allow(:ok_web, depends_on: [:ok_domain])
  forbid(:ok_domain, depends_on: [:ok_web])
end
