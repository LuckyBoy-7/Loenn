-- Load user settings and default to internal settings
-- Should be easily accessible from code

local utils = require("utils")
local config = require("utils.config")
local fileLocations = require("file_locations")

local configs = config.readConfig(fileLocations.getSettingsPath())
local defaultConfigData = require("default_config")

local mergedDefaults = utils.mergeTables(defaultConfigData, configs)

-- The first version of the previous-tool hotkey used Tab, which also became the toolbar toggle
-- default. Old settings files therefore contain the same key twice; split them once.
if configs.hotkeys
    and configs.hotkeys.togglePreviousTool == "tab"
    and configs.hotkeys.toggleToolbar == "tab" then
    configs.hotkeys.togglePreviousTool = "x"
    mergedDefaults = true
end

if mergedDefaults then
    config.writeConfig(configs, true)
end

return configs