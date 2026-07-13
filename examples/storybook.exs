defmodule StorybookExample do
  use Breeze.View
end

Breeze.Example.run(
  [
    view: Breeze.Storybook,
    start_opts: [directory: "storybook"],
    theme: Breeze.Theme.builtin(:gruvbox),
    hide_cursor: true,
    mouse: true,
    reload: true,
    inspector: true
  ],
  keep_alive: :infinity
)
