-- Minimal client for Everest's DebugRC HTTP server.
--
-- Everest starts a small HTTP server on localhost (port 32270 by default, the DebugRCPort
-- setting) that can teleport the player, restart the current screen, reload map binaries and
-- run console commands. The editor has no usable HTTP client of its own (lib/luajit-request
-- needs a system libcurl, which is usually not installed), so requests are made with the
-- system curl, which ships with Windows 10 and later.

local logging = require("logging")

local debugRC = {}

debugRC.host = "localhost"

-- Everest's default. Only change this if the DebugRCPort setting in Everest was changed too
debugRC.port = 32270

-- Keep the timeout short: a missing debug server should not stall the editor
local timeout = 2

local function urlEncode(value)
    return tostring(value):gsub("([^%w%-%._~])", function(character)
        return string.format("%%%02X", string.byte(character))
    end)
end

local function buildUrl(endpoint, query)
    local url = string.format("http://%s:%d%s", debugRC.host, debugRC.port, endpoint)

    if query then
        local parts = {}

        for key, value in pairs(query) do
            table.insert(parts, string.format("%s=%s", urlEncode(key), urlEncode(value)))
        end

        if #parts > 0 then
            url = url .. "?" .. table.concat(parts, "&")
        end
    end

    return url
end

-- Returns success, response body
function debugRC.request(endpoint, query)
    local url = buildUrl(endpoint, query)
    local command = string.format('curl -s -m %d --connect-timeout 1 "%s" 2>&1', timeout, url)

    local pipe = io.popen(command, "r")

    if not pipe then
        logging.warning("Could not run curl for DebugRC request: " .. url)

        return false
    end

    local body = pipe:read("*a")
    local ok = pipe:close()

    -- Lua 5.1 style popen: close returns nil when the command failed
    if ok == nil then
        logging.warning("DebugRC request failed: " .. url .. " " .. tostring(body))

        return false, body
    end

    return true, body
end

return debugRC
