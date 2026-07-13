defmodule Breeze.Storybook.Stories.Blocks.TreeStory do
  use Breeze.Storybook.Story

  @nodes [
    %{
      id: "root",
      label: "breeze",
      children: [
        %{
          id: "lib",
          label: "lib",
          children: [
            %{id: "blocks", label: "blocks.ex"},
            %{id: "view", label: "view.ex"}
          ]
        },
        %{
          id: "test",
          label: "test",
          children: [
            %{id: "blocks-test", label: "blocks_test.exs"},
            %{id: "view-test", label: "view_test.exs"}
          ]
        },
        %{id: "mix", label: "mix.exs"}
      ]
    }
  ]

  def story do
    %{
      id: "tree",
      title: "Tree",
      description: "Keyboard-navigable hierarchical data with expandable branches.",
      notes: [
        "Arrow keys or h/j/k/l navigate, expand, and collapse branches.",
        "The story keeps selected and expanded values in view state using the tree change payload."
      ],
      source:
        ~S(<.tree id="files" nodes={@nodes} selected={@selected} expanded={@expanded} br-change="select_node" />)
    }
  end

  def mount(_opts, term) do
    {:ok,
     term
     |> focus("storybook-tree")
     |> assign(selected: "root", expanded: ["root", "lib"])}
  end

  def render(assigns) do
    assigns = assign(assigns, nodes: @nodes)

    ~H"""
    <.tree
      id="storybook-tree"
      nodes={@nodes}
      selected={@selected}
      expanded={@expanded}
      br-change="storybook_tree_changed"
      class="width-42 height-full bg-panel"
    />
    """
  end

  def handle_event(
        "storybook_tree_changed",
        %{value: value, expanded: expanded},
        term
      ) do
    {:noreply, assign(term, selected: value, expanded: expanded)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
