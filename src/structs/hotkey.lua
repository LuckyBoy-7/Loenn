local keyboardHelper = require("utils.keyboard")

local defaultScope = "global"
local defaultScopes = {defaultScope}

local specialKeyAliases = {
    -- "+" is not a LÖVE key name: on the main keyboard it is "=" with shift, on the keypad it
    -- is "kp+". Accept both and make shift optional so Ctrl + Plus works as expected.
    plus = function()
        return love.keyboard.isDown("=") or love.keyboard.isDown("kp+")
    end,
    minus = "-",
    kpplus = "kp+",
    kpminus = "kp-",
}

-- Modifiers that must not be rejected by the exact-match check when this alias is used, but
-- are also not required to be held.
local optionalAliasModifiers = {
    plus = {"shift"}
}

local modifierKeyFunctions = keyboardHelper.nameToModifierFunction

local hotkeyStruct = {}

-- TODO - Validate that the key constant exists?
-- Exact match means that ctrl + s will only be valid on ctrl + s, and not ctrl + alt + s and so on
function hotkeyStruct.sanitize(activator, exactMatch)
    local activatorType = type(activator)

    if activatorType == "table" then
        return activator
    end

    if not activator then
        return false
    end

    exactMatch = exactMatch == nil or exactMatch

    local parts = string.split(activator, "+")
    local activators = {}

    local usedModifiers = {}

    for i, part <- parts do
        part = part:match("^%s*(.-)%s*$"):lower()

        if specialKeyAliases[part] then
            table.insert(activators, specialKeyAliases[part])

            local optionalModifiers = optionalAliasModifiers[part]

            if optionalModifiers then
                for _, name in ipairs(optionalModifiers) do
                    local func = modifierKeyFunctions[name]

                    if func then
                        usedModifiers[func] = true
                    end
                end
            end

        elseif modifierKeyFunctions[part] then
            local func = modifierKeyFunctions[part]

            table.insert(activators, func)

            usedModifiers[modifierKeyFunctions[part]] = true

        else
            table.insert(activators, part)
        end
    end

    if exactMatch then
        for name, func in pairs(modifierKeyFunctions) do
            if not usedModifiers[func] then
                -- Make sure we don't add any aliases for the function either
                usedModifiers[func] = true

                table.insert(activators, function() return not func() end)
            end
        end
    end

    return activators
end

function hotkeyStruct.hotkeyActive(hotkey)
    if hotkeyStruct.disabled(hotkey) then
        return false
    end

    for i, part in ipairs(hotkey.activator) do
        if type(part) == "function" then
            if not part() then
                return false
            end

        else
            if not love.keyboard.isDown(part) then
                return false
            end
        end
    end

    return true
end

function hotkeyStruct.callbackIfActive(hotkey, ...)
    if hotkey:active() then
        hotkey(...)
    end
end

function hotkeyStruct.callbackFirstActive(hotkeys, scopes, ...)
    scopes = scopes or defaultScopes

    local scopeLookup = table.flip(scopes)

    for i, hotkey in ipairs(hotkeys) do
        -- Skip any hotkeys that doesn't match specified scope
        if scopeLookup[hotkey.scope] then
            if hotkey:active() then
                hotkey(...)

                return true, i
            end
        end
    end

    return false, false
end

function hotkeyStruct.disabled(hotkey)
    return not hotkey.activator or not hotkey.enabled
end

local hotkeyMt = {}

hotkeyMt.__index = {}
hotkeyMt.__index.active = hotkeyStruct.hotkeyActive
hotkeyMt.__index.callbackIfActive = hotkeyStruct.callbackIfActive

function hotkeyMt:__call(...)
    self:callback(...)
end

function hotkeyStruct.createHotkey(scope, activator, callback, options)
    local hotkey = {
        _type = "hotkey",
        _rawActivator = activator
    }

    hotkey.scope = scope or defaultScope
    hotkey.callback = callback
    hotkey.activator = hotkeyStruct.sanitize(activator)
    hotkey.options = options
    hotkey.enabled = true

    return setmetatable(hotkey, hotkeyMt)
end

return hotkeyStruct