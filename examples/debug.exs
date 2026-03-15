Breeze.Example.run(
  [
    view: Breeze.Debug,
    global_keybindings: [{"q", fn _event, term -> {:stop, term} end}]
  ],
  keep_alive: :infinity
)
