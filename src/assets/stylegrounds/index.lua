-- Styleground preview index
-- =============================================================================
-- Keys are the effect's registered `name`, exactly as written in its handler (handlers without
-- a name field are registered under their file name). Every field is optional: an effect
-- without an entry still gets the placeholder preview.
--
-- This file covers both the official effects from src/effects (listed first) and every effect
-- found in Mods/*/Loenn/effects.
--
-- preview
-- -------
-- String shorthand:
--     preview = "assets/stylegrounds/my_effect.png",
--
-- Table form:
--     preview = {
--         type = "image",                  -- "image" (default) or "attribute"
--         image = "assets/stylegrounds/my_effect.png",
--     },
--     preview = {
--         type = "attribute",              -- resolve the preview from an effect attribute
--         attribute = "texture",
--         basePath = "Graphics/Atlases/Gameplay",
--     },
--
-- hoverPreview
-- ------------
-- Optional image used by the hover preview on list entries instead of `preview`. Accepts the same
-- string/table forms as `preview`; when omitted, the hover preview follows `preview`.
--
--     hoverPreview = "assets/stylegrounds/my_effect_hover.png",
--
-- otherTextures
-- -------------
-- Extra textures drawn as cells to the right of the preview box. Each entry:
--
--     {attribute = "texture", type = "texture", basePath = "Graphics/Atlases/Gameplay"}
--
-- (`type` may also be written as `enum`.) Up to 36 cells are shown per effect.
--
-- The four supported types:
--     "texture"     one texture; basePath .. "/" .. value
--     "textureList" a separated list of textures (separator defaults to ",")
--     "animation"   one animation frame; the trailing number is trimmed and every sibling
--                   with the same stem is collected (bg0 -> bg0, bg1, bg2, ...)
--     "folder"      the value is a folder; every image inside it is collected
--
-- A complete example:
--
--     ["MyMod/MyEffect"] = {
--         preview = {type = "attribute", attribute = "texture", basePath = "Graphics/Atlases/Gameplay"},
--         otherTextures = {
--             {attribute = "texture", type = "texture", basePath = "Graphics/Atlases/Gameplay"},
--             {attribute = "textures", type = "textureList", basePath = "Graphics/Atlases/Gameplay", separator = ","},
--             {attribute = "texture", type = "animation", basePath = "Graphics/Atlases/Gameplay"},
--             {attribute = "folder", type = "folder", basePath = "Graphics/Atlases/Gameplay"},
--         },
--     },
--
-- Replace the placeholder paths below with real images under assets/stylegrounds/ when you have
-- them; entries left pointing at the placeholder keep showing it.
-- The bundled images live in assets/stylegrounds/preview/.
--
-- Animated previews: `preview` may point at a .gif file (e.g. "assets/stylegrounds/foo.gif").
-- The editor decodes it and plays every frame in the big preview box and in the hover preview.
-- GIFs referenced by otherTextures are shown as their first frame.
-- =============================================================================

local PLACEHOLDER = "assets/stylegrounds/placeholder.png"

return {
    -- Official effects (src/effects)
    ["blackhole"] = { preview = "assets/stylegrounds/preview/Black Hole.png" },
    ["bossStarField"] = { preview = "assets/stylegrounds/preview/Boss Star field.png" },
    ["corestarsfg"] = { preview = "assets/stylegrounds/preview/Core Stars.png" },
    ["dreamstars"] = { preview = "assets/stylegrounds/preview/Dream Stars.png" },
    ["godrays"] = { preview = "assets/stylegrounds/preview/God Rays.png" },
    ["heatwave"] = { preview = "assets/stylegrounds/preview/Heat Wave.png" },
    ["mirrorfg"] = { preview = "assets/stylegrounds/preview/Mirror Foreground.png" },
    ["northernlights"] = { preview = "assets/stylegrounds/preview/Northern Lights.png" },
    ["petals"] = { preview = "assets/stylegrounds/preview/Petals.png" },
    ["planets"] = { preview = "assets/stylegrounds/preview/Planets.png" },
    ["rain"] = { preview = "assets/stylegrounds/preview/Rain.png" },
    ["reflectionfg"] = { preview = "assets/stylegrounds/preview/Reflection Foreground.png" },
    ["snowBg"] = { preview = "assets/stylegrounds/preview/Snow Bg.png" },
    ["snowFg"] = { preview = "assets/stylegrounds/preview/Snow Fg.png" },
    ["stardust"] = { preview = "assets/stylegrounds/preview/Star Dust.png" },
    ["starfield"] = { preview = "assets/stylegrounds/preview/Starfield.png" },
    ["stars"] = { preview = "assets/stylegrounds/preview/Stars.png" },
    ["tentacles"] = { preview = "assets/stylegrounds/preview/Tentacles.png" },
    ["windSnow"] = { preview = "assets/stylegrounds/preview/Wind Snow.png" },

    -- Mod effects (Mods/*/Loenn/effects)
    ["AdamsAddons/RhombusGodrays"] = { preview = "assets/stylegrounds/preview/Rhombus Godrays [Adam's Add-ons].png" },
    ["AidenHelper/MeteorShower"] = { preview = "assets/stylegrounds/preview/Meteor Shower [AidenHelper].png" },
    ["Aqua/Andromeda Field"] = { preview = PLACEHOLDER },

    ["Aqua/Gravity Control Parallax"] = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        }
    },
    ["Aqua/Self Reconfiguration Circuit"] = { preview = PLACEHOLDER },
    ["Aqua/Vortex"] = { preview = PLACEHOLDER },
    ["ArphimigonHelper/BubbleEffect"] = { preview = "assets/stylegrounds/preview/Arphimigon Helper Bubble Effect [ArphimigonsToyBox].png" },
    ["ArphimigonHelper/RippleEffect"] = { preview = "assets/stylegrounds/preview/Arphimigon Helper Ripple Effect [ArphimigonsToyBox].png" },
    ["auspicioushelper/MaterialEffect"] = { preview = PLACEHOLDER },
    ["CaeruleaHelper/CustomAscendingStars"] = {
        preview = "assets/stylegrounds/preview/Custom Ascending Stars [CaeruleaHelper].png",
        otherTextures = {
            { attribute = "path", type = "folder", basePath = "Graphics/Atlases/Gameplay" },
        }
    },
    ["CaeruleaHelper/NoiseCircleArea"] = { preview = PLACEHOLDER },
    ["CaeruleaHelper/PureColor"] = { preview = "assets/stylegrounds/preview/Pure Color [CaeruleaHelper].png" },
    ["ChroniaHelper/CustomRain"] = { preview = "assets/stylegrounds/preview/Custom Rain [ChroniaHelper].png" },
    ["ChroniaHelper/WaterSurface"] = { preview = "assets/stylegrounds/preview/Water Surface [ChroniaHelper].png" },
    ["ChroniaHelper/WindRainFG"] = { preview = PLACEHOLDER },
    ["CNY2024Helper/TwirlBackdrop"] = { preview = "assets/stylegrounds/preview/CNY2024Helper Twirl Backdrop [CNY2O24Helper].png" },
    ["CommunalHelper/BetaCube"] = {
        preview = "assets/stylegrounds/preview/Beta Cube [Communal Helper].png",
        otherTextures = {
            { attribute = "texture", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },
    ["CommunalHelper/Cloudscape"] = { preview = "assets/stylegrounds/preview/Cloudscape [Communal Helper].png" },
    ["ContortHelper/HighResolutionParticleBackdrop"] = {
        preview = "assets/stylegrounds/preview/Contort Helper High Resolution Particle Backdrop [ContortHelper].png",
        otherTextures = {
            { attribute = "overlay",  type = "texture", basePath = "Graphics/Atlases/Overworld" },
            { attribute = "particle", type = "texture", basePath = "Graphics/Atlases/Overworld" },
        }
    },

    ["corkr900Graphics/VelocityTrail"] = { preview = "assets/stylegrounds/preview/Velocity Trail [corkr9o0 Graphics].png" },
    ["CrystallineHelper/CustomWindSnow"] = { preview = "assets/stylegrounds/preview/Custom Wind Snow [Crystalline].png" },
    ["DBBHelper/CartonCloud"] = {
        preview = "assets/stylegrounds/preview/Carton Cloud [DBBHelper].png",
        otherTextures = {
            { attribute = "Texture", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["DBBHelper/PhysicalParticle"] = {
        preview = "assets/stylegrounds/preview/Physical Particle [DBBHelper].png",
        otherTextures = {
            { attribute = "ParticleTexture", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["DBBHelper/ProgramSky"] = { preview = "assets/stylegrounds/preview/Program Sky [DBBHelper].png" },
    ["EeveeHelper/SeededStarfield"] = {
        preview = "assets/stylegrounds/preview/Seeded Starfield [Eevee Helper].png",
        otherTextures = {
            { attribute = "textureDir", type = "folder", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["ExCameraDynamics/ZoomParallax"] = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        }
    },
    ["ExCameraDynamics/ZoomParallaxDepth"] = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        }
    },
    ["ExCameraDynamics/ZoomParticleDepth"] = {
        preview = PLACEHOLDER,
        otherTextures = {
            { attribute = "textures", type = "animation", basePath = "Graphics/Atlases/Gameplay" },
        }
    },
    ["ExCameraDynamics/ZoomParticleParallax"] = {
        preview = {
            type = "attribute",
            attribute = "textures",
            basePath = "Graphics/Atlases/Gameplay",
        }
    },

    ["FemtoHelper/DigitalCascade"] = {
        preview = "assets/stylegrounds/preview/Digital Cascade [FemtoHelper].png",
        otherTextures = {
            { attribute = "spritePath", type = "animation", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    -- ["FemtoHelper/DistortedParallax"] = { preview = PLACEHOLDER },
    ["FemtoHelper/FemtoStars"] = {
        preview = "assets/stylegrounds/preview/Femto Stars [FemtoHelper].png",
        otherTextures = {
            { attribute = "sprite", type = "folder", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["FemtoHelper/NewDistortedParallax"] = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        }
    },
    ["FemtoHelper/PolygonStars"] = { preview = "assets/stylegrounds/preview/Polygon Stars [FemtoHelper].png" },
    ["FemtoHelper/VectorSpace"] = { preview = "assets/stylegrounds/preview/Vector Space [FemtoHelper].png" },
    ["FemtoHelper/WindPetals"] = {
        preview = "assets/stylegrounds/preview/Wind Petals [FemtoHelper].png",
        otherTextures = {
            { attribute = "texture", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["FlaglinesAndSuch/customBossField"] = { preview = "assets/stylegrounds/preview/Boss starfield (Custom) [Flaglines And Such].png" },
    ["FlaglinesAndSuch/customDreamStars"] = { preview = "assets/stylegrounds/preview/Dreamstars (custom) [Flaglines And Such].png" },
    ["FlaglinesAndSuch/customGodrays"] = { preview = "assets/stylegrounds/preview/Godrays (custom) [Flaglines And Such].png" },
    ["FlaglinesAndSuch/GeometricBlackhole"] = {
        preview = "assets/stylegrounds/preview/Geometric Blackhole [Flaglines And Such].png",
        otherTextures = {
            { attribute = "Texture", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["FlaglinesAndSuch/PolygonEffect"] = { preview = PLACEHOLDER },
    ["FlaglinesAndSuch/PolygonEffectCube"] = { preview = "assets/stylegrounds/preview/3D Polygon (cube) [Flaglines And Such].png" },
    ["FlaglinesAndSuch/RotParralaxTwo"] = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        },
        hoverPreview = "assets/stylegrounds/preview/Rotating Parallax+ [Flaglines And Such].png",
    },
    ["FlaglinesAndSuch/SineParallaxStyleground"] = {
        preview = {
            type = "attribute",
            attribute = "Texture",
            basePath = "Graphics/Atlases/Gameplay",
        }
    },

    ["FlaglinesAndSuch/SummitBoostBackground"] = { preview = "assets/stylegrounds/preview/Summit Boost BG [Flaglines And Such].png" },
    ["FlaglinesAndSuch/VaporwaveGrid"] = { preview = "assets/stylegrounds/preview/Vaporwave Grid [Flaglines And Such].png" },
    ["FrostHelper/Gradient"] = { preview = "assets/stylegrounds/preview/Gradient [Frost Helper]、.png" },
    ["LunaticHelper/CustomDust"] = { preview = "assets/stylegrounds/preview/Custom Dust [LunaticHelper].png" },
    ["LunaticHelper/CustomField"] = { preview = "assets/stylegrounds/preview/Custom Field [LunaticHelper].png" },
    ["LylyraHelper/HexagonalGodray"] = { preview = "assets/stylegrounds/preview/Lylyra Helper Hexagonal Godray [LylyraHelper].png" },
    ["LylyraHelper/SS2024/AtmosphericWind"] = { preview = "assets/stylegrounds/preview/Lylyra Helper SS2024 Atmospheric Wind [LylyraHelper].png" },
    ["LylyraHelper/SS2024/ShockwaveRenderer"] = { preview = PLACEHOLDER },
    ["LylyraHelper/StarGodray"] = { preview = "assets/stylegrounds/preview/Lylyra Helper Star Godray [LylyraHelper].png" },
    ["MaxHelpingHand/AllSideTentacles"] = { preview = "assets/stylegrounds/preview/Tentacles (All Sides) [Maddie's Helping Hand].png" },
    ["MaxHelpingHand/BlackholeCustomColors"] = {
        preview = "assets/stylegrounds/preview/Black Hole (Custom) [Maddie's Helping Hand].png",
        otherTextures = {
            { attribute = "particleTexture", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
            { attribute = "texture",         type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["MaxHelpingHand/CustomPlanets"] = {
        preview = "assets/stylegrounds/preview/Planets (Custom) [Maddie's Helping Hand].png",
        otherTextures = {
            { attribute = "directory", type = "folder", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["MaxHelpingHand/CustomStarfield"] = {
        preview = "assets/stylegrounds/preview/Starfield (Custom) [Maddie's Helping Hand].png",
        otherTextures = {
            { attribute = "paths", type = "folder", basePath = "Graphics/Atlases/Gameplay/particles" },
        }
    },

    ["MaxHelpingHand/CustomStars"] = {
        preview = "assets/stylegrounds/preview/Stars (Custom) [Maddie's Helping Hand].png",
        otherTextures = {
            { attribute = "spriteDirectory", type = "folder", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["MaxHelpingHand/HeatWaveNoColorGrade"] = { preview = "assets/stylegrounds/preview/Heatwave (not affecting Color Grade) [Maddie's Helping Hand].png" },
    ["MaxHelpingHand/NorthernLightsCustomColors"] = { preview = "assets/stylegrounds/preview/Northern Lights (Custom) [Maddie's Helping Hand].png" },
    ["MaxHelpingHand/SnowCustomColors"] = {
        preview = "assets/stylegrounds/preview/Snow (Custom) [Maddie's Helping Hand].png",
        otherTextures = {
            { attribute = "texturePath", type = "texture", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["MoladanHelper/CubeGenerator"] = { preview = "assets/stylegrounds/preview/3D Cube Background [MoladanHelper].png" },
    ["PersistenceHelper/GlamNetuneWave"] = { preview = PLACEHOLDER },
    ["PrismaticHelper/Flyaway"] = {
        preview = "assets/stylegrounds/preview/Flyaway [PrismaticHelper].png",
        otherTextures = {
            { attribute = "textures", type = "animation", basePath = "Graphics/Atlases/Gameplay" },
        }
    },

    ["PrismaticHelper/RotatingParallax"] = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        },
        hoverPreview = "assets/stylegrounds/preview/Rotating Parallax [PrismaticHelper].png",
    },

    ["ReverseHelper/ThetaAndParalldoxsOnWorldlines/Sea"] = { preview = "assets/stylegrounds/preview/Sea of Worldlines [Reverse Helper].png" },
    ["ReverseHelper/YetAnotherHiresBackgroundParallax"]  = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        },
    },
    
    ["rushHelper/cloudSea"] = { preview = PLACEHOLDER },
    ["rushHelper/waterPlane"]  = {
        preview = {
            type = "attribute",
            attribute = "texture",
            basePath = "Graphics/Atlases/Gameplay",
        },
    },
    ["ScugHelper/Balatro"] = { preview = PLACEHOLDER },
    ["ScugHelper/HallOfMirrors"] = { preview = PLACEHOLDER },
    ["shaderWrapper"] = { preview = PLACEHOLDER },
    ["ShroomHelper/ShroomPetals"] = { preview = "assets/stylegrounds/preview/Petals (Custom) [Shroom Helper].png" },
    ["SorbetHelper/EntityStylegroundRenderer"] = { preview = PLACEHOLDER },
    ["SorbetHelper/HiResGodrays"]= {
        preview = "assets/stylegrounds/preview/Godrays (Hi-Res) [Sorbet Helper].png",
        otherTextures = {
            { attribute = "texturePath", type = "texture", basePath = "Graphics/Atlases/Overworld" },
        }
    },
    
    ["SorbetHelper/ParallaxHiResSnow"] = { preview = "assets/stylegrounds/preview/Parallax Hi-Res Snow [Sorbet Helper].png" },
    ["SorbetHelper/SpiralStars"]  = {
        preview = "assets/stylegrounds/preview/Spiral Stars [Sorbet Helper].png",
        otherTextures = {
            { attribute = "spritePath", type = "folder", basePath = "Graphics/Atlases/Gameplay" },
        }
    },
    
    ["StyleMaskHelper/HeatWaveOneMode"] = { preview = "assets/stylegrounds/preview/Heatwave (One Mode) [Style Mask Helper].png" },
    ["VidPlayer/VidPlayerParallax"] = { preview = PLACEHOLDER },
    ["VidPlayer/VidPlayerStyleground"] = { preview = PLACEHOLDER },
    ["VivHelper/CustomRain"] = { preview = PLACEHOLDER },
    ["VivHelper/WindRainFG"] = { preview = PLACEHOLDER },
    ["WindHelper/DiagonalStardustFG"] = { preview = "assets/stylegrounds/preview/Star Dust (Diagonal) [WindHelper].png" },
    ["WindHelper/DiagonalWindSnowFG"] = { preview = "assets/stylegrounds/preview/Wind Snow (Diagonal) [WindHelper].png" },
    ["XaphanHelper/Glow"] = { preview = PLACEHOLDER },
    ["XaphanHelper/HeatParticles"] = { preview = "assets/stylegrounds/preview/Heat Particles [Xaphan Helper].png" },
}
