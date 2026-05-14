defmodule Breeze.Theme do
  @moduledoc """
  Theme helpers for semantic Breeze color tokens.

  Themes can be:

  * `:system16` for legacy ANSI-slot-based themes
  * `:system` for richer themes derived from the terminal palette when available
  * custom maps/keywords/structs with explicit defaults, palette entries, and extras
  """

  @enforce_keys [:defaults, :palette, :extras]
  defstruct name: nil,
            mode: :custom,
            dark: nil,
            defaults: %{},
            palette: %{},
            extras: %{},
            variables: %{},
            terminal_palette: nil

  @reserved_keys ~w(name mode type dark defaults palette extras variables terminal_palette)a
  @default_aliases %{
    text: :foreground_color,
    fg: :foreground_color,
    bg: :background_color,
    background: :background_color,
    stroke: :border_color,
    border: :border_color
  }
  @palette_aliases %{fg: :text}
  @legacy_palette_keys ~w(muted primary secondary warning error success accent surface panel)a

  @type rgb :: {0..255, 0..255, 0..255}
  @type color :: non_neg_integer() | rgb() | String.t()
  @type terminal_palette :: %{optional(integer() | atom()) => color()}

  @type t :: %__MODULE__{
          name: String.t() | nil,
          mode: :custom | :system | :system16,
          dark: boolean() | nil,
          defaults: %{optional(atom()) => color()},
          palette: %{optional(atom()) => color()},
          extras: %{optional(atom()) => color()},
          variables: %{optional(String.t()) => term()},
          terminal_palette: terminal_palette() | nil
        }

  @spec default(keyword()) :: t()
  def default(opts \\ []), do: system16(opts)

  @spec builtin(atom(), atom() | nil) :: t()
  def builtin(name, variant \\ nil),
    do: Breeze.Theme.Builtin.fetch!(name, variant)

  @spec default_cycle() :: [atom()]
  def default_cycle do
    [
      :system16,
      :system,
      :nebula,
      :catppuccin,
      :dracula,
      :gruvbox,
      :nord,
      :solarized_light,
      :solarized_dark
    ]
  end

  @spec resolve_theme(atom() | {term(), term()}) :: {term(), term()}
  def resolve_theme({name, theme}), do: {name, theme}
  def resolve_theme(:system16), do: {:system16, :system16}
  def resolve_theme(:system), do: {:system, :system}
  def resolve_theme(name) when is_atom(name), do: {name, builtin(name)}

  @spec next_theme(term(), [atom() | {term(), term()}]) :: {term(), term()} | nil
  def next_theme(current, themes \\ default_cycle()) when is_list(themes) do
    case Enum.map(themes, &resolve_theme/1) do
      [] ->
        nil

      entries ->
        index = Enum.find_index(entries, fn {name, _theme} -> name == current end)
        next_index = if is_integer(index), do: rem(index + 1, length(entries)), else: 0
        Enum.at(entries, next_index)
    end
  end

  @spec defaults_enabled?(term()) :: boolean()
  def defaults_enabled?(theme), do: theme not in [nil, false]

  @spec requested_system?(term()) :: boolean()
  def requested_system?(:system), do: true
  def requested_system?(%__MODULE__{mode: :system}), do: true
  def requested_system?(%__MODULE__{variables: %{requested_theme: :system}}), do: true

  def requested_system?(theme) when is_list(theme) do
    if Keyword.keyword?(theme), do: requested_system?(Map.new(theme)), else: false
  end

  def requested_system?(theme) when is_map(theme) do
    variables = Map.get(theme, :variables) || Map.get(theme, "variables") || %{}

    requested_theme =
      Map.get(variables, :requested_theme) || Map.get(variables, "requested_theme")

    mode =
      Map.get(theme, :mode) || Map.get(theme, "mode") || Map.get(theme, :type) ||
        Map.get(theme, "type")

    requested_theme == :system or normalize_mode(mode) == :system
  end

  def requested_system?(_theme), do: false

  @spec normalize_requested_source(term()) :: term()
  def normalize_requested_source(%__MODULE__{
        mode: :system16,
        variables: %{requested_theme: :system}
      }),
      do: :system

  def normalize_requested_source(theme) when is_list(theme) do
    if Keyword.keyword?(theme), do: normalize_requested_source(Map.new(theme)), else: theme
  end

  def normalize_requested_source(theme) when is_map(theme) do
    variables = Map.get(theme, :variables) || Map.get(theme, "variables") || %{}

    requested_theme =
      Map.get(variables, :requested_theme) || Map.get(variables, "requested_theme")

    mode =
      Map.get(theme, :mode) || Map.get(theme, "mode") || Map.get(theme, :type) ||
        Map.get(theme, "type")

    if requested_theme == :system and normalize_mode(mode) != :system, do: :system, else: theme
  end

  def normalize_requested_source(theme), do: theme

  @spec probe_status(t() | map() | keyword() | atom() | nil) ::
          :ready | :pending | :unavailable | nil
  def probe_status(theme) do
    theme = new(theme)
    Map.get(theme.variables, :palette_probe_status)
  end

  @spec default_style(t() | map() | keyword() | atom() | nil) :: map()
  def default_style(theme) do
    theme = new(theme)
    theme.defaults
  end

  @spec system16(keyword()) :: t()
  def system16(opts \\ []) do
    terminal_palette =
      normalize_terminal_palette(
        Keyword.get(opts, :palette) || terminal_palette_from_terminal(opts[:terminal])
      )

    %__MODULE__{
      name: Keyword.get(opts, :name, "system16"),
      mode: :system16,
      dark: Keyword.get(opts, :dark, infer_dark(terminal_palette)),
      defaults: %{foreground_color: 7, background_color: 0, border_color: 7},
      palette: system16_palette(terminal_palette),
      extras: %{},
      variables: Keyword.get(opts, :variables, %{}),
      terminal_palette: terminal_palette
    }
  end

  @spec system(keyword()) :: t()
  def system(opts \\ []) do
    terminal_palette =
      normalize_terminal_palette(
        Keyword.get(opts, :palette) || terminal_palette_from_terminal(opts[:terminal])
      )

    if system_palette_available?(terminal_palette) do
      %__MODULE__{
        name: Keyword.get(opts, :name, "system"),
        mode: :system,
        dark: Keyword.get(opts, :dark, infer_dark(terminal_palette)),
        defaults: system_defaults(terminal_palette),
        palette: system_palette(terminal_palette),
        extras: %{},
        variables: Keyword.get(opts, :variables, %{}) |> Map.put(:palette_probe_status, :ready),
        terminal_palette: terminal_palette
      }
    else
      system16(
        name: Keyword.get(opts, :name, "system16"),
        dark: Keyword.get(opts, :dark),
        variables:
          Keyword.get(opts, :variables, %{})
          |> Map.put(:requested_theme, :system)
          |> Map.put(:palette_probe_status, Breeze.Theme.Probe.probe_status(opts[:terminal])),
        palette: terminal_palette
      )
    end
  end

  @spec ensure_runtime_palette_async(Termite.Terminal.t() | nil, pid()) :: :ok
  def ensure_runtime_palette_async(%Termite.Terminal{} = terminal, notify_pid)
      when is_pid(notify_pid) do
    Breeze.Theme.Probe.ensure_runtime_palette_async(terminal, notify_pid)
  end

  def ensure_runtime_palette_async(_terminal, _notify_pid), do: :ok

  @spec start_runtime_palette_probe(Termite.Terminal.t() | nil) ::
          {:start, term(), binary()} | :ready | :pending | :unavailable | :error
  def start_runtime_palette_probe(%Termite.Terminal{} = terminal) do
    Breeze.Theme.Probe.start_runtime_palette_probe(terminal)
  end

  def start_runtime_palette_probe(_terminal), do: :error

  @spec runtime_palette_probe_timeout_ms() :: pos_integer()
  def runtime_palette_probe_timeout_ms, do: Breeze.Theme.Probe.runtime_palette_probe_timeout_ms()

  @spec merge_runtime_palette_data(binary(), map(), binary()) :: {map(), binary()}
  def merge_runtime_palette_data(buffer, palette, data)
      when is_binary(buffer) and is_map(palette) and is_binary(data) do
    Breeze.Theme.Probe.merge_runtime_palette_data(buffer, palette, data)
  end

  @spec runtime_palette_probe_complete?(map()) :: boolean()
  def runtime_palette_probe_complete?(palette) when is_map(palette),
    do: Breeze.Theme.Probe.runtime_palette_probe_complete?(palette)

  def runtime_palette_probe_complete?(_palette), do: false

  @spec finish_runtime_palette_probe(Termite.Terminal.t() | nil, map()) :: :ready | :unavailable
  def finish_runtime_palette_probe(%Termite.Terminal{} = terminal, palette)
      when is_map(palette) do
    Breeze.Theme.Probe.finish_runtime_palette_probe(terminal, palette)
  end

  def finish_runtime_palette_probe(_terminal, _palette), do: :unavailable

  @spec new(t() | map() | keyword() | atom() | nil, keyword()) :: t()
  def new(theme, opts \\ [])

  def new(nil, opts), do: default(opts)
  def new(false, opts), do: default(opts)
  def new(true, opts), do: default(opts)
  def new(:system16, opts), do: system16(opts)
  def new(:system, opts), do: system(opts)

  def new(%__MODULE__{} = theme, opts) do
    case theme.mode do
      :system ->
        system(
          name: theme.name,
          dark: theme.dark,
          variables: theme.variables,
          palette:
            Keyword.get(opts, :palette, theme.terminal_palette) ||
              terminal_palette_from_terminal(opts[:terminal])
        )

      :system16 ->
        system16(
          name: theme.name,
          dark: theme.dark,
          variables: theme.variables,
          palette:
            Keyword.get(opts, :palette, theme.terminal_palette) ||
              terminal_palette_from_terminal(opts[:terminal])
        )

      :custom ->
        theme
    end
  end

  def new(theme, opts) when is_list(theme) do
    if Keyword.keyword?(theme), do: theme |> Map.new() |> new(opts), else: default(opts)
  end

  def new(theme, opts) when is_map(theme) do
    mode = theme[:mode] || theme[:type]

    case normalize_mode(mode) do
      :system ->
        system(
          name: theme[:name],
          dark: theme[:dark],
          variables: theme[:variables] || %{},
          palette:
            theme[:terminal_palette] || theme[:palette] || Keyword.get(opts, :palette) ||
              terminal_palette_from_terminal(opts[:terminal])
        )

      :system16 ->
        system16(
          name: theme[:name],
          dark: theme[:dark],
          variables: theme[:variables] || %{},
          palette:
            theme[:terminal_palette] || theme[:palette] || Keyword.get(opts, :palette) ||
              terminal_palette_from_terminal(opts[:terminal])
        )

      _ ->
        build_custom(theme)
    end
  end

  @spec color(t() | map() | keyword() | atom() | nil, atom() | String.t()) :: color() | nil
  def color(theme, key) do
    theme = new(theme)
    key = normalize_key(key)

    default_color(theme, key) ||
      Map.get(theme.palette, canonical_palette_key(key)) ||
      Map.get(theme.extras, key)
  end

  @spec resolve_color(t() | map() | keyword() | atom() | nil, term()) :: term()
  def resolve_color(theme, value)

  def resolve_color(theme, value) when is_atom(value) do
    color(theme, value) || value
  end

  def resolve_color(_theme, value) when is_integer(value), do: value

  def resolve_color(_theme, {red, green, blue} = value)
      when red in 0..255 and green in 0..255 and blue in 0..255,
      do: value

  def resolve_color(theme, value) when is_binary(value) do
    value = String.trim(value)

    case Integer.parse(value) do
      {parsed, ""} ->
        parsed

      _ ->
        color(theme, value) || value
    end
  end

  def resolve_color(_theme, value), do: value

  @spec blend(color(), color(), float()) :: color()
  def blend(left, right, weight) when is_number(weight) do
    mix(left, right, max(0.0, min(weight * 1.0, 1.0)))
  end

  @spec lighten(color(), float()) :: color()
  def lighten(color, amount) when is_number(amount) do
    blend(color, {255, 255, 255}, max(0.0, min(amount * 1.0, 1.0)))
  end

  @spec darken(color(), float()) :: color()
  def darken(color, amount) when is_number(amount) do
    blend(color, {0, 0, 0}, max(0.0, min(amount * 1.0, 1.0)))
  end

  @spec blendable?(t() | map() | keyword() | atom() | nil) :: boolean()
  def blendable?(theme) do
    case new(theme).mode do
      mode when mode in [:system, :system16] -> false
      _ -> true
    end
  end

  defp build_custom(theme) do
    defaults =
      theme
      |> explicit_defaults()
      |> Map.merge(legacy_defaults(theme))

    palette =
      theme
      |> explicit_palette()
      |> Map.merge(legacy_palette(theme))

    extras =
      theme
      |> explicit_extras()
      |> Map.merge(legacy_extras(theme))

    %__MODULE__{
      name: theme[:name],
      mode: :custom,
      dark: theme[:dark],
      defaults: defaults,
      palette: palette,
      extras: extras,
      variables: theme[:variables] || %{},
      terminal_palette: normalize_terminal_palette(theme[:terminal_palette])
    }
  end

  defp explicit_defaults(theme) do
    theme
    |> Map.get(:defaults, %{})
    |> normalize_default_map()
  end

  defp explicit_palette(theme) do
    theme
    |> Map.get(:palette, %{})
    |> normalize_palette_entries()
  end

  defp explicit_extras(theme) do
    theme
    |> Map.get(:extras, %{})
    |> normalize_palette_entries()
  end

  defp legacy_defaults(theme) do
    Enum.reduce(theme, %{}, fn {key, value}, acc ->
      case normalize_key(key) do
        :foreground_color -> Map.put(acc, :foreground_color, value)
        :background_color -> Map.put(acc, :background_color, value)
        :border_color -> Map.put(acc, :border_color, value)
        :text -> Map.put(acc, :foreground_color, value)
        :background -> Map.put(acc, :background_color, value)
        :stroke -> Map.put(acc, :border_color, value)
        :border -> Map.put(acc, :border_color, value)
        _ -> acc
      end
    end)
    |> normalize_default_map()
  end

  defp legacy_palette(theme) do
    Enum.reduce(theme, %{}, fn {key, value}, acc ->
      key = normalize_key(key)

      if key in @legacy_palette_keys do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
    |> normalize_palette_entries()
  end

  defp legacy_extras(theme) do
    Enum.reduce(theme, %{}, fn {key, value}, acc ->
      key = normalize_key(key)

      cond do
        key in @reserved_keys ->
          acc

        key in [
          :foreground_color,
          :background_color,
          :border_color,
          :text,
          :background,
          :stroke,
          :border
        ] ->
          acc

        key in @legacy_palette_keys ->
          acc

        true ->
          Map.put(acc, key, value)
      end
    end)
    |> normalize_palette_entries()
  end

  defp normalize_mode(mode) when mode in [:system, :system16, :custom], do: mode
  defp normalize_mode("system"), do: :system
  defp normalize_mode("system16"), do: :system16
  defp normalize_mode("custom"), do: :custom
  defp normalize_mode(_), do: nil

  defp system_defaults(nil) do
    %{foreground_color: 7, background_color: 0, border_color: 8}
  end

  defp system_defaults(terminal_palette) do
    background =
      terminal_palette_lookup(terminal_palette, :background) ||
        terminal_palette_lookup(terminal_palette, 0) || {0, 0, 0}

    foreground =
      terminal_palette_lookup(terminal_palette, :foreground) ||
        terminal_palette_lookup(terminal_palette, 7) || {255, 255, 255}

    %{
      foreground_color: foreground,
      background_color: background,
      border_color: mix(foreground, background, 0.35)
    }
  end

  defp system16_palette(nil) do
    %{
      muted: 7,
      primary: 4,
      secondary: 6,
      warning: 3,
      error: 1,
      success: 2,
      accent: 5,
      surface: 8,
      panel: 0
    }
  end

  defp system16_palette(terminal_palette) do
    background =
      terminal_palette_lookup(terminal_palette, :background) ||
        terminal_palette_lookup(terminal_palette, 0) || {0, 0, 0}

    foreground =
      terminal_palette_lookup(terminal_palette, :foreground) ||
        terminal_palette_lookup(terminal_palette, 7) || {255, 255, 255}

    %{
      muted: tone_mix(foreground, background, 0.55, 7),
      primary: 4,
      secondary: 6,
      warning: 3,
      error: 1,
      success: 2,
      accent: 5,
      surface: tone_mix(background, foreground, 0.08, 8),
      panel: tone_mix(background, foreground, 0.14, 0)
    }
  end

  defp system_palette(nil) do
    %{
      muted: 8,
      primary: 12,
      secondary: 14,
      warning: 11,
      error: 9,
      success: 10,
      accent: 13,
      surface: 0,
      panel: 0
    }
  end

  defp system_palette(terminal_palette) do
    background = system_defaults(terminal_palette).background_color
    foreground = system_defaults(terminal_palette).foreground_color

    primary =
      terminal_palette_lookup(terminal_palette, 4) ||
        terminal_palette_lookup(terminal_palette, 12) || foreground

    secondary =
      terminal_palette_lookup(terminal_palette, 6) ||
        terminal_palette_lookup(terminal_palette, 14) || foreground

    warning =
      terminal_palette_lookup(terminal_palette, 3) ||
        terminal_palette_lookup(terminal_palette, 11) || foreground

    error =
      terminal_palette_lookup(terminal_palette, 1) || terminal_palette_lookup(terminal_palette, 9) ||
        foreground

    success =
      terminal_palette_lookup(terminal_palette, 2) ||
        terminal_palette_lookup(terminal_palette, 10) || foreground

    accent =
      terminal_palette_lookup(terminal_palette, 5) ||
        terminal_palette_lookup(terminal_palette, 13) || primary

    %{
      muted: mix(foreground, background, 0.55),
      primary: primary,
      secondary: secondary,
      warning: warning,
      error: error,
      success: success,
      accent: accent,
      surface: mix(background, foreground, 0.08),
      panel: mix(background, foreground, 0.14)
    }
  end

  defp tone_mix(left, right, weight, fallback) do
    case mix(left, right, weight) do
      value when value == left ->
        fallback

      value ->
        if visually_distinct?(left, value) do
          value
        else
          fallback
        end
    end
  end

  defp visually_distinct?(left, right) do
    with {:ok, left_rgb} <- to_rgb(left),
         {:ok, right_rgb} <- to_rgb(right) do
      color_distance(left_rgb, right_rgb) >= 36
    else
      _ -> left != right
    end
  end

  defp color_distance({lr, lg, lb}, {rr, rg, rb}) do
    :math.sqrt(
      :math.pow(rr - lr, 2) +
        :math.pow(rg - lg, 2) +
        :math.pow(rb - lb, 2)
    )
  end

  defp terminal_palette_from_terminal(%Termite.Terminal{} = terminal),
    do: Map.get(terminal, :palette) || Breeze.Theme.Probe.cached_terminal_palette(terminal)

  defp terminal_palette_from_terminal(_), do: nil

  defp normalize_terminal_palette(nil), do: nil

  defp normalize_terminal_palette(palette) when is_list(palette) do
    if Keyword.keyword?(palette),
      do: palette |> Map.new() |> normalize_terminal_palette(),
      else: nil
  end

  defp normalize_terminal_palette(palette) when is_map(palette) do
    Map.new(palette, fn {key, value} ->
      {normalize_terminal_palette_key(key), normalize_color_value(value)}
    end)
  end

  defp normalize_terminal_palette(_), do: nil

  defp normalize_terminal_palette_key(key) when is_integer(key), do: key
  defp normalize_terminal_palette_key(key) when key in [:foreground, :background], do: key

  defp normalize_terminal_palette_key(key) when is_binary(key) do
    case Integer.parse(key) do
      {value, ""} -> value
      _ -> normalize_key(key)
    end
  end

  defp normalize_terminal_palette_key(key) when is_atom(key), do: key
  defp normalize_terminal_palette_key(key), do: key

  defp normalize_default_map(nil), do: %{}

  defp normalize_default_map(values) when is_list(values) do
    if Keyword.keyword?(values), do: values |> Map.new() |> normalize_default_map(), else: %{}
  end

  defp normalize_default_map(values) when is_map(values) do
    Enum.reduce(values, %{}, fn {key, value}, acc ->
      case canonical_default_key(key) do
        nil -> acc
        target -> Map.put(acc, target, normalize_color_value(value))
      end
    end)
  end

  defp normalize_default_map(_), do: %{}

  defp normalize_palette_entries(nil), do: %{}

  defp normalize_palette_entries(values) when is_list(values) do
    if Keyword.keyword?(values), do: values |> Map.new() |> normalize_palette_entries(), else: %{}
  end

  defp normalize_palette_entries(values) when is_map(values) do
    Map.new(values, fn {key, value} ->
      {canonical_palette_key(key), normalize_color_value(value)}
    end)
  end

  defp normalize_palette_entries(_), do: %{}

  defp normalize_color_value("#" <> hex), do: parse_hex_color!(hex)

  defp normalize_color_value({red, green, blue} = color)
       when red in 0..255 and green in 0..255 and blue in 0..255,
       do: color

  defp normalize_color_value(color), do: color

  defp terminal_palette_lookup(nil, _key), do: nil
  defp terminal_palette_lookup(palette, key), do: Map.get(palette, key)

  defp system_palette_available?(terminal_palette) when is_map(terminal_palette) do
    Enum.all?(
      [:background, :foreground],
      &match?({_, _, _}, terminal_palette_lookup(terminal_palette, &1))
    )
  end

  defp system_palette_available?(_), do: false

  defp default_color(theme, key) do
    case canonical_default_key(key) do
      nil -> nil
      target -> Map.get(theme.defaults, target)
    end
  end

  defp infer_dark(nil), do: true

  defp infer_dark(terminal_palette) do
    case terminal_palette_lookup(terminal_palette, :background) ||
           terminal_palette_lookup(terminal_palette, 0) do
      {red, green, blue} -> luminance({red, green, blue}) < 0.5
      _ -> true
    end
  end

  defp mix(left, right, weight) do
    with {:ok, left} <- to_rgb(left),
         {:ok, right} <- to_rgb(right) do
      {
        blend_channel(elem(left, 0), elem(right, 0), weight),
        blend_channel(elem(left, 1), elem(right, 1), weight),
        blend_channel(elem(left, 2), elem(right, 2), weight)
      }
    else
      _ -> left
    end
  end

  defp to_rgb({red, green, blue}) when red in 0..255 and green in 0..255 and blue in 0..255,
    do: {:ok, {red, green, blue}}

  defp to_rgb("#" <> hex), do: {:ok, parse_hex_color!(hex)}
  defp to_rgb(_), do: :error

  defp blend_channel(left, right, weight) do
    round(left * (1.0 - weight) + right * weight)
  end

  defp luminance({red, green, blue}) do
    (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
  end

  defp canonical_default_key(key)
       when key in [:foreground_color, :background_color, :border_color],
       do: key

  defp canonical_default_key(key) when is_atom(key), do: Map.get(@default_aliases, key)
  defp canonical_default_key(key), do: key |> normalize_key() |> canonical_default_key()

  defp canonical_palette_key(key) when is_atom(key), do: Map.get(@palette_aliases, key, key)
  defp canonical_palette_key(key), do: key |> normalize_key() |> canonical_palette_key()

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    key
    |> String.replace("-", "_")
    |> String.to_atom()
  end

  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp parse_hex_color!(<<_::binary-size(6)>> = hex) do
    List.to_tuple(for <<pair::binary-size(2) <- hex>>, do: hex_byte!(pair))
  end

  defp parse_hex_color!(<<r, g, b>>) do
    parse_hex_color!(<<r, r, g, g, b, b>>)
  end

  defp parse_hex_color!(other) do
    raise ArgumentError, "invalid hex color: #{inspect(other)}"
  end

  defp hex_byte!(pair) do
    pair
    |> Integer.parse(16)
    |> case do
      {value, ""} -> value
      _ -> raise ArgumentError, "invalid hex byte: #{inspect(pair)}"
    end
  end
end
