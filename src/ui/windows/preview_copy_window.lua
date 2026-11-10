-- Copy window for the Preview tool: either copy only the relative path, or also copy the image
-- (and the animation frames sharing its name) into the current map's mod.

local ui = require("ui")
local uiElements = require("ui.elements")
local uiRoot = require("ui.ui_root")
local widgetUtils = require("ui.widgets.utils")
local form = require("ui.forms.form")
local languageRegistry = require("language_registry")
local utils = require("utils")
local filesystem = require("utils.filesystem")
local modHandler = require("mods")
local virtualFs = require("virtual_fs")
local notifications = require("ui.notification")
local tilesetDefaults = require("tileset_defaults")

local previewCopyWindow = {}

local panelGroup
local currentWindow

local GAMEPLAY_ROOT = "Graphics/Atlases/Gameplay"
local COLOR_GRADING_ROOT = "Graphics/ColorGrading"

local function normalizeRelativePath(path)
    path = utils.trim(path or "")
    path = string.gsub(path, "\\", "/")
    path = string.gsub(path, "^/+", "")
    path = string.gsub(path, "/+$", "")
    path = string.gsub(path, "//+", "/")

    return path
end

local function pathRoots(copyPath, layer)
    if layer == "colorGrading" then
        -- Color grading files are copied below Graphics/ColorGrading and the entered relative
        -- path replaces their original folder completely
        return COLOR_GRADING_ROOT, ""
    end

    -- Gameplay layers keep their first folder (objects/, bgs/, ...) and copy everything below it
    local firstFolder = string.match(copyPath, "^([^/]+)/")

    return GAMEPLAY_ROOT, firstFolder
end

-- All files that belong to the same image: the file itself plus numbered animation frames
local function getSourceFiles(sourceFile, sourceRelative, atlasRoot)
    local modFolder = string.match(sourceFile, "^%$([^%$]+)%$")

    if not modFolder then
        return {}
    end

    local sourceDirectory = string.match(sourceRelative, "^(.*)/[^/]*$") or ""    local baseName = string.gsub(string.match(sourceRelative, "([^/]*)$") or "", "%.png$", "")

    -- Frames are usually the same name plus a number (default00, default01, ...): strip the
    -- trailing number so every frame sharing the prefix is copied
    local prefix = string.gsub(baseName, "%d+$", "")

    if prefix == "" then
        prefix = baseName
    end

    local escapedPrefix = string.gsub(prefix, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")

    local folder = atlasRoot
    if sourceDirectory ~= "" then
        folder = folder .. "/" .. sourceDirectory
    end

    local files = modHandler.findModFiletype(folder, "png", {modFolder})
    local result = {}

    for _, filename in ipairs(files) do
        local fileNameOnly = string.match(filename, "([^/]+)$") or ""
        local stem = string.gsub(fileNameOnly, "%.png$", "")

        if stem == prefix or string.match(stem, "^" .. escapedPrefix .. "%d+$") then
            table.insert(result, {filename = filename, name = fileNameOnly})
        end
    end

    return result, modFolder
end

-- Path the copied object gets inside the target folder, e.g. objects/Lucky_boy/TestMap/default
local function getTargetCopyPath(params, relativePath)
    local _, layerFolder = pathRoots(params.copyPath, params.layer)
    local baseName = string.match(params.copyPath, "([^/]*)$") or ""
    local parts = {}

    if layerFolder and layerFolder ~= "" then
        table.insert(parts, layerFolder)
    end

    table.insert(parts, relativePath)
    table.insert(parts, baseName)

    return table.concat(parts, "/")
end

local function copyFiles(params, relativePath)
    local atlasRoot, layerFolder = pathRoots(params.copyPath, params.layer)
    local sourceFiles, sourceModFolder = getSourceFiles(params.sourceFile, params.copyPath, atlasRoot)
    if #sourceFiles == 0 then
        return 0, {}
    end

    local mapModFolder, mapModName = tilesetDefaults.getMapModFolder()

    if not mapModFolder then
        return 0, {}
    end

    local targetPath = getTargetCopyPath(params, relativePath)
    local relativeTargetDirectory = atlasRoot
    local mountName = mapModName:gsub("%.", "_")

    if layerFolder and layerFolder ~= "" then
        relativeTargetDirectory = relativeTargetDirectory .. "/" .. layerFolder
    end

    relativeTargetDirectory = relativeTargetDirectory .. "/" .. relativePath

    local targetDirectory = utils.joinpath(mapModFolder, relativeTargetDirectory)

    local written = 0
    local copied = {}

    for _, source in ipairs(sourceFiles) do
        local bytes = utils.readAll(source.filename, "rb", true)

        if bytes then
            local target = utils.joinpath(targetDirectory, source.name)

            filesystem.mkpath(filesystem.dirname(target))

            local handle = utils.getFileHandle(target, "wb")

            if handle then
                handle:write(bytes)
                handle:close()

                written = written + 1

                local resource

                if params.layer ~= "colorGrading" then
                    resource = (relativeTargetDirectory:gsub("^Graphics/Atlases/Gameplay/", ""))
                        .. "/" .. string.gsub(source.name, "%.png$", "")
                end

                table.insert(copied, {
                    file = utils.convertToUnixPath(string.format("$%s$/%s/%s", mountName, relativeTargetDirectory, source.name)),
                    resource = resource,
                    prefix = targetPath
                })
            end
        end
    end

    return written, copied, targetDirectory
end

function previewCopyWindow.open(params)
    if not params then
        return
    end

    local language = languageRegistry.getLanguage()
    local strings = language.ui.preview_copy_window

    local function finish(text)
        if currentWindow then
            widgetUtils.closeWindow(currentWindow)
            currentWindow = nil
        end

        if text then
            notifications.notify(text)
        end
    end

    local buttons = {
        {
            text = tostring(strings.copy_path_and_file),
            formMustBeValid = true,
            callback = function(formFields)
                local values = form.getFormData(formFields)
                local relativePath = normalizeRelativePath(values.relativePath)

                if relativePath == "" then
                    love.system.setClipboardText(params.copyPath)
                    finish(string.format(tostring(strings.copied_path), params.copyPath))

                    return
                end

                -- The copied object now lives at the target path, so that is what gets copied
                local targetPath = getTargetCopyPath(params, relativePath)

                love.system.setClipboardText(targetPath)

                local written, copied, targetDirectory = copyFiles(params, relativePath)

                if written > 0 then
                    local _, layerFolder = pathRoots(params.copyPath, params.layer)

                    require("ui.windows.tools").reloadPreviewCopiedFiles(copied, layerFolder or "")

                    finish(string.format(tostring(strings.copied_files), written, targetPath))

                    if values.showExplorer and targetDirectory then
                        love.system.openURL("file://" .. utils.convertToUnixPath(targetDirectory))
                    end

                else
                    finish(string.format(tostring(strings.copy_failed), targetPath))
                end
            end
        },
        {
            text = tostring(strings.only_copy_path),
            callback = function()
                love.system.setClipboardText(params.copyPath)
                finish(string.format(tostring(strings.copied_path), params.copyPath))
            end
        }
    }

    local fieldInformation = {
        relativePath = {
            displayName = tostring(strings.relative_path),
            tooltipText = tostring(strings.relative_path_tooltip)
        },
        showExplorer = {
            displayName = tostring(strings.show_explorer),
            tooltipText = tostring(strings.show_explorer_tooltip)
        }
    }

    local body = form.getForm(buttons, {
        relativePath = "YourName/YourMod/",
        showExplorer = true
    }, {
        fields = fieldInformation,
        fieldOrder = {"relativePath", "showExplorer"},
        formFieldChanged = function() end
    })

    if currentWindow then
        widgetUtils.closeWindow(currentWindow)
        currentWindow = nil
    end

    ui.runLate(function()
        local window = uiElements.window(tostring(strings.title), body)

        currentWindow = window

        local parent = uiRoot.getWindowGroup and uiRoot.getWindowGroup() or ui.root

        parent:addChild(window)

        widgetUtils.addWindowCloseButton(window, function(w)
            currentWindow = nil
            w:removeSelf()
            ui.root:recollect()

            return true
        end)
        widgetUtils.preventOutOfBoundsMovement(window)
        widgetUtils.consumeKeyboardEvents(window)
        form.prepareScrollableWindow(window)

        window:layout()
        window:layoutLate()
        widgetUtils.centerWindow(window)

        if ui.root then
            ui.root:recollect()
        end
    end)
end

function previewCopyWindow.getWindow()
    panelGroup = uiElements.group({})

    return panelGroup
end

return previewCopyWindow
