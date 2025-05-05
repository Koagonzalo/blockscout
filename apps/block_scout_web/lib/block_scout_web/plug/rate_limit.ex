defmodule BlockScoutWeb.Plug.RateLimit do
  @moduledoc """
    Rate limiting
  """
  alias BlockScoutWeb.{AccessHelper, RateLimit}
  alias Plug.Conn

  # static_api_key
  # account_api_key
  # whitelisted_ip
  # temporary_token
  # limit_by_ip

  # нужен ли regexp в названиях роутов
  # нужно ли рейтлимитить не по ip, в дефолте

  # should match
  # "api/account/v2/authenticate_via_wallet"
  # ["api", "account", "v2", "authenticate_via_wallet"]
  # ["api", "account", "v2", "authenticate_via_wallet"]

  # # via Enum.take
  # "api/account/v2/*"
  # ["api", "account", "v2", "*"]
  # {["api", "account", "v2"], 3}

  # # via underscoring one of the path part
  # "api/account/v2/:param"
  # ["api", "account", "v2", ":param"]
  # ["api", "account", "v2", ":param"]

  # any field from static_api_key to temporary_token could be
  # true (will be used default configured rate limits (from envs)),
  # false (disabled option)
  # or a map with period and limit
  # while overriding account_api_key, make sure that your limits much less than the default ones
  # if you want to use default rate limits, just set true
  # if you want to disable rate limit, set false
  # if you want to use custom rate limits, set a map with period and limit
  #
  # if you want to use custom rate limits for a specific route, set a map with period and limit
  #
  # logic on frontend:
  # if X-RateLimit-Remaining

  # @multipliers %{
  #   "api/v2" => 1,
  #   "api/eth-rpc" => 2
  # }

  def init(opts), do: opts

  def call(conn, _opts) do
    request_path = request_path(conn)
    config = fetch_rate_limit_config(request_path)

    conn
    |> handle_call(config)
    |> case do
      {:deny, _time_to_reset, _limit, _period} = result ->
        conn
        |> set_rate_limit_headers(result)
        |> AccessHelper.handle_rate_limit_deny(!api_v2?(conn))

      result ->
        set_rate_limit_headers(conn, result)
    end
    |> set_rate_limit_headers_for_frontend(config)
  end

  defp set_rate_limit_headers(conn, result) do
    case result do
      {:allow, -1} ->
        conn
        |> Conn.put_resp_header("X-RateLimit-Limit", "-1")
        |> Conn.put_resp_header("X-RateLimit-Remaining", "-1")
        |> Conn.put_resp_header("X-RateLimit-Reset", "-1")

      {:allow, count, limit, period} ->
        now = System.system_time(:millisecond)
        window = div(now, period)
        expires_at = (window + 1) * period

        conn
        |> Conn.put_resp_header("X-RateLimit-Limit", "#{limit}")
        |> Conn.put_resp_header("X-RateLimit-Remaining", "#{limit - count}")
        |> Conn.put_resp_header("X-RateLimit-Reset", "#{expires_at - now}")

      {:deny, time_to_reset, limit, _time_interval} ->
        conn
        |> Conn.put_resp_header("X-RateLimit-Limit", "#{limit}")
        |> Conn.put_resp_header("X-RateLimit-Remaining", "0")
        |> Conn.put_resp_header("X-RateLimit-Reset", "#{time_to_reset}")
    end
  end

  defp set_rate_limit_headers_for_frontend(conn, config) do
    user_agent = RateLimit.get_user_agent(conn)

    option =
      cond do
        config[:recaptcha_to_bypass_429] && user_agent -> "recaptcha"
        config[:temporary_token] && user_agent -> "temporary_token"
        !is_nil(config) -> "no_bypass"
        true -> "no_bypass"
      end

    conn
    |> Conn.put_resp_header("bypass-429-option", option)
  end

  defp handle_call(conn, config) do
    cond do
      graphql?(conn) ->
        RateLimit.check_rate_limit(conn, 1, graphql?: graphql?(conn))

      true ->
        RateLimit.rate_limit_special(conn, config)
    end
  end

  defp fetch_rate_limit_config(request_path) do
    config = Application.get_env(:block_scout_web, :api_rate_limit)[:config]
    request_path = request_path |> String.trim("/")

    cond do
      res = config[:map][request_path] ->
        res

      true ->
        find_endpoint_config(config, request_path) || config[:map]["default"]
    end
  end

  defp find_endpoint_config(config, request_path) do
    request_path_parts = String.split(request_path, "/")

    Enum.find(config[:parametrized_match], fn {key, _config} ->
      length(key) == length(request_path_parts) &&
        key |> Enum.zip(request_path_parts) |> Enum.all?(fn {k, r} -> k == r || k == ":param" end)
    end) ||
      Enum.find(config[:wildcard_match], fn {{key, length}, _config} when is_integer(length) ->
        Enum.take(request_path_parts, length) == key
      end)
  end

  defp graphql?(conn) do
    request_path = request_path(conn)
    request_path == "api/v1/graphql" or request_path == "graphiql"
  end

  defp request_path(conn) do
    Enum.join(conn.path_info, "/")
  end

  defp api_v2?(conn) do
    conn.path_info |> Enum.take(2) == ["api", "v2"]
  end
end
