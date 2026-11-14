-- Added for plugins to use
-- Lönn itself does not need this

local utils = require("utils")
local configs = require("configs")
local pluginLoader = require("plugin_loader")
local modHandler = require("mods")
local logging = require("logging")

local libraries = {}

libraries.registeredLibraries = nil

function libraries.initDefaultRegistry(t)
    libraries.registeredLibraries = t or {}
end

function libraries.registerLibrary(filename, registerAt, verbose)
    -- Use verbose flag or default to logPluginLoading from config
    verbose = verbose or verbose == nil and configs.debug.logPluginLoading
    registerAt = registerAt or libraries.registeredLibraries

    local pathNoExt = utils.stripExtension(filename)
    local library = utils.rerequire(pathNoExt)

    if type(library) ~= "table" then
        return
    end

    local name = library.name or pathNoExt

    registerAt[name] = library

    if verbose then
        logging.info("Registered library '" .. name .. "' from '" .. filename .."'")
    end
end


function libraries.loadLibraries(path, registerAt)
    pluginLoader.loadPlugins(path, registerAt, libraries.registerLibrary)
end

function libraries.loadInternalLibraries(registerAt)
    return libraries.loadLibraries("libraries", registerAt)
end

function libraries.loadExternalLibraries(registerAt)
    local filenames = modHandler.findPlugins("libraries")
    local registered = {}

    for _, filename in ipairs(filenames) do
        registered[filename] = true
    end

    -- Custom wipe dropdown registrations live in the legacy "Loenn/libraries" folder and are
    -- explicitly loaded even when editor plugins are isolated.
    for _, filename in ipairs(modHandler.findWipeDropdownLibraries()) do
        if not registered[filename] then
            table.insert(filenames, filename)
            registered[filename] = true
        end
    end

    return libraries.loadLibraries(filenames, registerAt)
end

libraries.initDefaultRegistry()

return libraries