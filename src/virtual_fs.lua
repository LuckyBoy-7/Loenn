-- Resolves Lönn's shared mod namespace ("@ModsCommon@/...") into per-mod mount
-- points ("$ModName$/..."), so every mod archive only has to be mounted once.
--
-- The index is built from the per-mod file lists that mods.lua already caches on
-- disk (Cache/ModFilenames/*.conf), so nothing has to be walked at startup.
--
-- On top of that, the LÖVE functions that accept paths are wrapped: engine level
-- loading (love.graphics.newImage, love.graphics.newImageFont, love.filesystem
-- reads, ...) goes through the same resolution, which keeps third party plugins
-- that build "@ModsCommon@/..." paths working unchanged.
--
-- Every wrapper falls back to the original call when a path cannot be resolved,
-- so with the old double mount enabled (@see configs.editor.mountSharedModView)
-- this module is a pure no-op.

local virtualFs = {}

local prefix = "@ModsCommon@"

virtualFs.prefix = prefix
virtualFs.maxUnresolvedLogs = 25
virtualFs.unresolvedCount = 0

virtualFs.stats = {
    mods = 0,
    resolved = 0,   
    cached = 0,
    listed = 0,
    unresolved = 0
}

-- Originals of the wrapped LÖVE functions. Kept on _G so re-requiring this
-- module (debug reload) can not end up wrapping our own wrappers.
local rawRegistry = rawget(_G, "_virtualFsOriginals")

if not rawRegistry then
    rawRegistry = {}
    rawset(_G, "_virtualFsOriginals", rawRegistry)
end

local function originalFunction(moduleName, functionName)
    local key = moduleName .. "." .. functionName
    local stored = rawRegistry[key]

    if stored then
        return stored
    end

    local module = love[moduleName]
    local func = module and module[functionName]

    if type(func) == "function" then
        rawRegistry[key] = func
    end

    return func
end

local raw = {
    getInfo = originalFunction("filesystem", "getInfo"),
    getDirectoryItems = originalFunction("filesystem", "getDirectoryItems")
}

-- Mount roots: modFolder -> "$ModFolder$"
local mountRoots = {}

-- Filename lists per mod (referenced, not copied: mods.lua already keeps them)
local modFiles = {}

-- Reverse index: relative file path -> mod folder with the highest priority.
-- Without this every lookup would have to stat one candidate per mod that
-- contributes to the parent directory, which is far too slow when a whole
-- atlas tree is enumerated.
local fileOwner = {}

-- Directory index: every directory that exists in some mod. Cheap, and enough
-- to answer getInfo for directory paths without mounting anything.
local dirSet = {}

-- Directory index: directory -> set of direct child names. Built on first use
-- because it is the single biggest part of the index; listing a shared
-- directory never needs any mod to be mounted.
local dirNames

-- Case insensitive fallback for folder mods: lowercased path -> {modFolder, rel}.
-- Windows folder mounts match paths case insensitively, zip mounts do not, and
-- this keeps that behaviour for path lookups that use the wrong case.
local folderOwners = {}

local modIsZip = {}

-- Called with a mod folder name when a path resolves to a mod that might not
-- be mounted yet; set by mods.lua
local mountHandler

-- Ordered list of mod folders, mount order == search order
local modOrder = {}
local modIndex = {}

local resolveCache = {}
local listCache = {}

local installed = false

local configCache

local function config()
    if configCache == nil then
        local success, res = pcall(require, "configs")

        configCache = success and res or false
    end

    return configCache or nil
end

local function logger()
    local success, res = pcall(require, "logging")

    return success and res or nil
end

-- PhysFS collapses duplicate separators and ignores a trailing separator, but
-- it refuses "." and ".." components and backslashes. The index has to behave
-- the same way: plugins do build paths like
-- "objects/Wiki/refill//idle00.png" (a sprite field that ends with a slash),
-- which the merged mount used to accept.
local function normalizeRelative(rel)
    if rel == "" then
        return rel
    end

    if rel:find("//", 1, true) then
        rel = rel:gsub("/+", "/")
    end

    if rel == "." or rel == ".."
        or rel:find("/./", 1, true) or rel:find("/../", 1, true)
        or rel:sub(1, 2) == "./" or rel:sub(1, 3) == "../"
        or rel:sub(-2) == "/." or rel:sub(-3) == "/.." then
        return nil
    end

    if rel:sub(-1) == "/" then
        rel = rel:gsub("/+$", "")
    end

    return rel
end

-- Returns the path relative to "@ModsCommon@", or nil when the path is not part
-- of the shared namespace. The shared root itself maps to "".
local function relativePath(path)
    if path == prefix then
        return ""
    end

    local prefixWithSeparator = prefix .. "/"

    if path:sub(1, #prefixWithSeparator) == prefixWithSeparator then
        return normalizeRelative(path:sub(#prefixWithSeparator + 1))
    end

    return nil
end

local function pathDirectory(rel)
    return rel:match("^(.*)/[^/]*$") or ""
end

local function clearTable(t)
    for key in pairs(t) do
        t[key] = nil
    end
end

local function addDirectory(rel)
    local directory = pathDirectory(rel)

    while true do
        dirSet[directory] = true

        if directory == "" then
            break
        end

        directory = pathDirectory(directory)
    end
end

-- Built from the filename lists on first listing request
local function buildDirectoryNames()
    local namesByDirectory = {}

    for _, modFolder in ipairs(modOrder) do
        local filenames = modFiles[modFolder]

        if filenames then
            local root = mountRoots[modFolder]
            local rootPrefixLength = #root + 1

            for i = 1, #filenames do
                local filename = filenames[i]

                if filename:sub(1, rootPrefixLength) == root .. "/" then
                    local rel = filename:sub(rootPrefixLength + 1)
                    local directory = pathDirectory(rel)
                    local name = rel:sub(#directory + 2)

                    while true do
                        local names = namesByDirectory[directory]

                        if not names then
                            names = {}
                            namesByDirectory[directory] = names
                        end

                        names[name] = true

                        if directory == "" then
                            break
                        end

                        name = directory:match("[^/]+$") or ""
                        directory = pathDirectory(directory)
                    end
                end
            end
        end
    end

    return namesByDirectory
end

local function addFolderOwner(modFolder, rel)
    local key = rel:lower()

    if folderOwners[key] == nil then
        folderOwners[key] = {modFolder = modFolder, rel = rel}
    end
end

-- Rebuilds the file -> mod and directory indexes from all registered filename
-- lists, honouring the mod order (first mounted wins). Only needed when a mod
-- re-registers.
local function rebuildIndexes()
    clearTable(fileOwner)
    clearTable(dirSet)
    clearTable(folderOwners)

    dirNames = nil

    for _, modFolder in ipairs(modOrder) do
        local filenames = modFiles[modFolder]

        if filenames then
            local root = mountRoots[modFolder]
            local rootPrefixLength = #root + 1

            for i = 1, #filenames do
                local filename = filenames[i]

                if filename:sub(1, rootPrefixLength) == root .. "/" then
                    local rel = filename:sub(rootPrefixLength + 1)

                    if fileOwner[rel] == nil then
                        fileOwner[rel] = modFolder
                    end

                    addDirectory(rel)

                    if not modIsZip[modFolder] then
                        addFolderOwner(modFolder, rel)
                    end
                end
            end
        end
    end
end

local function clearCaches()
    clearTable(resolveCache)
    clearTable(listCache)
end

-- Registers (or re-registers) one mod and all of its filenames with the index.
-- `filenames` uses the cached "$ModFolder$/relative/path" form.
function virtualFs.registerMod(modFolder, filenames, isZip)
    local reRegister = modFiles[modFolder] ~= nil

    local root = "$" .. modFolder .. "$"

    mountRoots[modFolder] = root
    modIsZip[modFolder] = isZip or false

    if not modIndex[modFolder] then
        table.insert(modOrder, modFolder)

        modIndex[modFolder] = #modOrder

        virtualFs.stats.mods = #modOrder
    end

    modFiles[modFolder] = filenames

    if filenames and not reRegister then
        local rootPrefixLength = #root + 1

        for i = 1, #filenames do
            local filename = filenames[i]

            if filename:sub(1, rootPrefixLength) == root .. "/" then
                local rel = filename:sub(rootPrefixLength + 1)

                if fileOwner[rel] == nil then
                    fileOwner[rel] = modFolder
                end

                addDirectory(rel)

                if not isZip then
                    addFolderOwner(modFolder, rel)
                end
            end
        end
    end

    if reRegister then
        rebuildIndexes()
    end

    -- Listing index is lazily rebuilt on the next directory listing
    dirNames = nil

    clearCaches()
end

function virtualFs.unregisterMod(modFolder)
    virtualFs.registerMod(modFolder, nil)

    mountRoots[modFolder] = nil
    modFiles[modFolder] = nil

    rebuildIndexes()

    clearCaches()
end

function virtualFs.isMounted(modFolder)
    return mountRoots[modFolder] ~= nil
end

-- Returns the "$ModFolder$/..." path that actually contains `path`, or nil.
function virtualFs.resolve(path)
    if type(path) ~= "string" then
        return nil
    end

    local rel = relativePath(path)

    if not rel or rel == "" then
        return nil
    end

    local cached = resolveCache[rel]

    if cached ~= nil then
        if cached == false then
            return nil
        end

        virtualFs.stats.cached = virtualFs.stats.cached + 1

        return cached
    end

    -- Folder mounts are case insensitive on Windows, so a folder mod may match
    -- a path that only differs in case. Whichever mod comes first in mount
    -- order wins, like it does through the PhysFS search path.
    local owner = fileOwner[rel]
    local folderHit = folderOwners[rel:lower()]
    local firstMod, firstRel, secondMod, secondRel

    if owner and folderHit then
        if modIndex[folderHit.modFolder] < modIndex[owner] then
            firstMod, firstRel = folderHit.modFolder, folderHit.rel
            secondMod, secondRel = owner, rel
        else
            firstMod, firstRel = owner, rel
            secondMod, secondRel = folderHit.modFolder, folderHit.rel
        end

    elseif owner then
        firstMod, firstRel = owner, rel

    elseif folderHit then
        firstMod, firstRel = folderHit.modFolder, folderHit.rel
    end

    for i = 1, 2 do
        local modFolder = i == 1 and firstMod or secondMod

        if modFolder then
            local relPath = i == 1 and firstRel or secondRel

            -- Lazy loading: the owning mod may not be mounted yet
            if mountHandler then
                mountHandler(modFolder)
            end

            local candidate = mountRoots[modFolder] .. "/" .. relPath

            if raw.getInfo(candidate) then
                resolveCache[rel] = candidate

                virtualFs.stats.resolved = virtualFs.stats.resolved + 1

                return candidate
            end
        end
    end

    -- Directory paths have no file owner; existence is answered by
    -- virtualFs.isDirectory from the directory set instead
    if dirSet[rel] then
        return nil
    end

    resolveCache[rel] = false

    virtualFs.logUnresolved(path)

    return nil
end

-- Merged listing of "@ModsCommon@/<directory>": union of every mod's entries,
-- deduplicated by name. Comes straight from the filename index, so no mod has
-- to be mounted for this.
function virtualFs.list(path)
    local rel = relativePath(path)

    if rel == nil then
        return nil
    end

    local cached = listCache[rel]

    if cached ~= nil then
        if cached == false then
            return nil
        end

        return cached
    end

    if not dirNames then
        dirNames = buildDirectoryNames()
    end

    local names = {}
    local entries = dirNames[rel]

    if entries then
        for name in pairs(entries) do
            table.insert(names, name)
        end
    end

    if #names == 0 then
        listCache[rel] = false

        return nil
    end

    table.sort(names)

    listCache[rel] = names

    virtualFs.stats.listed = virtualFs.stats.listed + 1

    return names
end

function virtualFs.isDirectory(path)
    if type(path) ~= "string" then
        return false
    end

    local rel = relativePath(path)

    return rel ~= nil and dirSet[rel] ~= nil
end

function virtualFs.setMountHandler(handler)
    mountHandler = handler
end

function virtualFs.markMounted()
    virtualFs.stats.mounted = (virtualFs.stats.mounted or 0) + 1
end

function virtualFs.logUnresolved(path)
    local configs = config()

    if configs and configs.editor and configs.editor.logUnresolvedVirtualPaths == false then
        return
    end

    virtualFs.stats.unresolved = virtualFs.stats.unresolved + 1

    if virtualFs.unresolvedSeen then
        if virtualFs.unresolvedSeen[path] then
            return
        end
    else
        virtualFs.unresolvedSeen = {}
    end

    virtualFs.unresolvedSeen[path] = true

    if virtualFs.unresolvedCount >= virtualFs.maxUnresolvedLogs then
        return
    end

    virtualFs.unresolvedCount = virtualFs.unresolvedCount + 1

    local logging = logger()

    if logging then
        -- Many of these are lookups that would fail in a merged view too (the
        -- base game atlas is not part of the mod namespace), so keep them out
        -- of the default log level
        logging.debug(string.format("[virtual_fs] Could not resolve '%s'", path))
    end
end

local wrappedFunctions = {}

local function wrapResolvingFunction(moduleName, functionName)
    local module = love[moduleName]

    if type(module) ~= "table" then
        return
    end

    local key = moduleName .. "." .. functionName
    local func = module[functionName]

    if type(func) ~= "function" or wrappedFunctions[key] then
        return
    end

    originalFunction(moduleName, functionName)

    wrappedFunctions[key] = true

    module[functionName] = function(path, ...)
        if type(path) == "string" then
            local resolved = virtualFs.resolve(path)

            if resolved then
                return func(resolved, ...)
            end
        end

        return func(path, ...)
    end
end

-- Installs the LÖVE wrappers. Must run before any plugin code is loaded.
function virtualFs.install()
    if installed then
        return
    end

    installed = true
    virtualFs.stats.installed = true

    for _, name in ipairs({"read", "newFile", "getRealDirectory", "getSize", "lines", "load"}) do
        wrapResolvingFunction("filesystem", name)
    end

    for _, name in ipairs({"newImage", "newImageFont", "newFont", "newShader"}) do
        wrapResolvingFunction("graphics", name)
    end

    wrapResolvingFunction("image", "newImageData")
    wrapResolvingFunction("audio", "newSource")

    local fs = love.filesystem
    local rawGetInfo = raw.getInfo
    local rawGetDirectoryItems = raw.getDirectoryItems

    fs.getInfo = function(path, ...)
        if type(path) == "string" and relativePath(path) then
            if path == prefix then
                return {type = "directory"}
            end

            local resolved = virtualFs.resolve(path)

            if resolved then
                return rawGetInfo(resolved, ...)
            end

            -- Directories that only contain subdirectories are known from the
            -- index alone, and answering them must not mount anything
            if virtualFs.isDirectory(path) then
                return {type = "directory"}
            end
        end

        return rawGetInfo(path, ...)
    end

    fs.getDirectoryItems = function(path)
        if type(path) == "string" and relativePath(path) then
            local names = virtualFs.list(path)

            if names then
                return names
            end
        end

        return rawGetDirectoryItems(path)
    end
end

function virtualFs.report()
    local logging = logger()
    local message = string.format(
        "[virtual_fs] mods=%d mounted=%d resolved=%d cached=%d listed=%d unresolved=%d sharedMount=%s",
        virtualFs.stats.mods,
        virtualFs.stats.mounted or 0,
        virtualFs.stats.resolved,
        virtualFs.stats.cached,
        virtualFs.stats.listed,
        virtualFs.stats.unresolved,
        tostring((config() and config().editor.mountSharedModView) or false)
    )

    if logging then
        logging.info(message)
    else
        print(message)
    end
end

return virtualFs
