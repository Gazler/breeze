Application.put_env(:breeze, :example_mode, :load_only)
Application.put_env(:breeze, :example_user_host, "gazler@gazler-arch")

for file <- ~w(counter.exs docs.exs modal.exs posting.exs responsive.exs snake.exs tabs.exs) do
  Code.require_file(Path.expand("../examples/#{file}", __DIR__))
end

Breeze.Storybook.Registry.stories("storybook")
ExUnit.start()
