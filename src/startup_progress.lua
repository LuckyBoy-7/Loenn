-- Tracks how far the startup loading task has progressed, so the loading screen
-- can show a determinate bar instead of a blind spinner.
--
-- Phases are reported by the code doing the work (mods, plugin loader, ...),
-- the weights below are the rough share of the total startup time they take.

local startupProgress = {}

local order = {
    "celesteAtlases",
    "mountMods",
    "languages",
    "libraries",
    "entities",
    "triggers",
    "effects",
    "tools",
    "saveSanitizers",
    "userInterface"
}

local weights = {
    celesteAtlases = 0.06,
    mountMods = 0.40,
    languages = 0.08,
    libraries = 0.05,
    entities = 0.25,
    triggers = 0.07,
    effects = 0.02,
    tools = 0.02,
    saveSanitizers = 0.01,
    userInterface = 0.04
}

local state = {}

function startupProgress.reset()
    state.phase = nil
    state.fraction = 0
    state.label = ""
    state.finished = {}
end

startupProgress.reset()

function startupProgress.beginPhase(name, label)
    state.phase = name
    state.fraction = 0
    state.label = label or ""
end

function startupProgress.setLabel(label)
    state.label = label or ""
end

-- Fractions only ever move forward: a phase that discovers more work while it
-- runs must not make the bar jump backwards
function startupProgress.report(fraction, label)
    if not state.phase then
        return
    end

    fraction = math.max(0, math.min(1, fraction or 0))
    state.fraction = math.max(state.fraction, fraction)

    if label then
        state.label = label
    end
end

function startupProgress.reportFiles(total, index, label)
    if not state.phase or not total or total <= 0 then
        return
    end

    startupProgress.report(index / total, label)
end

function startupProgress.finishPhase(name)
    if not state.phase then
        return
    end

    if name and name ~= state.phase then
        return
    end

    state.finished[state.phase] = true
    state.phase = nil
    state.fraction = 0
end

function startupProgress.get()
    local progress = 0

    for _, name in ipairs(order) do
        local weight = weights[name] or 0

        if state.finished[name] then
            progress = progress + weight

        elseif name == state.phase then
            progress = progress + weight * state.fraction
        end
    end

    return math.max(0, math.min(1, progress))
end

function startupProgress.getLabel()
    return state.label
end

return startupProgress
