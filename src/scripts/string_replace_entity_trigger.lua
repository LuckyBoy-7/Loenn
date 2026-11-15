-- Ported from Aurora's Loenn Plugin: replaces a substring inside one attribute of entities and/or
-- triggers whose type name matches. This is effectively a conditional Change Attributes script.

local namePreviewFocus = require("ui.name_preview_focus")

local script = {}

script.name = "stringReplaceEntityTrigger"
script.title = "String Replace in Entity/Trigger"
script.description = "Replaces a substring in one attribute of matching entities and/or triggers."

script.fieldOrder = {"name", "attr", "from", "to", "entities", "triggers"}
script.defaultData = {
    name = "",
    attr = "",
    from = "",
    to = "",
    entities = true,
    triggers = false
}

script.fieldInformation = {
    name = {editable = true, onFocus = namePreviewFocus.onFocus, onBlur = namePreviewFocus.onBlur},
    attr = {editable = true}
}

script.tooltips = {
    name = "Entity or trigger type name to match, case-sensitive.",
    attr = "Attribute name to edit, case-sensitive (for example: texture, directory, message).",
    from = "Substring to find inside the attribute value.",
    to = "Replacement text.",
    entities = "Apply to matching entities.",
    triggers = "Apply to matching triggers."
}

local function replaceString(value, from, to)
    if type(value) ~= "string" then
        return value
    end

    -- Treat the search text as a literal substring, not a Lua pattern.
    local pattern = from:gsub("%p", "%%%0")
    local replacement = to:gsub("%%", "%%%%")

    return (value:gsub(pattern, replacement))
end

local function replaceInList(items, args)
    for _, item in ipairs(items or {}) do
        if item._name == args.name then
            local value = item[args.attr]

            if type(value) == "string" then
                item[args.attr] = replaceString(value, args.from, args.to)
            end
        end
    end
end

function script.run(room, args)
    if not room or not args.name or args.name == "" or not args.attr or args.attr == "" then
        return
    end

    if not args.from or args.from == "" then
        return
    end

    local to = args.to or ""

    if args.entities then
        replaceInList(room.entities, {
            name = args.name,
            attr = args.attr,
            from = args.from,
            to = to
        })
    end

    if args.triggers then
        replaceInList(room.triggers, {
            name = args.name,
            attr = args.attr,
            from = args.from,
            to = to
        })
    end
end

return script
