defmodule Breeze.Storybook.Stories.Blocks.TableStory do
  use Breeze.Storybook.Story

  def story do
    %{
      id: "table",
      title: "Table",
      description: "Keyboard-selectable data table with fixed columns and scrollable rows.",
      notes: [
        "Uses the built-in table implicit.",
        "Arrow keys or j/k move the selected row.",
        "The change event payload includes the selected row value, index, and scroll offset."
      ],
      source: "<.table id=\"cities\" selected=\"delhi\">...</.table>"
    }
  end

  def mount(_opts, term) do
    {:ok, assign(term, selected_city: "delhi")}
  end

  def render(assigns) do
    rows = [
      %{id: "tokyo", rank: "1", city: "Tokyo", country: "Japan", population: "37.2m"},
      %{id: "delhi", rank: "2", city: "Delhi", country: "India", population: "32.0m"},
      %{id: "shanghai", rank: "3", city: "Shanghai", country: "China", population: "28.5m"},
      %{id: "dhaka", rank: "4", city: "Dhaka", country: "Bangladesh", population: "22.4m"},
      %{id: "sao-paulo", rank: "5", city: "Sao Paulo", country: "Brazil", population: "22.4m"},
      %{
        id: "mexico-city",
        rank: "6",
        city: "Mexico City",
        country: "Mexico",
        population: "22.1m"
      },
      %{id: "cairo", rank: "7", city: "Cairo", country: "Egypt", population: "21.7m"},
      %{id: "mumbai", rank: "8", city: "Mumbai", country: "India", population: "21.2m"},
      %{id: "beijing", rank: "9", city: "Beijing", country: "China", population: "21.1m"},
      %{id: "osaka", rank: "10", city: "Osaka", country: "Japan", population: "19.0m"}
    ]

    assigns = assign(assigns, rows: rows)

    ~H"""
    <.table
      id="storybook-table"
      rows={@rows}
      selected={@selected_city}
      br-change="storybook_table_changed"
    >
      <:col :let={city} label="#" width={4} align="right">{city.rank}</:col>
      <:col :let={city} label="City" width={12}>{city.city}</:col>
      <:col :let={city} label="Country" width={12} align="center">{city.country}</:col>
      <:col :let={city} label="Population" width={10} align="right">
        <box class="text-accent">{city.population}</box>
      </:col>
    </.table>
    """
  end

  def handle_event("storybook_table_changed", %{value: value}, term) do
    {:noreply, assign(term, selected_city: value)}
  end

  def handle_event(_, _, term), do: {:noreply, term}
end
