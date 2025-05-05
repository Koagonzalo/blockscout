defmodule Utils.RateLimitConfigHelper do
  @moduledoc """
  Fetches the rate limit config from the config url and parses it into a map.
  """
  require Logger

  def fetch_config do
    # possibly need to change to System.get_env("API_RATE_LIMIT_CONFIG_URL")
    url = Application.get_env(:block_scout_web, :api_rate_limit)[:config_url]

    with {:ok, config} <- download_config(url),
         {:ok, parsed_config} <- parse_config(config) do
      parsed_config
    else
      {:error, reason} ->
        Logger.error("Failed to fetch rate limit config: #{inspect(reason)}")
        %{}
    end
  rescue
    error ->
      Logger.error("Failed to fetch config: #{inspect(error)}")
      %{}
  end

  defp download_config(url) when is_binary(url) do
    url
    |> HTTPoison.get([], follow_redirect: true)
    |> case do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        to_atom? =
          Map.from_keys(
            [
              "account_api_key",
              "bypass_token_scope",
              "cost",
              "ip",
              "ignore",
              "limit",
              "period",
              "recaptcha_to_bypass_429",
              "static_api_key",
              "temporary_token",
              "whitelisted_ip"
            ],
            true
          )

        body
        |> Jason.decode(
          keys: fn key ->
            if to_atom?[key] do
              String.to_atom(key)
            else
              key
            end
          end
        )

      {:ok, %HTTPoison.Response{status_code: status}} ->
        Logger.error("Failed to fetch config from #{url}: #{status}")
        {:error, status}

      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp download_config(_), do: {:error, :invalid_config_url}

  defp parse_config({:ok, config}) do
    cfg = decode_time_values(config)

    {wildcard_match, parametrized_match, static_match} =
      cfg
      |> Map.keys()
      |> Enum.reduce({%{}, %{}, %{}}, fn key, {wildcard_match, parametrized_match, static_match} ->
        path_parts = key |> String.trim("/") |> String.split("/")

        cond do
          String.contains?(key, "*") ->
            if Enum.find_index(path_parts, &Kernel.==(&1, "*")) == length(path_parts) - 1 do
              {Map.put(wildcard_match, {Enum.drop(path_parts, -1), length(path_parts) - 1}, cfg[key]),
               parametrized_match, static_match}
            else
              raise "wildcard `*` allowed only at the end of the path"
            end

          String.contains?(key, ":param") ->
            {wildcard_match, Map.put(parametrized_match, path_parts, cfg[key]), static_match}

          true ->
            {wildcard_match, parametrized_match, Map.put(static_match, key, cfg[key])}
        end
      end)

    {:ok, %{wildcard_match: wildcard_match, parametrized_match: parametrized_match, static_match: static_match}}
  end

  defp parse_config({:error, reason}) do
    {:error, reason}
  end

  @doc """
  Recursively decodes time values in nested maps.
  Converts string time values (like "1h", "5m") in "period" keys to milliseconds.
  """
  def decode_time_values(config) when is_map(config) do
    Enum.map(config, fn
      {:period, value} when is_binary(value) ->
        {:period, parse_time_string(value)}

      {key, value} when is_map(value) ->
        {key, decode_time_values(value)}

      entry ->
        entry
    end)
    |> Enum.into(%{})
  end

  defp parse_time_string(value) do
    case value |> String.downcase() |> Integer.parse() do
      {milliseconds, "ms"} -> milliseconds
      {hours, "h"} -> :timer.hours(hours)
      {minutes, "m"} -> :timer.minutes(minutes)
      {seconds, s} when s in ["s", ""] -> :timer.seconds(seconds)
      _ -> raise "Invalid time format in rate limit config: #{value}"
    end
  end
end
