Rate limits could be defined in json config, which should be passed to `API_RATE_LIMIT_CONFIG_URL` as url to json file. 
Rate limits json config structure:
json config is a map, where
keys - API endpoints path, and values - rate limit config.
Example: 
```
"api/account/v2/send_otp": {
  "recaptcha_to_bypass_429": true,
    "ip": {
      "period": "1h",
      "limit": 1
    }
}
```
Path should not contain any query params.
Path should not contain trailing slashes
Path could contain `*`, it works as wildcard, means that path starting from the asterics will be discarded while matching. For example: `api/v2/*` will match to `api/v2`, `api/v2/addresses`.
Path could contain `:param`, means some variable parameter in endpoint path. For example: `api/v2/addresses/:param` will match to `api/v2/addresses/0x00000..000`
Please note, that it's not allowed to use `*` and `:param` simultaneously.
Priority of paths defined in config 
 1. path without `:param` and `*`
 2. path with `:param`
 3. path with `*`
Config must contain `default` key, where will be defined default API rate limit config, which will be used if for some endpoing won't match any of defined paths in config. (Excluding graphQL endpoints, them are out of scope for this config, and rate limits as previously based on ENVs: `API_GRAPHQL_RATE_LIMIT_*`)

Values for rate limit entry is a json map, which could contain following keys:
  - "account_api_key" (#rate_limit_option)
    (if true or a map, then allowed to use API key, emitted in My Account)
    while overriding account_api_key, make sure that your limits much less than the default ones
  - "whitelisted_ip" (#rate_limit_option)
    (if true or a map, then allowed to rate limit by whitelisted IP)
  - "static_api_key" (#rate_limit_option)
    (if true or a map, then allowed to rate limit by static API key)
  - "temporary_token" (#rate_limit_option)
    (if true or a map, then allowed to rate limit by temporary token (cookie), issued by /api/v2/key)
  - "ip" (#rate_limit_option)
    (if true or a map, then allowed to rate limit by IP address)
  - "cost"
    (integer value, used to decrease allowed limit, by it's value. By default `1`)
  - "ignore" 
    (if true, then this endpoint won't be rate limited)
  - "recaptcha_to_bypass_429" 
    (if true, then in case of 429, allowed to pass recaptcha header with recaptcha response, if it'll be correct, then request will be allowed)
  - "bypass_token_scope" 
    (scope of recaptcha bypass token, supported only `token_instance_refetch_metadata`, implemented in: #####, regulated by envs: INSERT ENV name)

#rate_limit_option 
possible values for such keys in config: true, false, map with (`period` and `limit` keys)
if true, then the rate limit option is allowed, and limits will be pulled from ENVs.
if false, or the rate limit option is omitted, then this rate limit option won't be used for that endpoint.
if map, then the rate limit option is allowed and limits will exactly you defined in map (`limit` requests per `period`):
 - `limit` - integer value representing max amount of request allowed per period
 - `period` - rate limit time period, should be in [time format](https://docs.blockscout.com/setup/env-variables/backend-env-variables#time-format)
while overriding account_api_key, make sure that your limits much less than the default ones


## Recaptcha 
Recaptcha response should be passed via headers: 
  - `recaptcha-v2-response` for V2 captcha
  - `recaptcha-v3-response` for V3 captcha
  - `recaptcha-bypass-token` for not scoped bypass recaptcha token
  - `scoped-recaptcha-bypass-token` for scoped bypass recaptcha token (currently supported only `token_instance_refetch_metadata` scope), which was implemented in [#12147](https://github.com/blockscout/blockscout/pull/12147)
Recaptcha for `api/v2/key` endpoint should be sent as now, in request body.

## Rate limits headers
Backend returns informational headers for rate limits:
  - `X-RateLimit-Limit` total limit per timeframe
  - `X-RateLimit-Remaining` remaining amount of requests within current time window
  - `X-RateLimit-Reset` time to reset rate limits in milliseconds
Above headers could take `-1` value in case of 
  - internal errors
  - `API_NO_RATE_LIMIT_API_KEY` is used
  - rate limits disabled on the backend
  - the enpoint you requesting has `"ignore": true` parameter set, and isn't rate limited

Also there are `bypass-429-option` header, which indicates which option should fronted use in order to make successful requests even if user hits the limits. Possible values are:
  - `recaptcha` 
    each request should paired with recaptcha response in headers (see [#recaptcha])
  - `temporary_token`
    should get temporary cookie in api/v2/key endpoint
  - `no_bypass`
    no way to bypass 429 error
