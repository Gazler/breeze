defmodule Breeze.Theme.Contrast do
  @moduledoc false

  # Internal contrast measurement and color correction for terminal-derived
  # themes. Contrast uses WCAG's sRGB relative luminance. Corrections search
  # Oklab lightness, reducing chroma at a fixed hue when needed to stay in the
  # sRGB gamut.
  #
  # References:
  # * https://www.w3.org/TR/WCAG22/#dfn-contrast-ratio
  # * https://www.w3.org/TR/WCAG22/#dfn-relative-luminance
  # * https://www.w3.org/TR/css-color-4/#ok-lab
  # * https://www.w3.org/TR/css-color-4/#color-conversion-code
  # * https://bottosson.github.io/posts/oklab/

  @type rgb :: {0..255, 0..255, 0..255}
  @type color :: non_neg_integer() | rgb() | String.t()
  @contrast_iterations 10
  @gamut_search_iterations 8

  # Terminal RGB channels have only 256 possible values, so calculate the
  # WCAG sRGB linearization once at compile time rather than inside each search.
  @linear_channels List.to_tuple(
                     for channel <- 0..255 do
                       encoded = channel / 255

                       if encoded <= 0.04045 do
                         encoded / 12.92
                       else
                         :math.pow((encoded + 0.055) / 1.055, 2.4)
                       end
                     end
                   )

  @doc """
  Returns the WCAG contrast ratio between two RGB or hexadecimal colors.

  Results range from `1.0` for identical luminance to `21.0` for black against
  white. Terminal color indexes cannot be measured without an RGB palette and
  return `nil`.
  """
  @spec ratio(color(), color()) :: float() | nil
  def ratio(left, right) do
    with {:ok, left} <- to_rgb(left),
         {:ok, right} <- to_rgb(right) do
      ratio_rgb(left, right)
    else
      _ -> nil
    end
  end

  @doc """
  Adjusts a color's Oklab lightness until it meets `minimum` contrast.

  The returned RGB color satisfies the requested ratio against every
  background when either black or white can do so. Otherwise the original
  color is returned.
  """
  @spec adjust(color(), [color()], number()) :: color()
  def adjust(color, backgrounds, minimum) when is_list(backgrounds) and is_number(minimum) do
    with {:ok, rgb} <- to_rgb(color),
         {:ok, backgrounds} <- to_rgb_colors(backgrounds) do
      background_luminances = Enum.map(backgrounds, &relative_luminance/1)
      adjust_rgb(rgb, background_luminances, minimum, color)
    else
      _ -> color
    end
  end

  defp adjust_rgb(rgb, background_luminances, minimum, fallback) do
    if contrast_satisfied?(rgb, background_luminances, minimum) do
      rgb
    else
      rgb
      |> contrast_candidates(background_luminances, minimum)
      |> Enum.min_by(&elem(&1, 0), fn -> {0, fallback} end)
      |> elem(1)
    end
  end

  @doc "Returns whichever of black or white has greater contrast with a color."
  @spec preferred_target(rgb()) :: rgb()
  def preferred_target(background) do
    background_luminance = relative_luminance(background)

    if ratio_luminances(0.0, background_luminance) >= ratio_luminances(1.0, background_luminance) do
      {0, 0, 0}
    else
      {255, 255, 255}
    end
  end

  @doc """
  Keeps a generated surface on the contrast-safe side of a target color.

  When `color` is too close to `target`, it is moved toward the known-safe
  `anchor` by the minimum RGB blend needed to reach `minimum`.
  """
  @spec keep_contrast_side(rgb(), rgb(), rgb(), number()) :: rgb()
  def keep_contrast_side(color, target, anchor, minimum) do
    target_luminance = relative_luminance(target)

    if ratio_with_luminance(color, target_luminance) >= minimum do
      color
    else
      weight =
        anchor_weight(color, target_luminance, anchor, minimum, 0.0, 1.0, @contrast_iterations)

      mix(color, anchor, weight)
    end
  end

  defp anchor_weight(_color, _target_luminance, _anchor, _minimum, _low, high, 0), do: high

  defp anchor_weight(color, target_luminance, anchor, minimum, low, high, attempts) do
    weight = (low + high) / 2

    if ratio_with_luminance(mix(color, anchor, weight), target_luminance) >= minimum do
      anchor_weight(color, target_luminance, anchor, minimum, low, weight, attempts - 1)
    else
      anchor_weight(color, target_luminance, anchor, minimum, weight, high, attempts - 1)
    end
  end

  defp contrast_candidates(color, background_luminances, minimum) do
    oklab = rgb_to_oklab(color)

    [0.0, 1.0]
    |> Enum.map(&contrast_candidate(oklab, &1, background_luminances, minimum))
    |> Enum.reject(&is_nil/1)
  end

  defp contrast_candidate(oklab, target, bg_luminances, minimum) do
    {lightness, _a, _b} = oklab

    satisfied? =
      oklab
      |> put_elem(0, target)
      |> oklab_to_rgb()
      |> contrast_satisfied?(bg_luminances, minimum)

    if satisfied? do
      weight =
        contrast_weight(oklab, target, bg_luminances, minimum, 0.0, 1.0, @contrast_iterations)

      candidate_lightness = blend_number(lightness, target, weight)
      distance = abs(candidate_lightness - lightness)

      {distance, oklab |> put_elem(0, candidate_lightness) |> oklab_to_rgb()}
    end
  end

  defp contrast_weight(_oklab, _target, _backgrounds, _minimum, _low, high, 0), do: high

  defp contrast_weight(oklab, target, background_luminances, minimum, low, high, attempts) do
    {lightness, _a, _b} = oklab
    weight = (low + high) / 2

    candidate =
      oklab
      |> put_elem(0, blend_number(lightness, target, weight))
      |> oklab_to_rgb()

    if contrast_satisfied?(candidate, background_luminances, minimum) do
      contrast_weight(oklab, target, background_luminances, minimum, low, weight, attempts - 1)
    else
      contrast_weight(oklab, target, background_luminances, minimum, weight, high, attempts - 1)
    end
  end

  defp contrast_satisfied?(color, background_luminances, minimum) do
    color_luminance = relative_luminance(color)
    Enum.all?(background_luminances, &(ratio_luminances(color_luminance, &1) >= minimum))
  end

  defp ratio_rgb(left, right) do
    ratio_luminances(relative_luminance(left), relative_luminance(right))
  end

  defp ratio_with_luminance(color, other_luminance) do
    ratio_luminances(relative_luminance(color), other_luminance)
  end

  defp ratio_luminances(left, right) do
    lighter = max(left, right)
    darker = min(left, right)
    (lighter + 0.05) / (darker + 0.05)
  end

  defp relative_luminance({red, green, blue}) do
    0.2126 * linear_channel(red) +
      0.7152 * linear_channel(green) +
      0.0722 * linear_channel(blue)
  end

  defp linear_channel(channel), do: elem(@linear_channels, channel)

  defp rgb_to_oklab({red, green, blue}) do
    red = linear_channel(red)
    green = linear_channel(green)
    blue = linear_channel(blue)

    light = cube_root(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    medium = cube_root(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    short = cube_root(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)

    {
      0.2104542553 * light + 0.793617785 * medium - 0.0040720468 * short,
      1.9779984951 * light - 2.428592205 * medium + 0.4505937099 * short,
      0.0259040371 * light + 0.7827717662 * medium - 0.808675766 * short
    }
  end

  defp oklab_to_rgb(oklab) do
    channels = oklab_to_rgb_channels(oklab)

    if rgb_channels_in_gamut?(channels) do
      normalize_rgb_channels(channels)
    else
      fit_oklab_chroma(oklab, 0.0, 1.0, @gamut_search_iterations)
    end
  end

  defp fit_oklab_chroma({lightness, a, b}, low, _high, 0) do
    {lightness, a * low, b * low}
    |> oklab_to_rgb_channels()
    |> normalize_rgb_channels()
  end

  defp fit_oklab_chroma({lightness, a, b} = oklab, low, high, attempts) do
    scale = (low + high) / 2
    channels = oklab_to_rgb_channels({lightness, a * scale, b * scale})

    if rgb_channels_in_gamut?(channels) do
      fit_oklab_chroma(oklab, scale, high, attempts - 1)
    else
      fit_oklab_chroma(oklab, low, scale, attempts - 1)
    end
  end

  defp oklab_to_rgb_channels({lightness, a, b}) do
    light = lightness + 0.3963377774 * a + 0.2158037573 * b
    medium = lightness - 0.1055613458 * a - 0.0638541728 * b
    short = lightness - 0.0894841775 * a - 1.291485548 * b

    light = light * light * light
    medium = medium * medium * medium
    short = short * short * short

    {
      encode_linear_channel(4.0767416621 * light - 3.3077115913 * medium + 0.2309699292 * short) *
        255,
      encode_linear_channel(-1.2684380046 * light + 2.6097574011 * medium - 0.3413193965 * short) *
        255,
      encode_linear_channel(-0.0041960863 * light - 0.7034186147 * medium + 1.707614701 * short) *
        255
    }
  end

  defp encode_linear_channel(channel) when abs(channel) <= 0.0031308,
    do: 12.92 * channel

  defp encode_linear_channel(channel) do
    sign = if channel < 0, do: -1, else: 1
    sign * (1.055 * :math.pow(abs(channel), 1 / 2.4) - 0.055)
  end

  defp rgb_channels_in_gamut?({red, green, blue}) do
    Enum.all?([red, green, blue], &(&1 >= -0.001 and &1 <= 255.001))
  end

  defp normalize_rgb_channels({red, green, blue}) do
    {normalize_rgb_channel(red), normalize_rgb_channel(green), normalize_rgb_channel(blue)}
  end

  defp normalize_rgb_channel(channel), do: channel |> max(0.0) |> min(255.0) |> round()

  defp mix({left_red, left_green, left_blue}, {right_red, right_green, right_blue}, weight) do
    {
      blend_channel(left_red, right_red, weight),
      blend_channel(left_green, right_green, weight),
      blend_channel(left_blue, right_blue, weight)
    }
  end

  defp blend_channel(left, right, weight), do: round(blend_number(left, right, weight))
  defp blend_number(left, right, weight), do: left * (1.0 - weight) + right * weight
  defp cube_root(value), do: :math.pow(value, 1 / 3)

  defp to_rgb_colors(colors) do
    Enum.reduce_while(colors, {:ok, []}, fn color, {:ok, acc} ->
      case to_rgb(color) do
        {:ok, rgb} -> {:cont, {:ok, [rgb | acc]}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp to_rgb({red, green, blue}) when red in 0..255 and green in 0..255 and blue in 0..255,
    do: {:ok, {red, green, blue}}

  defp to_rgb("#" <> hex), do: parse_hex(hex)
  defp to_rgb(_color), do: :error

  defp parse_hex(<<red, green, blue>>), do: parse_hex(<<red, red, green, green, blue, blue>>)

  defp parse_hex(<<red::binary-size(2), green::binary-size(2), blue::binary-size(2)>>) do
    with {:ok, red} <- parse_hex_channel(red),
         {:ok, green} <- parse_hex_channel(green),
         {:ok, blue} <- parse_hex_channel(blue) do
      {:ok, {red, green, blue}}
    end
  end

  defp parse_hex(_hex), do: :error

  defp parse_hex_channel(channel) do
    case Integer.parse(channel, 16) do
      {value, ""} when value in 0..255 -> {:ok, value}
      _other -> :error
    end
  end
end
