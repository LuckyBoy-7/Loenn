local ffi = require("ffi")

local ime = {}

local supportedPlatforms = {
    Windows = true,
    OSX = true,
    Linux = true
}

local isSupported = supportedPlatforms[ffi.os] == true
local sdl

if isSupported then
    pcall(ffi.cdef, [[
        typedef struct SDL_Rect {
            int x;
            int y;
            int w;
            int h;
        } SDL_Rect;

        int SDL_SetHint(const char *name, const char *value);
        void SDL_SetTextInputRect(const SDL_Rect *rect);
    ]])

    local libraryNames = {"SDL2"}

    if ffi.os == "Linux" then
        table.insert(libraryNames, "libSDL2-2.0.so.0")
        table.insert(libraryNames, "libSDL2-2.0.so")

    elseif ffi.os == "OSX" then
        table.insert(libraryNames, "SDL2.framework/SDL2")
    end

    for _, name in ipairs(libraryNames) do
        local success, library = pcall(ffi.load, name)

        if success then
            sdl = library

            break
        end
    end
end

-- Windows uses a UILess IME by default, which does not render the candidate window. This hint
-- has to be set before the first SDL_StartTextInput / IME initialization. macOS and Linux use
-- their native input methods, where SDL draws through the OS candidate window.
function ime.enableNativeCandidateWindow()
    if sdl then
        sdl.SDL_SetHint("SDL_IME_SHOW_UI", "1")
    end
end

-- Tells the IME where the text field is so the candidate window is positioned near it.
function ime.updateTextInputRect(element)
    if not isSupported or not element or not love.keyboard.setTextInput then
        return
    end

    local x, y = element.screenX, element.screenY

    if not x or not y then
        return
    end

    love.keyboard.setTextInput(true, x, y, element.width or 1, element.height or 1)
end

-- Moves an already active IME without restarting text input. Re-calling SDL_StartTextInput while
-- a composition is active can make the candidate window lag, which is why this uses
-- SDL_SetTextInputRect directly when the SDL library is available.
function ime.moveTextInputRect(element)
    if not isSupported or not element then
        return
    end

    local x, y = element.screenX, element.screenY

    if not x or not y then
        return
    end

    if ffi.os == "Windows" and sdl and sdl.SDL_SetTextInputRect then
        local rect = ffi.new("SDL_Rect", {
            x = math.floor(x),
            y = math.floor(y),
            w = math.max(1, math.floor(element.width or 1)),
            h = math.max(1, math.floor(element.height or 1))
        })

        sdl.SDL_SetTextInputRect(rect)

    elseif love.keyboard.setTextInput then
        love.keyboard.setTextInput(true, x, y, element.width or 1, element.height or 1)
    end
end

function ime.disableTextInput()
    if isSupported and love.keyboard.setTextInput then
        love.keyboard.setTextInput(false)
    end
end

return ime
