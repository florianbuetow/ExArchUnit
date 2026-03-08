if System.get_env("ExArch_NO_CACHE") == "1" do
  ExUnit.configure(exclude: [:skip_when_no_cache])
end

ExUnit.start()
