local noRefill = {}

noRefill.name = "noRefillTrigger"
noRefill.placements = {
    {
        name = "disable_refills",
        data = {
            state = true
        }
    },
    {
        name = "enable_refills",
        data = {
            state = false
        }
    }
}

-- Extended text: whether refills are enabled or disabled
noRefill._lonnExt_extendedText = function(trigger)
    return trigger.state and "On" or "Off"
end

return noRefill