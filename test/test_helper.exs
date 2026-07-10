ExUnit.start()
Code.require_file("../test_support/snapshot_assertions.ex", __DIR__)
Code.require_file("support/wait_until.ex", __DIR__)
Code.require_file("support/storybook_case.ex", __DIR__)
Code.require_file("support/live_view_case.ex", __DIR__)

Application.put_env(:breeze, :example_mode, :load_only)
Application.put_env(:breeze, :example_user_host, "gazler@gazler-arch")

for file <- ~w(counter.exs docs.exs modal.exs posting.exs snake.exs tabs.exs) do
  Code.require_file(Path.expand("../examples/#{file}", __DIR__))
end

_ = Breeze.Storybook.Registry.stories("storybook")
