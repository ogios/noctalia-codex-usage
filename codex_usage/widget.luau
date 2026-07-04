--!nonstrict
-- Thin bar widget: displays the service-published Codex usage and updates reset
-- countdowns locally once per second without making any network requests.

local status = noctalia.state.get("usage")

noctalia.setUpdateInterval(1000)

local function now()
    return tonumber(noctalia.formatTime("%s")) or 0
end

local function formatPercent(value)
    local number = tonumber(value)
    if number == nil then return "--%" end
    if number < 0 then number = 0 end
    if number > 100 then number = 100 end
    return `{math.floor(number + 0.5)}%`
end

local function gauge(value)
    local number = tonumber(value)
    if number == nil then return barWidget.getConfig("gauge_0") or "⠀" end
    if number < 0 then number = 0 end
    if number > 100 then number = 100 end

    local glyphs = {
        barWidget.getConfig("gauge_0") or "⠀",
        barWidget.getConfig("gauge_1") or "▁",
        barWidget.getConfig("gauge_2") or "▂",
        barWidget.getConfig("gauge_3") or "▃",
        barWidget.getConfig("gauge_4") or "▄",
        barWidget.getConfig("gauge_5") or "▅",
        barWidget.getConfig("gauge_6") or "▆",
        barWidget.getConfig("gauge_7") or "▇",
        barWidget.getConfig("gauge_8") or "█",
    }
    local index = math.floor((number / 100) * (#glyphs - 1) + 1.5)
    return glyphs[index]
end

local function formatDuration(seconds)
    local total = tonumber(seconds)
    if total == nil then return "--" end
    total = math.max(0, math.floor(total))

    local days = math.floor(total / 86400)
    total %= 86400
    local hours = math.floor(total / 3600)
    total %= 3600
    local minutes = math.floor(total / 60)
    local secs = total % 60

    if days > 0 then
        return `{days}d {hours}h`
    elseif hours > 0 then
        return `{hours}h {minutes}m`
    elseif minutes > 0 then
        return `{minutes}m {secs}s`
    end
    return `{secs}s`
end

local function resetRemaining(window)
    if type(window) ~= "table" then return nil end
    local resetAt = tonumber(window.reset_at)
    if resetAt == nil then return nil end
    return resetAt - now()
end

local function renderWindow(label, window)
    if type(window) ~= "table" then
        return `{label} {gauge(nil)} --% (--)`
    end
    return `{label} {gauge(window.remaining_percent)} {formatPercent(window.remaining_percent)} ({formatDuration(resetRemaining(window))})`
end

local function tooltipRows()
    if type(status) ~= "table" then
        return "Waiting for Codex usage data"
    end
    if not status.ok then
        return {
            { key = "Codex Usage", value = "Unavailable" },
            { key = "Error", value = tostring(status.error or "unknown error") },
            { key = "Next request", value = if status.requesting then "Requesting..." else formatDuration((tonumber(status.next_request_at) or now()) - now()) },
        }
    end

    local fiveHour = status.five_hour
    if type(fiveHour) ~= "table" then fiveHour = {} end
    local weekly = status.weekly
    if type(weekly) ~= "table" then weekly = {} end

    local rows = {
        { key = "5-hour remaining", value = `{formatPercent(fiveHour.remaining_percent)} - resets in {formatDuration(resetRemaining(fiveHour))}` },
        { key = "Weekly remaining", value = `{formatPercent(weekly.remaining_percent)} - resets in {formatDuration(resetRemaining(weekly))}` },
        { key = "Next request", value = if status.requesting then "Requesting..." else formatDuration((tonumber(status.next_request_at) or now()) - now()) },
        { key = "Plan", value = tostring(status.plan_type or "unknown") },
    }

    if barWidget.getConfig("show_account") then
        table.insert(rows, { key = "Account", value = tostring(status.email or "unknown") })
    end

    return rows
end

local function render()
    barWidget.setGlyph("brand-openai")

    if type(status) ~= "table" then
        barWidget.setGlyphColor("on_surface_variant")
        barWidget.setText("Codex --")
        barWidget.setTooltip(tooltipRows())
        return
    end

    if not status.ok then
        barWidget.setGlyphColor("error")
        barWidget.setColor("error")
        barWidget.setText("Codex error")
        barWidget.setTooltip(tooltipRows())
        return
    end

    if status.limit_reached then
        barWidget.setGlyphColor("error")
        barWidget.setColor("error")
    else
        barWidget.setGlyphColor("primary")
        barWidget.setColor("on_surface")
    end

    barWidget.setText(`{renderWindow("5h", status.five_hour)} | {renderWindow("W", status.weekly)}`)
    barWidget.setFont("PragmataPro")
    barWidget.setTooltip(tooltipRows())
end

function update()
    render()
end

noctalia.state.watch("usage", function(value)
    status = value
    render()
end)

render()
