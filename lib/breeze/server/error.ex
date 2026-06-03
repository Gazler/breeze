defmodule Breeze.Server.Error do
  @moduledoc false

  @actions [:restart, :stop, :copy_details]

  def normalize(opts) when is_list(opts) do
    [
      view: Keyword.get(opts, :view, Breeze.ErrorView),
      keybindings: normalize_action_keybindings(Keyword.get(opts, :keybindings, []))
    ]
  end

  def normalize(_opts), do: normalize([])

  def view(config) when is_list(config), do: Keyword.get(config, :view, Breeze.ErrorView)
  def view(_config), do: Breeze.ErrorView

  def prepare_crash(config, root_view, crash, size) do
    view = view(config)

    if exported?(view, :prepare_crash, 3) do
      view.prepare_crash(root_view, crash, size)
    else
      Breeze.ErrorView.prepare_crash(root_view, crash, size)
    end
  end

  def render_assigns(config, root_view, crash, size) do
    view = view(config)

    assigns =
      if exported?(view, :render_assigns, 3) do
        view.render_assigns(root_view, crash, size)
      else
        Breeze.ErrorView.render_assigns(root_view, crash, size)
      end

    put_keybindings_assign(assigns, config)
  end

  def handle_input(config, root_view, crash, input, size) do
    case view(config) do
      Breeze.ErrorView ->
        Breeze.ErrorView.handle_input(root_view, crash, input, size)

      _view ->
        dispatch_keybinding(config, crash, input)
    end
  end

  def details_text(config, root_view, crash) do
    view = view(config)

    if exported?(view, :details_text, 2) do
      view.details_text(root_view, crash)
    else
      Breeze.ErrorView.details_text(root_view, crash)
    end
  end

  defp dispatch_keybinding(config, crash, input) do
    case keybinding_action(input, keybindings(config)) do
      :restart -> :restart
      :stop -> :stop
      :copy_details -> {:copy_details, crash}
      :continue -> :ignore
    end
  end

  defp keybinding_action({:key, key}, keybindings) do
    Breeze.Keybindings.dispatch(%{"key" => key}, keybindings, nil)
  end

  defp keybinding_action(_input, _keybindings), do: :continue

  defp put_keybindings_assign(assigns, config) do
    keybindings = Breeze.Keybindings.visible(keybindings(config))

    Map.update(assigns, :breeze, %{keybindings: keybindings}, fn
      breeze when is_map(breeze) -> Map.put(breeze, :keybindings, keybindings)
      _other -> %{keybindings: keybindings}
    end)
  end

  defp keybindings(config) when is_list(config), do: Keyword.get(config, :keybindings, [])
  defp keybindings(_config), do: []

  defp normalize_action_keybindings(keybindings) do
    keybindings
    |> List.wrap()
    |> Enum.flat_map(fn binding ->
      case normalize_action_keybinding(binding) do
        %{key: key, label: label, action: action} ->
          handler = fn _event, _term -> action end
          [%{key: key, label: label, handler: handler}]

        nil ->
          []
      end
    end)
  end

  defp normalize_action_keybinding({key, action}) when action in @actions do
    %{key: to_string(key), label: nil, action: action}
  end

  defp normalize_action_keybinding({key, label, action})
       when is_binary(label) and action in @actions do
    %{key: to_string(key), label: label, action: action}
  end

  defp normalize_action_keybinding(%{key: key, action: action} = binding)
       when action in @actions do
    %{key: to_string(key), label: Map.get(binding, :label), action: action}
  end

  defp normalize_action_keybinding(%{"key" => key, "action" => action} = binding)
       when action in @actions do
    %{key: to_string(key), label: Map.get(binding, "label"), action: action}
  end

  defp normalize_action_keybinding(_binding), do: nil

  defp exported?(view, function, arity) do
    Code.ensure_loaded?(view) and function_exported?(view, function, arity)
  end
end
