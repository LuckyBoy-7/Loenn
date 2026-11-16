-- Settings for the in-editor font and the way trigger labels are drawn.
-- Previously provided by the FontLoennPlugin mod.

return {
    -- Internally selected by the editor; no longer exposed as a setting.
    useHiresPixelFont = true,
    autoSwitchFont = false,

    -- Trigger text
    addShadowToFont = true,
    triggerFontPath = "assets/fonts/RenogareSoft-Regular.ttf",
    textSize = 1.0,
    highlightSelectedTriggerText = true,
    highlightColor = "ffff00",
    selectTriggerByClickingText = false,

    extrudeOverlappingTriggerText = true,
    ignoreOutOfRoomTextExtruding = true
}
