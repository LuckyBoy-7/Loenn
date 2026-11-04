-- Liquid mask for the loading screen.
--
-- The liquid is a mask over the logo, not an overlay: the logo is drawn faded
-- and the part below the moving surface is drawn at full strength (and a bit
-- brighter), as if the liquid was revealing it. The sprite alpha is the mask, so
-- no stencil or canvas is needed (the loading scene is already drawn inside the
-- scene wipe stencil).
--
--   local fill = liquidFill.create({baseAlpha = 0.35})
--   liquidFill.update(fill, dt)
--   liquidFill.drawLogo(fill, image, quad, x, y, size, size, progress)

local liquidFill = {}

local shaderCode = [[
extern number progress;
extern number time;
extern number waveCount;
extern number waveHeight;
extern number baseAlpha;
extern number brightness;
extern vec4 logoRect;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec4 texColor = Texel(tex, tc);

    if (texColor.a <= 0.0) {
        return vec4(0.0);
    }

    // Position inside the logo in screen space, so the surface stays level
    float level = (sc.y - logoRect.y) / logoRect.w;
    float xpos = (sc.x - logoRect.x) / logoRect.z;

    float wave = sin(xpos * waveCount * 6.28318 + time * 2.0) * waveHeight
               + sin(xpos * waveCount * 12.56637 - time * 1.3) * waveHeight * 0.35;

    // Clamped so the wave cannot overshoot the logo at 0% and 100%
    float surface = clamp(1.0 - progress + wave, 0.0, 1.0);
    float water = smoothstep(surface - 0.005, surface + 0.005, level);

    // Faded logo, fully lit inside the liquid
    float alpha = mix(baseAlpha, 1.0, water);
    vec3 rgb = texColor.rgb * mix(1.0, brightness, water);

    return vec4(rgb, texColor.a * alpha * color.a);
}
]]

liquidFill.shaderCode = shaderCode

function liquidFill.create(options)
    options = options or {}

    local fill = {
        time = 0,
        baseAlpha = options.baseAlpha or 0.35,
        brightness = options.brightness or 1.15,
        waveCount = options.waveCount or 3.0,
        waveHeight = options.waveHeight or 0.02
    }

    fill.shader = love.graphics.newShader(shaderCode)
    fill.shader:send("waveCount", fill.waveCount)
    fill.shader:send("waveHeight", fill.waveHeight)
    fill.shader:send("baseAlpha", fill.baseAlpha)
    fill.shader:send("brightness", fill.brightness)
    fill.shader:send("time", 0.0)
    fill.shader:send("progress", 0.0)
    fill.shader:send("logoRect", {0, 0, 256, 256})

    return fill
end

function liquidFill.update(fill, dt)
    fill.time = fill.time + (dt or 0)

    fill.shader:send("time", fill.time)
end

function liquidFill.drawLogo(fill, image, quad, x, y, width, height, progress)
    progress = math.max(0, math.min(1, progress or 0))

    fill.shader:send("progress", progress)
    fill.shader:send("logoRect", {x, y, width, height})

    love.graphics.setShader(fill.shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, quad, x, y)
    love.graphics.setShader()
end

return liquidFill
