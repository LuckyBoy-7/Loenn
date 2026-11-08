local info = debug.getinfo(1)
local source = info.source
local parts = string.split(source, "/")()

local libPrefix = table.concat(parts, "/", 1, 2)
return {
    __themeName = "WindowsXpVaporfontless",
    iconsPath = "ui/themes/light/icons/",
    horizontalLine = {
        color = {0.3215, 0.1843, 0.6627, 0.95}
    },
    button = {
        disabledBG = {0.4, 0.4, 0.4, 0.7},
        disabledBorder = {0, 0, 0, 0, 1},
        disabledFG = {0, 0, 0, 0.7},
        hoveredBG = {1, 1, 1, 1},
        hoveredBorder = {0.5607, 0.5686, 0.5686, 1, 1},
        hoveredFG = {0, 0, 0, 1},
        normalBG = {0.9843, 0.9725, 0.9843, 1},
        normalBorder = {0.5607, 0.5686, 0.5686, 1, 1},
        normalFG = {0, 0, 0, 1},
        pressedBG = {0.4901, 0.3568, 0.7686, 1},
        pressedBorder = {0.4901, 0.3568, 0.7686, 1, 1},
        pressedFG = {1, 1, 1, 1}
    },
    buttonClose = {
        hoveredBG = {0.85, 0.25, 0.25, 1},
        normalBG = {1, 0.1, 0.2, 1},
        pressedBG = {0.6, 0.08, 0.14, 1}
    },
    buttonGreen = {
        hoveredBG = {0.7, 0.9, 0.7, 0.9},
        normalBG = {0.5, 0.8, 0.5, 0.8},
        pressedBG = {0.5, 0.9, 0.5, 0.9}
    },
    default = {},
    dropdown = {},
    field = {
        disabledBG = {0.5, 0.5, 0.5, 0.7},
        disabledBorder = {0, 0, 0, 0.7, 1},
        disabledFG = {0, 0, 0, 0.7, 0},
        focusedBG = {1, 1, 1, 0.9},
        focusedBorder = {0, 0, 0, 0.9, 1},
        focusedFG = {0, 0, 0, 0.9, 1},
        normalBG = {0.95, 0.95, 0.95, 0.9},
        normalBorder = {0.08, 0.08, 0.08, 0.6, 1},
        normalFG = {0, 0, 0, 0.8, 0}
    },
    group = {
        bg = {},
        border = {},
        radius = 0
    },
    icon = {
        color = {0, 0, 0, 1}
    },
    image = {
        color = {1, 1, 1, 1}
    },
    label = {
        color = {0, 0, 0, 1}
    },
    list = {
        dragLineColor = {0.2, 0.2, 0.2, 1.0}
    },
    listItem = {
        disabledBG = {0.4, 0.4, 0.4, 0.9},
        disabledBorder = {0, 0, 0, 0, 1},
        disabledFG = {0, 0, 0, 0.7},
        hoveredBG = {1, 1, 1, 1},
        hoveredBorder = {0.5607, 0.5686, 0.5686, 1, 1},
        hoveredFG = {0, 0, 0, 1},
        normalBG = {0.9843, 0.9725, 0.9843, 1},
        normalBorder = {0.5607, 0.5686, 0.5686, 1, 1},
        normalFG = {0, 0, 0, 1},
        pressedBG = {0.4901, 0.3568, 0.7686, 1},
        pressedBorder = {0.4901, 0.3568, 0.7686, 1, 1},
        pressedFG = {1, 1, 1, 1},
        radius = 0,
        selectedBG = {0.3215, 0.1843, 0.6627, 1},
        selectedBorder = {0.3215, 0.1843, 0.6627, 1, 1},
        selectedFG = {1, 1, 1, 1}
    },
    listItemGreen = {
        hoveredBG = {0.7, 0.9, 0.7, 0.9},
        normalBG = {0.5, 0.8, 0.5, 0.8},
        pressedBG = {0.1, 0.6, 0.1, 0.9},
        selectedBG = {0.2, 0.7, 0.2, 0.9}
    },
    listItemYellow = {
        hoveredBG = {0.9, 0.8, 0.4, 0.9},
        normalBG = {0.8, 0.7, 0.3, 0.8},
        pressedBG = {0.3, 0.2, 0, 0.9},
        selectedBG = {0.4, 0.3, 0.1, 0.9}
    },
    menuItem = {
        bg = {0.08, 0.08, 0.08, 0.8}
    },
    menuItemSubmenu = {
        bg = {0.08, 0.08, 0.08, 0.8}
    },
    panel = {
        bg = {1, 0.8509, 0.9647, 1},
        border = {1, 0.9254, 0.9843, 1},
        radius = 3
    },
    scrollbox = {},
    scrollhandle = {
        border = {},
        color = {},
        hoveredBorder = {0.6, 0.6, 0.6, 0.7, 1},
        hoveredColor = {0.6, 0.6, 0.6, 1},
        normalBorder = {0.5, 0.5, 0.5, 1, 1},
        normalColor = {0.5, 0.5, 0.5, 0.6},
        pressedBorder = {0.55, 0.55, 0.55, 0.7, 1},
        pressedColor = {0.55, 0.55, 0.55, 1},
        radius = 3,
        thickness = 6
    },
    scrollhandleX = {},
    scrollhandleY = {},
    spinner = {
        color = {0, 0, 0, 1}
    },
    titlebar = {
        border = {0.3607, 0.3647, 0.3647, 0},
        focusedBG = {0.3215, 0.1843, 0.6627, 1},
        focusedFG = {1, 1, 1, 1},
        radius = 0,
        unfocusedBG = {0.1882, 0.1137, 0.4274, 0.9},
        unfocusedFG = {1, 1, 1, 0.65}
    },
    topbar = {
        bg = {0.3215, 0.1843, 0.6627, 1},
        radius = 0
    },
    window = {
        bg = {1, 0.8509, 0.9647, 1},
        border = {1, 0.2313, 0.8274, 1}
    }
}