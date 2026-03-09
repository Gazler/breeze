defmodule Breeze.Router do
  @moduledoc """
  Optional routing helpers for Breeze views.

  Routing is opt-in: store a router struct in assigns and render it with
  `<.router ... />` after importing this module.
  """

  use Breeze.View

  attr :routes, :map, required: true
  attr :id, :string, default: "route"

  def router(assigns) do
    case current_route(assigns.routes) do
      nil ->
        ""

      route ->
        assigns =
          assign(assigns,
            live_id: live_id(assigns.id, route),
            view: route.view,
            start_opts: route.start_opts,
            persistent: persistent?(route),
            preload_routes: preload_routes(assigns.routes.routes, assigns.id, route.name)
          )

        ~H"""
        <live id={@live_id} view={@view} start_opts={@start_opts} persistent={@persistent}>
        </live>
        <live
          :for={route <- @preload_routes}
          id={route.live_id}
          view={route.view}
          start_opts={route.start_opts}
          persistent={route.persistent}
          preload_only={true}
        >
        </live>
        """
    end
  end

  def new(routes, opts \\ []) do
    routes = normalize_routes(routes)
    current = Keyword.get(opts, :current) || default_route(routes)
    params = Keyword.get(opts, :params, [])

    %{routes: routes, current: current, params: params}
    |> put_route_params()
  end

  def init(term, routes, opts \\ []) do
    Breeze.View.assign(term, router: new(routes, opts))
  end

  def navigate(router_or_term, route_name, params \\ [])

  def navigate(%{assigns: %{router: router}} = term, route_name, params) do
    Breeze.View.assign(term, router: navigate(router, route_name, params))
  end

  def navigate(router, route_name, params) when is_map(router) do
    %{router | current: route_name, params: params}
    |> put_route_params()
  end

  def current(%{assigns: %{router: router}}), do: router.current
  def current(%{current: current}), do: current

  def current_route(%{assigns: %{router: router}}), do: current_route(router)

  def current_route(%{routes: routes, current: current}) do
    Map.get(routes, current)
  end

  def route_names(%{assigns: %{router: router}}), do: route_names(router)
  def route_names(%{routes: routes}), do: Map.keys(routes)

  defp default_route(routes) do
    routes
    |> Map.keys()
    |> List.first()
  end

  defp put_route_params(%{routes: routes, current: current, params: params} = router) do
    case Map.fetch(routes, current) do
      {:ok, route} ->
        route = %{route | start_opts: Keyword.merge(route.base_start_opts, params)}
        %{router | routes: Map.put(routes, current, route)}

      :error ->
        router
    end
  end

  defp normalize_routes(routes) do
    routes
    |> Enum.map(&normalize_route/1)
    |> Map.new(fn route -> {route.name, route} end)
  end

  defp normalize_route({name, view}) when is_atom(view) do
    %{name: name, view: view, start_opts: [], base_start_opts: [], persistence: false}
  end

  defp normalize_route({name, {view, start_opts}}) when is_atom(view) and is_list(start_opts) do
    %{
      name: name,
      view: view,
      start_opts: start_opts,
      base_start_opts: start_opts,
      persistence: false
    }
  end

  defp normalize_route({name, {view, start_opts, route_opts}})
       when is_atom(view) and is_list(start_opts) and is_list(route_opts) do
    %{
      name: name,
      view: view,
      start_opts: start_opts,
      base_start_opts: start_opts,
      persistence: Keyword.get(route_opts, :persistence, false)
    }
  end

  defp normalize_route(%{name: name, view: view} = route) do
    start_opts = Map.get(route, :start_opts, [])

    %{
      name: name,
      view: view,
      start_opts: start_opts,
      base_start_opts: start_opts,
      persistence: Map.get(route, :persistence, false)
    }
  end

  defp live_id(base_id, %{name: name, persistence: false}),
    do: base_id <> ":" <> to_string(name)

  defp live_id(base_id, %{name: name, persistence: true}),
    do: base_id <> ":persistent:" <> to_string(name)

  defp live_id(base_id, %{name: name, persistence: :preload}),
    do: base_id <> ":persistent:" <> to_string(name)

  defp persistent?(%{persistence: value}), do: value in [true, :preload]

  defp preload_routes(routes, base_id, current_name) do
    routes
    |> Map.values()
    |> Enum.filter(&(&1.name != current_name and &1.persistence == :preload))
    |> Enum.map(fn route ->
      %{
        live_id: live_id(base_id, route),
        view: route.view,
        start_opts: route.start_opts,
        persistent: true
      }
    end)
  end
end
