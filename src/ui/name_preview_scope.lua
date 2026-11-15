-- Scope used by Preview -> Name when it is opened from a Change Attributes form.
-- nil means the whole map, a table of rooms limits the list to those rooms.

local scope = {}

local rooms = nil

function scope.setRooms(value)
    rooms = value
end

function scope.getRooms()
    return rooms
end

function scope.clear()
    rooms = nil
end

return scope
