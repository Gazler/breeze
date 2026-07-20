defmodule Breeze.RemoteInspector.PageHost do
  @moduledoc false

  use Breeze.Component

  alias Breeze.RemoteInspector.Pages
  alias Breeze.Template

  def pages(active) do
    active
    |> active_pages()
    |> Pages.validate_discovered()
  end

  def normalize_tab(panel_tab, custom_pages) do
    available = Pages.reserved_ids() ++ Enum.map(custom_pages, & &1.id)
    if panel_tab in available, do: panel_tab, else: "overview"
  end

  def context(assigns, active) do
    context(assigns, active, active_source(assigns))
  end

  def context(assigns, active, scope) do
    %{
      source_server_pid: source_server_pid(active),
      breeze: Map.get(assigns, :breeze, %{}),
      page_states: Map.get(assigns, :custom_page_states, %{}),
      page_state_scope: scope
    }
  end

  def page_assigns(page, context) do
    state =
      context
      |> Map.get(:page_states, %{})
      |> Map.get(page_state_key(context, page.id), %{})

    page_data =
      page
      |> Map.get(:assigns, %{})
      |> Map.merge(state)

    host_data =
      context
      |> Map.drop([:page_states, :page_state_scope])
      |> Map.merge(%{
        id: page.id,
        label: page.label,
        page: page,
        page_ref: {Map.get(context, :page_state_scope), page.id}
      })

    Map.merge(page_data, host_data)
  end

  attr :page, :map, required: true
  attr :context, :map, required: true

  def render(assigns) do
    page_assigns = page_assigns(assigns.page, assigns.context)
    page_error = Map.get(page_assigns, :custom_page_error)

    if page_error do
      page_message(page_assigns, page_error)
    else
      render_page(assigns.page, page_assigns)
    end
  end

  defp render_page(page, page_assigns) do
    case safe_page_call(fn -> render_available_page(page, page_assigns) end) do
      {:ok, rendered} -> rendered
      {:error, reason} -> page_message(page_assigns, page_failure_message(reason))
    end
  end

  defp render_available_page(page, page_assigns) do
    if callback_exported?(page.module, :render, 1) do
      page.module
      |> apply(:render, [page_assigns])
      |> normalize_render(page_assigns)
    else
      page_message(
        page_assigns,
        "remote inspector page #{inspect(page.module)} is unavailable on this " <>
          "inspector node; start the inspector from a project that includes the page's package"
      )
    end
  end

  def delegate_event(event, payload, term, active) do
    scope = active_source(term.assigns)

    case custom_page_by_id(active, Map.get(term.assigns, :panel_tab)) do
      nil -> {:noreply, term}
      page -> invoke_callback(page, term, active, scope, :handle_event, [event, payload])
    end
  end

  def delegate_info({scope, page_id}, message, term) when is_binary(page_id) do
    active = source_entry(term.assigns, scope)

    case custom_page_by_id(active, page_id) do
      nil -> {:noreply, term}
      page -> invoke_callback(page, term, active, scope, :handle_info, [message])
    end
  end

  def delegate_info(page_id, message, term) when is_binary(page_id) do
    delegate_info({active_source(term.assigns), page_id}, message, term)
  end

  def delegate_info(_page_ref, _message, term), do: {:noreply, term}

  defp active_pages(%{snapshot: %{pages: pages}}) when is_list(pages), do: pages
  defp active_pages(_active), do: []

  defp source_server_pid(%{snapshot: %{source: %{server_pid: pid}}}) when is_pid(pid), do: pid
  defp source_server_pid(%{source: %{pid: pid}}) when is_pid(pid), do: pid
  defp source_server_pid(_active), do: nil

  defp active_source(assigns) do
    Map.get(assigns, :active_source) ||
      Map.get(assigns, :latest_source) ||
      Map.get(assigns, :source_server_pid)
  end

  defp page_state_key(context, page_id) do
    {Map.get(context, :page_state_scope), page_id}
  end

  defp custom_page_by_id(active, page_id) when is_binary(page_id) do
    active
    |> pages()
    |> Enum.find(&(&1.id == page_id))
  end

  defp custom_page_by_id(_active, _page_id), do: nil

  defp invoke_callback(page, term, active, scope, callback, args) do
    result =
      safe_page_call(fn ->
        call_page_callback(page, term, active, scope, callback, args)
      end)

    case result do
      {:ok, reply} ->
        reply

      {:error, reason} ->
        callback_error(term, page, scope, page_failure_message(reason))
    end
  end

  defp call_page_callback(page, term, active, scope, callback, args) do
    if callback_exported?(page.module, callback, length(args) + 1) do
      assigns = page_assigns(page, context(term.assigns, active, scope))

      page.module
      |> apply(callback, args ++ [assigns])
      |> normalize_callback_reply(term, page, scope)
    else
      {:noreply, term}
    end
  end

  defp normalize_callback_reply({:noreply, state}, term, page, scope) when is_map(state) do
    {:noreply, put_page_state(term, page.id, scope, state)}
  end

  defp normalize_callback_reply(:noreply, term, _page, _scope), do: {:noreply, term}

  defp normalize_callback_reply(reply, term, page, scope) do
    callback_error(
      term,
      page,
      scope,
      "remote inspector page returned an invalid callback result: #{inspect(reply)}"
    )
  end

  defp callback_error(term, page, scope, message) do
    {:noreply, put_page_error(term, page.id, scope, message)}
  end

  defp put_page_error(term, page_id, scope, message) do
    key = {scope, page_id}

    current =
      term.assigns
      |> Map.get(:custom_page_states, %{})
      |> Map.get(key, %{})

    put_page_state(term, page_id, scope, Map.put(current, :custom_page_error, message))
  end

  defp put_page_state(term, page_id, scope, state) do
    key = {scope, page_id}

    custom_page_states =
      term.assigns
      |> Map.get(:custom_page_states, %{})
      |> Map.put(key, state)

    assign(term, custom_page_states: custom_page_states)
  end

  defp source_entry(%{snapshots: snapshots}, scope), do: Map.get(snapshots, scope)
  defp source_entry(_assigns, _scope), do: nil

  defp callback_exported?(module, callback, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, callback, arity)
  end

  defp safe_page_call(fun) do
    {:ok, fun.()}
  rescue
    error -> {:error, Exception.message(error)}
  catch
    kind, reason -> {:error, inspect({kind, reason})}
  end

  defp page_failure_message(reason), do: "remote inspector page failed: #{reason}"

  defp normalize_render({%Template{} = template, assigns}, _page_assigns) do
    {template, assigns}
  end

  defp normalize_render(%Template{} = template, page_assigns) do
    {template, page_assigns}
  end

  defp normalize_render(content, page_assigns) do
    page_content(
      Map.put(page_assigns, :content, Template.render_to_string(content, page_assigns))
    )
  end

  defp page_content(assigns) do
    ~H"""
    <box class="width-full height-full padding-top-1 overflow-hidden">{@content}</box>
    """
  end

  defp page_message(assigns, message) do
    assigns = Map.put(assigns, :message, message)

    ~H"""
    <box class="width-full height-full padding-top-1 overflow-hidden text-error">{@message}</box>
    """
  end
end
