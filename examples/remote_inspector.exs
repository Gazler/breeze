{:ok, _pid} = Breeze.RemoteInspector.ensure_server()

Breeze.Example.run(
  view: Breeze.RemoteInspector.View,
  reload: true,
  mouse: true,
  inspector: false
)
