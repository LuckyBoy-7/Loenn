-- Export To Zip: updates the version in the current map mod's everest.yaml and writes the whole mod
-- folder into a zip file on the desktop.

local utils = require("utils")
local filesystem = require("utils.filesystem")
local notifications = require("ui.notification")
local zipWriter = require("utils.zip_writer")

local script = {}

script.name = "exportToZip"
script.title = "Export To Zip"
script.description = "Updates the mod version and exports the whole mod folder to a zip file."

local function readTextFile(path)
    local handle = io.open(path, "rb")

    if not handle then
        return nil
    end

    local content = handle:read("*a")

    handle:close()

    return content
end

local function writeTextFile(path, content)
    local handle = io.open(path, "wb")

    if not handle then
        return false
    end

    handle:write(content)
    handle:close()

    return true
end

local function readVersion(everestPath)
    local content = readTextFile(everestPath)

    if not content then
        return nil
    end

    return content:match("Version:%s*([^\r\n]+)")
end

local function updateVersion(everestPath, version)
    local content = readTextFile(everestPath)

    if not content then
        return false, "could not read everest.yaml"
    end

    local replaced

    content, replaced = content:gsub("(Version:%s*)([^\r\n]+)", function(prefix)
        return prefix .. version
    end, 1)

    if replaced == 0 then
        return false, "everest.yaml has no Version field"
    end

    return writeTextFile(everestPath, content)
end

local function collectFiles(root)
    local files = {}

    local function walk(relative)
        local directory = relative == "" and root or utils.joinpath(root, relative)

        for name in utils.listDir(directory) do
            if name ~= "." and name ~= ".." then
                local childRelative = relative == "" and name or relative .. "/" .. name
                local childPath = utils.joinpath(root, childRelative)
                local attributes = filesystem.pathAttributes(childPath)

                if attributes and attributes.mode == "directory" then
                    walk(childRelative)

                elseif attributes then
                    table.insert(files, {name = childRelative, path = childPath})
                end
            end
        end
    end

    walk("")

    return files
end

local function getDesktopFolder()
    local profile = os.getenv("USERPROFILE")

    if profile then
        local desktop = utils.joinpath(profile, "Desktop")

        if filesystem.isDirectory(desktop) then
            return desktop
        end
    end

    local home = os.getenv("HOME")

    if home then
        local desktop = utils.joinpath(home, "Desktop")

        if filesystem.isDirectory(desktop) then
            return desktop
        end
    end
end

local function exportMod(modFolder, modName, version)
    local everestPath = utils.joinpath(modFolder, "everest.yaml")

    if not version or version == "" or version:find("[\r\n]") then
        notifications.notify("Export To Zip: please enter a valid version.")

        return false
    end

    local success, reason = updateVersion(everestPath, version)

    if not success then
        notifications.notify("Export To Zip: " .. tostring(reason))

        return false
    end

    local desktop = getDesktopFolder()

    if not desktop then
        notifications.notify("Export To Zip: could not find the desktop folder.")

        return false
    end

    local destination = utils.joinpath(desktop, modName .. ".zip")
    local files = collectFiles(modFolder)

    if #files == 0 then
        notifications.notify("Export To Zip: the mod folder is empty.")

        return false
    end

    local zipped, zipReason = zipWriter.write(destination, files)

    if not zipped then
        notifications.notify("Export To Zip: " .. tostring(zipReason))

        return false
    end

    notifications.notify(string.format("Export To Zip: exported %d files to '%s'.", #files, destination))

    return true
end

function script.open()
    local tilesetDefaults = require("tileset_defaults")
    local scriptsPanel = require("ui.windows.scripts_panel")
    local modFolder, modName = tilesetDefaults.getMapModFolder()

    if not modFolder then
        notifications.notify("Export To Zip: the current map is not inside a valid, unpacked Mod folder.")

        return
    end

    local everestPath = utils.joinpath(modFolder, "everest.yaml")
    local version = readVersion(everestPath) or "1.0.0"

    local panelScript = {
        name = script.name .. "Panel",
        title = script.title,
        fieldOrder = {"version"},
        defaultData = {
            version = version
        },
        fieldInformation = {
            version = {
                displayName = "Version",
                tooltipText = "Version written to everest.yaml before exporting."
            }
        }
    }

    scriptsPanel.open(panelScript, nil, function(values)
        return exportMod(modFolder, modName, utils.trim(values.version or ""))
    end, {
        extraButtons = {
            {
                text = "Close Window",
                callback = function()
                    scriptsPanel.close()
                end
            }
        }
    })
end

return script
