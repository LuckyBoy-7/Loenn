local utils = require("utils")
local language = require("utils.lang")
local pluginLoader = require("plugin_loader")
local modHandler = require("mods")
local configs = require("configs")

local languageRegistry = {}

languageRegistry.languages = {}
languageRegistry.language = {}
languageRegistry.currentLanguageName = nil
languageRegistry.fallbackLanguage = {}
languageRegistry.fallbackLanguageName = nil

function languageRegistry.setLanguage(name)
    languageRegistry.currentLanguageName = name
    languageRegistry.language = languageRegistry.languages[name]
end

function languageRegistry.getLanguage()
    -- If language is completely missing
    if not languageRegistry.language then
        return languageRegistry.fallbackLanguage
    end

    return languageRegistry.language
end

function languageRegistry.getLanguageDisplayName(name, data)
    data = data or languageRegistry.languages[name]

    if data and data.language and data.language.name and data.language.name._exists then
        return tostring(data.language.name)
    end

    return name
end

function languageRegistry.getLanguageOptions()
    local options = {}
    local seenNames = {}
    local seenLabels = {}

    for name, data in pairs(languageRegistry.languages or {}) do
        local displayName = languageRegistry.getLanguageDisplayName(name, data)

        if not seenNames[name] and not seenLabels[displayName] then
            seenNames[name] = true
            seenLabels[displayName] = true

            table.insert(options, {
                displayName,
                name
            })
        end
    end

    table.sort(options, function(a, b)
        return string.lower(a[1]) < string.lower(b[1])
    end)

    return options
end

function languageRegistry.setFallbackLanguage(name)
    languageRegistry.fallbackLanguageName = name
    languageRegistry.fallbackLanguage = languageRegistry.languages[name]

    language.setFallback(languageRegistry.fallbackLanguage)
end

function languageRegistry.loadLanguageFile(filename)
    local name = utils.stripExtension(utils.filename(filename, "/"))
    local languageData = languageRegistry.languages[name]

    languageRegistry.languages[name] = language.loadFile(filename, languageData)
end

function languageRegistry.unloadFiles()
    languageRegistry.languages = {}
end

function languageRegistry.loadInternalFiles()
    pluginLoader.loadPlugins("lang", nil, languageRegistry.loadLanguageFile, false, "lang")
    pluginLoader.loadPlugins("ui/lang", nil, languageRegistry.loadLanguageFile, false, "lang")
end

function languageRegistry.loadExternalFiles()
    local filenames = modHandler.findLanguageFiles("lang")

    pluginLoader.loadPlugins(filenames, nil, languageRegistry.loadLanguageFile, true, "lang")
end

return languageRegistry