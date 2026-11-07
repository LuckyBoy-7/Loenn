local fonts = require("fonts")
local utils = require("utils")
local languageRegistry = require("language_registry")
local persistence = require("persistence")
local viewportHandler = require("viewport_handler")
local logging = require("logging")
local startupProgress = require("startup_progress")
local liquidFill = require("ui.widgets.liquid_fill")

local loadingScene = {}

loadingScene.name = "Loading"

function loadingScene:setText(text)
    self.text = tostring(text)
    self.alignment = "left"
    self.textScale = fonts.fontScale * 2
    self.textOffsetX = (fonts.font:getWidth(self.text .. "..") * self.textScale) / 2
    self.textOffsetY = self.quadSize / 2
end

-- Runs every time the loading scene is entered (opening a map goes through it
-- again), so the loading text always uses the configured font, not whatever
-- zoom based font the editor was using
function loadingScene:enter()
    local configs = require("configs")

    fonts.setUseHires(configs.font.useHiresPixelFont)
    self:setText(languageRegistry.getLanguage().scenes.loading.loading)
end

function loadingScene:loaded()
    self.spriteSheet = love.graphics.newImage("assets/loading-256.png")
    self.quadSize = 256
    self.quads = {}

    for y = 0, self.spriteSheet:getHeight() - self.quadSize, self.quadSize do
        for x = 0, self.spriteSheet:getWidth() - self.quadSize, self.quadSize do
            table.insert(self.quads, love.graphics.newQuad(x, y, self.quadSize, self.quadSize, self.spriteSheet:getDimensions()))
        end
    end

    -- The sheet starts with an empty frame and a partly rotated one, the last
    -- frame is the fully visible logo. The logo no longer animates, so just
    -- keep that last frame
    self.logoQuad = self.quads[#self.quads]

    -- Faded base logo the liquid is drawn on top of
    self.logoAlpha = 0.35

    -- The logo and the loading text sit slightly above the window center, which
    -- looks more balanced than centering the logo itself
    self.logoOffset = 26

    self.duration = 1
    self.currentTime = 0
end

function loadingScene:firstEnter()
    local tasks = require("utils.tasks")

    local sandboxUtils = require("utils.sandbox")
    local language = languageRegistry.getLanguage()

    local sceneHandler = require("scene_handler")
    local toolHandler = require("tools")
    local entities = require("entities")
    local triggers = require("triggers")
    local effects = require("effects")
    local libraries = require("libraries")
    local saveSanitizers = require("save_sanitizers")

    local atlases = require("atlases")

    local configs = require("configs")
    local defaultConfig = require("default_config")
    local mods = require("mods")

    local launchArguments = require("launch_arguments")

    local fileLocations = require("file_locations")
    local viewerState = require("loaded_state")

    local userInterfaceDevice = require("ui.ui_device")

    -- The configured font has to be applied before the loading text is
    -- measured. Automatic zoom switching only applies to map text, so the
    -- loading screen always uses the configured font
    fonts.setUseHires(configs.font.useHiresPixelFont)

    self:setText(language.scenes.loading.loading)

    startupProgress.reset()

    -- A broken shader must not break startup, the logo is drawn plain instead
    local created, liquidLogo = pcall(liquidFill.create, {baseAlpha = self.logoAlpha})

    self.liquidLogo = created and liquidLogo or nil

    if not created then
        logging.warning("[loading] Could not create the liquid fill shader: " .. tostring(liquidLogo))
    end

    -- Microbenchmark to estimate instructions per second
    sandboxUtils.calcIpsAndHookInterval()

    -- Load assets and entity, trigger, effect etc modules
    tasks.newTask(
        function()
            local timings = {}
            local phaseStart = love.timer.getTime()

            local function phaseDone(name)
                local now = love.timer.getTime()

                table.insert(timings, string.format("%s=%.0fms", name, (now - phaseStart) * 1000))

                if configs.debug.logStartupTiming then
                    logging.info(string.format("[startup] %s done at %.0fms (+%.0fms)",
                        name, now * 1000, (now - phaseStart) * 1000))
                end

                phaseStart = now
            end

            startupProgress.beginPhase("celesteAtlases", "Loading atlases")
            atlases.loadCelesteAtlases()
            startupProgress.finishPhase()
            phaseDone("celesteAtlases")

            startupProgress.beginPhase("mountMods", "Loading mods")

            mods.mountMods()

            startupProgress.finishPhase()
            phaseDone("mountMods")

            startupProgress.beginPhase("languages", "Loading languages")
            -- Internal scenes are already loaded, how else would we be here
            sceneHandler.loadExternalScenes()

            languageRegistry.loadExternalFiles()
            languageRegistry.setFallbackLanguage(defaultConfig.general.language)
            startupProgress.finishPhase()
            phaseDone("scenes+language")

            startupProgress.beginPhase("libraries", "Loading libraries")
            libraries.loadInternalLibraries()
            libraries.loadExternalLibraries()
            startupProgress.finishPhase()
            phaseDone("libraries")

            startupProgress.beginPhase("entities", "Loading entities")
            entities.loadInternalEntities()
            entities.loadExternalEntities()
            startupProgress.finishPhase()
            phaseDone("entities")

            startupProgress.beginPhase("triggers", "Loading triggers")
            triggers.loadInternalTriggers()
            triggers.loadExternalTriggers()
            startupProgress.finishPhase()
            phaseDone("triggers")

            startupProgress.beginPhase("effects", "Loading effects")
            effects.loadInternalEffects()
            effects.loadExternalEffects()
            startupProgress.finishPhase()
            phaseDone("effects")

            startupProgress.beginPhase("tools", "Loading tools")
            toolHandler.loadInternalTools()
            toolHandler.loadExternalTools()
            startupProgress.finishPhase()
            phaseDone("tools")

            startupProgress.beginPhase("saveSanitizers", "Loading save sanitizers")
            saveSanitizers.loadInternalSanitizers()
            saveSanitizers.loadExternalSanitizers()
            startupProgress.finishPhase()
            phaseDone("saveSanitizers")

            startupProgress.beginPhase("userInterface", "Building interface")
            if userInterfaceDevice.initializeDevice then
                userInterfaceDevice.initializeDevice()
            end
            startupProgress.finishPhase()
            phaseDone("userInterface")

            -- This can take a while depending on the amount of installed mods
            -- By default it is lazy loaded
            if not configs.editor.lazyLoadExternalAtlases then
                atlases.loadExternalAtlases()
                phaseDone("externalAtlases")
            end

            require("virtual_fs").report()
            logging.info("[compile_cache] " .. require("compile_cache").report())

            logging.info(string.format("[startup] boot=%.0fms progress=%.0f%% %s",
                love.timer.getTime() * 1000, startupProgress.get() * 100, table.concat(timings, " ")))
        end
    )

    local defaultMapFilename = utils.joinpath(fileLocations.getCelesteDir(), "Content", "Maps", "7-Summit.bin")
    local initialFilename = launchArguments.parsed.initialFilename
    local lastMapFilename = persistence.lastLoadedFilename
    local lastRoomName = persistence.lastSelectedRoomName
    local targetFilename = initialFilename or lastMapFilename or defaultMapFilename

    viewerState.loadFile(targetFilename, lastRoomName)
    viewportHandler.cameraFromPersistence()
    viewerState.initFromPersistence()
end

function loadingScene:draw()
    -- Scenes metatable will make this seem like a function, make sure its actually set
    if type(self.text) == "string" then
        local windowWidth, windowHeight = love.graphics.getWidth(), love.graphics.getHeight()

        local dots = string.rep(".", utils.mod1(math.floor(self.currentTime / self.duration * 4) + 1, 4))

        love.graphics.printf(self.text .. dots, windowWidth / 2 - self.textOffsetX, windowHeight / 2 + self.textOffsetY - self.logoOffset, windowWidth, self.alignment, 0, self.textScale)

        local x = (windowWidth - self.quadSize) / 2
        local y = (windowHeight - self.quadSize) / 2 - self.logoOffset

        self:drawLogo(x, y)
    end
end

-- The liquid masks the logo: the part below the surface is drawn at full
-- strength, the rest stays faded
function loadingScene:drawLogo(x, y)
    if not self.liquidLogo then
        love.graphics.setColor(1, 1, 1, self.logoAlpha)
        love.graphics.draw(self.spriteSheet, self.logoQuad, x, y)
        love.graphics.setColor(1, 1, 1, 1)

        return
    end

    liquidFill.drawLogo(self.liquidLogo, self.spriteSheet, self.logoQuad, x, y, self.quadSize, self.quadSize, startupProgress.get())
end

function loadingScene:update(dt)
    self.currentTime = self.currentTime + dt
    while self.currentTime >= self.duration do
        self.currentTime = self.currentTime - self.duration
    end

    if self.liquidLogo then
        liquidFill.update(self.liquidLogo, dt)
    end
end

return loadingScene