--!nonstrict
-- Headless service that polls the Codex usage endpoint and publishes a compact
-- status table for the bar widget. After every completed request, it waits at
-- least request_delay_seconds before starting another one.

local inFlight = false
local nextRequestAt = 0
local lastStatusKey = ""
local currentStatus = nil

noctalia.setUpdateInterval(1000)

local function now()
    return tonumber(noctalia.formatTime("%s")) or 0
end

local function requestDelaySeconds()
    local value = tonumber(noctalia.getConfig("request_delay_seconds")) or 30
    if value < 1 then return 1 end
    return math.floor(value)
end

local function publish(status)
    currentStatus = status
    local key = noctalia.json.encode(status) or ""
    if key == lastStatusKey then return end
    lastStatusKey = key
    noctalia.state.set("usage", status)
end

local function publishError(message)
    publish({ ok = false, requesting = false, error = message, checked_at = now(), next_request_at = nextRequestAt })
end

local function publishRequesting()
    local status = currentStatus
    if type(status) ~= "table" then
        status = { ok = false, error = "requesting usage", checked_at = now() }
    end

    status.requesting = true
    status.requested_at = now()
    publish(status)
end

local function loadAuth()
    local authFile = noctalia.getConfig("auth_file") or "~/.codex/auth.json"
    local body, err = noctalia.readFile(authFile)
    if type(body) ~= "string" or body == "" then
        return nil, nil, `could not read auth file: {err or authFile}`
    end

    local auth, decodeErr = noctalia.json.decode(body)
    if type(auth) ~= "table" then
        return nil, nil, `auth file is not valid JSON: {decodeErr or authFile}`
    end

    local tokens = auth.tokens
    if type(tokens) ~= "table" then
        tokens = {}
    end

    local token = tokens.access_token
    local accountId = tokens.account_id
    if type(token) ~= "string" or token == "" then
        return nil, nil, "missing access token"
    end
    return token, accountId
end

local function remainingPercent(window)
    if type(window) ~= "table" then return nil end
    local used = tonumber(window.used_percent)
    if used == nil then return nil end
    local remaining = 100 - used
    if remaining < 0 then remaining = 0 end
    if remaining > 100 then remaining = 100 end
    return remaining
end

local function resetAt(window, checkedAt)
    if type(window) ~= "table" then return nil end
    local reset = tonumber(window.reset_at)
    if reset ~= nil and reset > 0 then return reset end
    local resetAfter = tonumber(window.reset_after_seconds)
    if resetAfter ~= nil then return checkedAt + resetAfter end
    return nil
end

local function windowStatus(rateLimit, key, checkedAt)
    local window = if type(rateLimit) == "table" then rateLimit[key] else nil
    return {
        remaining_percent = remainingPercent(window),
        reset_at = resetAt(window, checkedAt),
        reset_after_seconds = if type(window) == "table" then tonumber(window.reset_after_seconds) else nil,
    }
end

local function requestUsage()
    local token, accountId, authErr = loadAuth()
    if token == nil then
        nextRequestAt = now() + requestDelaySeconds()
        publishError(authErr or "missing access token")
        return
    end

    local endpoint = noctalia.getConfig("endpoint") or "https://chatgpt.com/backend-api/wham/usage"
    local headers = {
        `Authorization: Bearer {token}`,
        "Accept: application/json",
        "User-Agent: noctalia-codex-usage/1.0",
    }
    if type(accountId) == "string" and accountId ~= "" then
        table.insert(headers, `chatgpt-account-id: {accountId}`)
    end

    inFlight = true
    publishRequesting()
    local accepted = noctalia.http({ url = endpoint, method = "GET", headers = headers }, function(res)
        inFlight = false
        local checkedAt = now()
        nextRequestAt = checkedAt + requestDelaySeconds()

        if not res.ok or res.status < 200 or res.status >= 300 then
            publishError(`HTTP {res.status}`)
            return
        end

        local data, decodeErr = noctalia.json.decode(res.body)
        if type(data) ~= "table" then
            publishError(`response is not valid JSON: {decodeErr or "unknown error"}`)
            return
        end

        local rateLimit = data.rate_limit
        publish({
            ok = true,
            requesting = false,
            checked_at = checkedAt,
            next_request_at = nextRequestAt,
            email = data.email,
            plan_type = data.plan_type,
            allowed = if type(rateLimit) == "table" then rateLimit.allowed else nil,
            limit_reached = if type(rateLimit) == "table" then rateLimit.limit_reached else nil,
            five_hour = windowStatus(rateLimit, "primary_window", checkedAt),
            weekly = windowStatus(rateLimit, "secondary_window", checkedAt),
        })
    end)

    if not accepted then
        inFlight = false
        nextRequestAt = now() + requestDelaySeconds()
        publishError("usage request was rejected")
    end
end

function update()
    if inFlight then return end
    if now() < nextRequestAt then return end
    requestUsage()
end

requestUsage()
