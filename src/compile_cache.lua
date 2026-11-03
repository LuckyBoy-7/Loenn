-- Caches the Selene -> Lua translation of every module file.
--
-- Lönn source files are written in Selene (a Lua dialect); the Selene parser
-- translates them to plain Lua right before loadstring() sees them. Running that
-- parser over ~4400 files on every start is one of the most expensive parts of
-- startup, so the translated Lua is cached next to the other caches, keyed by
-- the file path, its size and its modification time.
--
-- Nothing else is cached: module execution, requires and asset reads all still
-- happen normally.

local compileCache = {}

local MAGIC = "LONNCC"
local FORMAT = 1

local libenv
local libparse

local cacheDirectory
local cacheDirectoryChecked = false
local fingerprint

local installed = false

compileCache.stats = {
    hits = 0,
    misses = 0,
    writes = 0,
    invalid = 0,
    failures = 0
}

local function enabled()
    local configs = package.loaded["configs"]

    if type(configs) == "table" and configs.debug and configs.debug.disableCompileCache then
        return false
    end

    return true
end

-- Kept free of requires: this runs while modules are being loaded and a nested
-- require could recurse into the module currently being loaded
local function getFingerprint()
    if fingerprint then
        return fingerprint
    end

    local major, minor, revision = love.getVersion()
    local version = love.filesystem.read("assets/VERSION") or "?"
    local seleneVersion = (libenv._selene and libenv._selene._VERSION) or "?"

    -- The fingerprint is stored in a "|" separated header line, so keep the
    -- separators inside it out of that character
    fingerprint = string.format("%d.%d.%d;%s;%s",
        major, minor, revision, (version:gsub("%s+$", "")), tostring(seleneVersion))

    return fingerprint
end

local function ensureDirectory(path)
    local success, lfs = pcall(require, "lib.lfs_ffi")

    if not success or not lfs then
        return false
    end

    local attributes = lfs.attributes(path)

    if attributes and attributes.mode == "directory" then
        return true
    end

    pcall(lfs.mkdir, path)

    attributes = lfs.attributes(path)

    return attributes ~= nil and attributes.mode == "directory"
end

-- Uses the storage directory only once file_locations is loaded; before that the
-- cache is simply not used (a handful of core modules)
local function getCacheDirectory()
    if cacheDirectoryChecked then
        return cacheDirectory
    end

    local fileLocations = package.loaded["file_locations"]

    if type(fileLocations) ~= "table" then
        return nil
    end

    cacheDirectoryChecked = true

    local storageDirectory = fileLocations.getStorageDir()

    if not storageDirectory then
        return nil
    end

    local directory = storageDirectory .. "/Cache/Compiled"

    if ensureDirectory(storageDirectory .. "/Cache") and ensureDirectory(directory) then
        cacheDirectory = directory
    end

    return cacheDirectory
end

local function hashName(name)
    if love.data and love.data.hash then
        local digest = love.data.hash("md5", name)

        return (digest:gsub(".", function(character)
            return string.format("%02x", character:byte())
        end))
    end
end

local function cachePath(name)
    local directory = getCacheDirectory()

    if not directory then
        return nil
    end

    local hashed = hashName(name)

    if not hashed then
        return nil
    end

    return directory .. "/" .. hashed .. ".luac"
end

local function readCacheFile(name, info)
    local path = cachePath(name)

    if not path then
        return nil
    end

    local handle = io.open(path, "rb")

    if not handle then
        return nil
    end

    local content = handle:read("*a")

    handle:close()

    if not content then
        return nil
    end

    local headerEnd = content:find("\n", 1, true)

    if not headerEnd then
        return nil
    end

    local header = content:sub(1, headerEnd - 1)
    local body = content:sub(headerEnd + 1)

    local fields = {}

    for field in header:gmatch("[^|]+") do
        table.insert(fields, field)
    end

    if #fields < 6 then
        return nil
    end

    local valid = fields[1] == MAGIC
        and tonumber(fields[2]) == FORMAT
        and fields[3] == getFingerprint()
        and tonumber(fields[4]) == info.size
        and tonumber(fields[5]) == (info.modtime or 0)
        and fields[6] == name

    if not valid then
        compileCache.stats.invalid = compileCache.stats.invalid + 1

        return nil
    end

    return body
end

local function writeCacheFile(name, info, source)
    local path = cachePath(name)

    if not path then
        return false
    end

    local header = table.concat({
        MAGIC,
        tostring(FORMAT),
        getFingerprint(),
        tostring(info.size),
        tostring(info.modtime or 0),
        name
    }, "|")

    local handle = io.open(path, "wb")

    if not handle then
        compileCache.stats.failures = compileCache.stats.failures + 1

        return false
    end

    handle:write(header .. "\n" .. source)
    handle:close()

    compileCache.stats.writes = compileCache.stats.writes + 1

    return true
end

local function findModuleFile(name)
    local filename = name:gsub("%.", "/")

    for pattern in love.filesystem.getRequirePath():gmatch("[^;]+") do
        local path = pattern:gsub("%?", filename)
        local info = love.filesystem.getInfo(path, "file")

        if info then
            return path, info
        end
    end
end

-- Only mod plugin files are cached: Lönn's own source is loaded straight from
-- disk so editing it always takes effect immediately, even when two edits
-- happen within the same second (mtime has a one second resolution)
local function isCacheable(path, info)
    return path:sub(1, 1) == "$" and info.size >= 256
end

-- Compiles straight from the source file. The cache is only written after the
-- chunk loaded successfully: some plugins produce Lua that does not parse
-- (broken Selene input), and caching that would poison every later start.
local function compileFromSource(path, info, name)
    local raw = love.filesystem.read(path)

    if not raw then
        return nil
    end

    local source = libparse(raw)
    local func, errorMessage = libenv.load(source, path)

    if not func then
        error(string.format("Failed to load module '%s': %s", path, tostring(errorMessage)), 0)
    end

    if enabled() and isCacheable(path, info) then
        writeCacheFile(path, info, source)
    end

    return func(name)
end

local function loadModule(path, info, name)
    if enabled() and isCacheable(path, info) and getCacheDirectory() then
        local cached = readCacheFile(path, info)

        if cached then
            local func = libenv.load(cached, path)

            if func then
                compileCache.stats.hits = compileCache.stats.hits + 1

                return func(name)
            end

            -- Broken or outdated entry: drop it and compile from the source once
            compileCache.stats.invalid = compileCache.stats.invalid + 1

            local cacheFile = cachePath(path)

            if cacheFile then
                os.remove(cacheFile)
            end
        end
    end

    compileCache.stats.misses = compileCache.stats.misses + 1

    return compileFromSource(path, info, name)
end

local function searcher(name)
    local path, info = findModuleFile(name)

    if not path then
        return "\n\tno file found for '" .. name .. "'"
    end

    return function()
        return loadModule(path, info, name)
    end
end

-- Installs the caching searcher in place of the plain Selene searcher.
-- `environment` is the Selene environment the searcher wrapper built.
function compileCache.install(environment)
    if installed then
        return
    end

    installed = true

    libenv = environment
    libparse = environment._selene._parse

    local searchers = package.searchers or package.loaders

    table.insert(searchers, 2, searcher)
end

function compileCache.report()
    local stats = compileCache.stats

    return string.format("hits=%d misses=%d writes=%d stale=%d",
        stats.hits, stats.misses, stats.writes, stats.invalid)
end

return compileCache
