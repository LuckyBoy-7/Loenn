-- Minimal ZIP writer (stored / uncompressed entries). Used by the Export to Zip script so the
-- editor does not depend on external zip tools.

local bit = require("bit")

local zipWriter = {}

local crcTable

local function getCrcTable()
    if not crcTable then
        crcTable = {}

        for i = 0, 255 do
            local value = i

            for _ = 1, 8 do
                if value % 2 == 1 then
                    value = bit.bxor(bit.rshift(value, 1), 0xEDB88320)

                else
                    value = bit.rshift(value, 1)
                end
            end

            crcTable[i] = value
        end
    end

    return crcTable
end

local function crc32(data)
    local table = getCrcTable()
    local crc = 0xFFFFFFFF

    for i = 1, #data do
        local index = bit.band(bit.bxor(crc, data:byte(i)), 0xFF)
        crc = bit.bxor(table[index], bit.rshift(crc, 8))
    end

    return bit.band(bit.bxor(crc, 0xFFFFFFFF), 0xFFFFFFFF)
end

local function u16(value)
    value = bit.band(value, 0xFFFF)

    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function u32(value)
    value = bit.band(value, 0xFFFFFFFF)

    local result = {}

    for _ = 1, 4 do
        table.insert(result, string.char(value % 256))
        value = math.floor(value / 256)
    end

    return table.concat(result)
end

local function dosDateTime()
    local time = os.date("*t")
    local dosTime = time.hour * 2048 + time.min * 32 + math.floor(time.sec / 2)
    local dosDate = math.max(0, time.year - 1980) * 512 + time.month * 32 + time.day

    return dosTime, dosDate
end

local function readFile(path)
    local handle = io.open(path, "rb")

    if not handle then
        return nil, "could not open " .. path
    end

    local data = handle:read("*a")

    handle:close()

    return data
end

-- entries: array of { name = "relative/path", path = "absolute/path" }
function zipWriter.write(destination, entries)
    local output = io.open(destination, "wb")

    if not output then
        return false, "could not create " .. destination
    end

    local time, date = dosDateTime()
    local centralEntries = {}
    local offset = 0

    for _, entry in ipairs(entries) do
        local data, reason = readFile(entry.path)

        if not data then
            output:close()

            return false, reason
        end

        local name = entry.name
        local crc = crc32(data)
        local size = #data

        local localHeader = table.concat({
            u32(0x04034b50),
            u16(20),
            u16(0x0800),
            u16(0),
            u16(time),
            u16(date),
            u32(crc),
            u32(size),
            u32(size),
            u16(#name),
            u16(0),
            name
        })

        output:write(localHeader)
        output:write(data)

        table.insert(centralEntries, {
            name = name,
            crc = crc,
            size = size,
            offset = offset
        })

        offset = offset + #localHeader + size
    end

    local centralStart = offset
    local centralData = {}

    for _, entry in ipairs(centralEntries) do
        table.insert(centralData, table.concat({
            u32(0x02014b50),
            u16(20),
            u16(20),
            u16(0x0800),
            u16(0),
            u16(time),
            u16(date),
            u32(entry.crc),
            u32(entry.size),
            u32(entry.size),
            u16(#entry.name),
            u16(0),
            u16(0),
            u16(0),
            u16(0),
            u32(0),
            u32(entry.offset),
            entry.name
        }))
    end

    local central = table.concat(centralData)

    output:write(central)

    output:write(table.concat({
        u32(0x06054b50),
        u16(0),
        u16(0),
        u16(#centralEntries),
        u16(#centralEntries),
        u32(#central),
        u32(centralStart),
        u16(0)
    }))

    output:close()

    return true
end

return zipWriter
