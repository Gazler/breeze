{:ok, _pid} = Breeze.RemoteInspector.ensure_server()

Breeze.Example.run(
  view: Breeze.RemoteInspector.View,
  reload: true,
  mouse: true,
  global_keybindings: Breeze.RemoteInspector.View.global_keybindings(),
  inspector: true
)
