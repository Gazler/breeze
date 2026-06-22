defmodule Mix.Tasks.BreezeInspectorTaskTest do
  use ExUnit.Case, async: true

  defmodule LLMInspectorPage do
    use Breeze.View

    def render(assigns) do
      ~H"<box>LLM</box>"
    end
  end

  defmodule NotAnInspectorPage do
  end

  test "run opts enable reload and remote inspector self-inspection" do
    assert Mix.Tasks.Breeze.Inspector.run_opts() == [
             view: Breeze.RemoteInspector.View,
             reload: true,
             theme: :system,
             mouse: true,
             global_keybindings: Breeze.RemoteInspector.View.global_keybindings(),
             inspector: true
           ]
  end

  test "run opts can pass extra remote inspector pages" do
    opts = Mix.Tasks.Breeze.Inspector.run_opts(pages: [LLMInspectorPage])

    assert Keyword.get(opts, :view) == Breeze.RemoteInspector.View
    assert Keyword.get(opts, :start_opts) == [remote_inspector_pages: [LLMInspectorPage]]
  end

  test "page modules resolve from --page option values" do
    name = inspect(LLMInspectorPage)

    assert Mix.Tasks.Breeze.Inspector.page_modules(page: name, page: "Elixir." <> name) == [
             LLMInspectorPage,
             LLMInspectorPage
           ]
  end

  test "sample LLM inspector page can be passed with --page" do
    assert Mix.Tasks.Breeze.Inspector.page_modules(page: "Breeze.RemoteInspector.Pages.LLM") == [
             Breeze.RemoteInspector.Pages.LLM
           ]
  end

  test "page modules must export render/1" do
    assert_raise Mix.Error, ~r/must export render\/1/, fn ->
      Mix.Tasks.Breeze.Inspector.page_module!(inspect(NotAnInspectorPage))
    end
  end

  test "page module values cannot be blank" do
    assert_raise Mix.Error, ~r/cannot be blank/, fn ->
      Mix.Tasks.Breeze.Inspector.page_module!(" ")
    end
  end

  test "distribution error message prompts user to start epmd for nodistribution" do
    reason =
      {{:shutdown, {:failed_to_start_child, :net_kernel, {:EXIT, :nodistribution}}},
       {:child, :undefined, :net_sup_dynamic,
        {:erl_distribution, :start_link,
         [
           %{
             name: :inspector,
             supervisor: :net_sup_dynamic,
             net_tickintensity: 4,
             net_ticktime: 60,
             name_domain: :shortnames,
             clean_halt: false
           }
         ]}, :permanent, false, 1000, :supervisor, [:erl_distribution]}}

    message = Mix.Tasks.Breeze.Inspector.distribution_error_message(reason)

    assert message =~ "epmd appears to be unavailable"
    assert message =~ "epmd -daemon"
    assert message =~ "mix breeze.inspector"
    assert message =~ "restart your application"
  end

  test "distribution error message preserves unexpected reasons" do
    assert Mix.Tasks.Breeze.Inspector.distribution_error_message(:some_other_reason) ==
             "breeze.inspector could not start distributed Erlang as inspector: :some_other_reason"
  end

  test "normalize_connect_target keeps explicit host" do
    assert Mix.Tasks.Breeze.Inspector.normalize_connect_target("app@host.example") ==
             :"app@host.example"
  end

  test "normalize_connect_target expands short name with current host" do
    host =
      case String.split(to_string(node()), "@", parts: 2) do
        [_name, current_host] when current_host != "" ->
          current_host

        _ ->
          case :inet.gethostname() do
            {:ok, hostname} -> to_string(hostname)
            _ -> "localhost"
          end
      end

    assert Mix.Tasks.Breeze.Inspector.normalize_connect_target("app") ==
             String.to_atom("app@#{host}")
  end
end
