-- Registry of the available scripts. Adding a script is one entry here.

local registry = {}

registry.scripts = {
    require("scripts/change_filler_to_room"),
    require("scripts/change_attributes"),
    require("scripts/string_replace_entity_trigger"),
    require("scripts/auto_add_filler"),
    require("scripts/flip_room"),
    require("scripts/tile_credits"),
    require("scripts/decal_credits"),
    require("scripts/auto_bg_tiles"),
    require("scripts/create_template_mod"),
    require("scripts/export_to_zip"),
    require("scripts/transfer_used_decals")
}

function registry.getScripts()
    return registry.scripts
end

function registry.getByName(name)
    for _, script in ipairs(registry.scripts) do
        if script.name == name then
            return script
        end
    end
end

return registry
