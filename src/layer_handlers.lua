local utils = require("utils")

local entityHandler = require("entities")
local triggerHandler = require("triggers")
local decalHandler = require("decals")
local tilesHandler = require("tiles")
local objectTileHandler = require("object_tile_placement")

local layerHandlers = {}

layerHandlers.layerHandlers = {
    entities = entityHandler,
    triggers = triggerHandler,
    decalsFg = decalHandler,
    decalsBg = decalHandler,
    tilesFg = tilesHandler,
    tilesBg = tilesHandler,
    sceneryObj = objectTileHandler
}

function layerHandlers.getHandler(layer)
    return layerHandlers.layerHandlers[layer]
end

return layerHandlers