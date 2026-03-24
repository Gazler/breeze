defmodule StorybookExample do
  use Breeze.View
end

Breeze.Example.run(
  [
    view: Breeze.Storybook.View,
    start_opts: [directory: "storybook"],
    theme: Breeze.Theme.builtin(:gruvbox),
    hide_cursor: true,
    reload: true,
    mouse: [mode: :motion],
    inspector: true,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
