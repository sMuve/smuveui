local _, S = ...
local M = S:NewModule("BarTextures")

-- One global statusbar texture for every health and primary resource bar: player, target, party,
-- raid, nameplates, and the personal resource display. Deliberately excludes secondary/alternate
-- class-resource bars (e.g. a Paladin's Holy Power bar via PersonalResourceDisplayFrame's own
-- AlternatePowerBar) - confirmed via BetterBlizzFrames' source (same client) as a genuinely
-- separate widget, not just a conceptual distinction.

-- Four small, original textures bundled under Media\Statusbars - procedurally generated shapes
-- (flat/gradient/sheen/ribbed), not copied artwork, so bundling them raises no licensing concern,
-- same spirit as Fonts.lua's OFL-licensed Rajdhani.
local BUILTIN_TEXTURES = {
    { name = "Flat", path = "Interface\\AddOns\\SmuveUI\\Media\\Statusbars\\SmuveFlat.tga", shared = true },
    { name = "Smooth", path = "Interface\\AddOns\\SmuveUI\\Media\\Statusbars\\SmuveSmooth.tga", shared = true },
    { name = "Satin", path = "Interface\\AddOns\\SmuveUI\\Media\\Statusbars\\SmuveSatin.tga", shared = true },
    { name = "Ribbed", path = "Interface\\AddOns\\SmuveUI\\Media\\Statusbars\\SmuveRibbed.tga", shared = true },
}

-- Share the bundled textures with every other addon via LibSharedMedia, same soft dependency as
-- Fonts.lua: skipped entirely if no other addon has LSM loaded.
local function RegisterSharedTextures()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return
    end
    for _, texture in ipairs(BUILTIN_TEXTURES) do
        if texture.shared then
            LSM:Register(LSM.MediaType.STATUSBAR, texture.name, texture.path)
        end
    end
end

-- The textures offered in the options: SmuveUI's own plus anything registered with LibSharedMedia.
function M:GetTextureList()
    local list, seen = {}, {}
    for _, texture in ipairs(BUILTIN_TEXTURES) do
        table.insert(list, texture)
        seen[texture.path:lower()] = true
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local extra = {}
        for name, texturePath in pairs(LSM:HashTable("statusbar")) do
            local key = type(texturePath) == "string" and texturePath:lower() or tostring(texturePath)
            if not seen[key] then
                seen[key] = true
                table.insert(extra, { name = name, path = texturePath })
            end
        end
        table.sort(extra, function(a, b) return a.name < b.name end)
        for _, texture in ipairs(extra) do
            table.insert(list, texture)
        end
    end
    return list
end

-- Resolves a stored texture name to a path. Returns nil for "DEFAULT" or anything that can't be
-- found (an addon that registered it got disabled) - ApplyTexture() below then falls back to
-- that specific bar's own remembered original texture, never erroring (spec FR-005).
local function ResolveTexture(name)
    if not name or name == "DEFAULT" then
        return nil
    end
    for _, texture in ipairs(BUILTIN_TEXTURES) do
        if texture.name == name then
            return texture.path
        end
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        return LSM:Fetch(LSM.MediaType.STATUSBAR, name, true)
    end
    return nil
end

-- Bars and frames can be forbidden/protected on this client; never touch one that is (mirrors
-- Modules\Nameplates.lua's own Accessible() check, duplicated locally rather than shared).
local function Accessible(region)
    if not region then
        return false
    end
    local forbidden = region.IsForbidden and region:IsForbidden()
    return not (S.IsSecret(forbidden) or forbidden)
end

-- Each bar's own original texture, captured the first time this module ever touches it - so
-- picking "DEFAULT" restores exactly what that specific bar started with, instead of guessing a
-- single hardcoded "default" path that might be wrong for some frame type (mirrors Fonts.lua's
-- originalFonts table for the same reason).
local originals = {}

local function ApplyTexture(bar)
    if not bar or not bar.SetStatusBarTexture or not Accessible(bar) then
        return
    end
    if originals[bar] == nil then
        local current = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        originals[bar] = (current and current.GetTextureFileID and current:GetTextureFileID())
            or (current and current.GetTexture and current:GetTexture())
            or false
    end
    local path = ResolveTexture(S.db.appearance.barTexture)
    bar:SetStatusBarTexture(path or originals[bar] or nil)
end

-- User Story 1: player and target frames -----------------------------------------------------------
-- Both follow the same "<Name>Content.<Name>ContentMain" nesting for the health bar (confirmed via
-- Modules\UnitFrames.lua's FindBar and AlignManaText, which already resolve this same path). The
-- mana bar does NOT follow the same shape on both: target's is a direct ".ManaBar" child (per
-- AlignManaText), but player's sits one level deeper under ".ManaBarArea.ManaBar" - confirmed via
-- BetterBlizzFrames' source, which touches both paths explicitly as two different shapes.

local function ApplyUnitFrame(frameName)
    local main = S.Resolve(frameName .. "." .. frameName .. "Content." .. frameName .. "ContentMain")
    if not main then
        return
    end
    local healthContainer = main.HealthBarsContainer
    ApplyTexture(healthContainer and healthContainer.HealthBar)
    local manaArea = main.ManaBarArea
    ApplyTexture((manaArea and manaArea.ManaBar) or main.ManaBar)
end

local function ApplyToUnitFrames()
    ApplyUnitFrame("PlayerFrame")
    ApplyUnitFrame("TargetFrame")
end

-- User Story 2: party and raid frames ---------------------------------------------------------------
-- CompactPartyFrameMember1-5 are static; CompactRaidFrame1-40 are created/destroyed as the raid's
-- size changes, so CompactUnitFrame_SetUnit (hooked in Init) is both the discovery mechanism and
-- the per-frame refresh - same hook point Modules\RaidFrames.lua already uses for its own styling.

local trackedCompactFrames = {}

local function ApplyCompactFrame(frame)
    if not frame or not Accessible(frame) then
        return
    end
    trackedCompactFrames[frame] = true
    ApplyTexture(frame.healthBar)
    ApplyTexture(frame.powerBar)
end

local function ApplyToCompactFrames()
    for frame in pairs(trackedCompactFrames) do
        pcall(ApplyCompactFrame, frame)
    end
end

-- User Story 3: nameplates and the personal resource display ----------------------------------------
-- Regular nameplates carry no resource bar at all - only health. The personal resource display is
-- its own named global frame (not part of C_NamePlate's enumeration) with a genuinely separate
-- PowerBar vs. AlternatePowerBar (the latter intentionally never touched - FR-009).

local function NamePlateHealthBar(plate)
    local frame = plate and plate.UnitFrame
    local container = frame and frame.HealthBarsContainer
    return container and container.healthBar
end

local function ApplyToNamePlateUnit(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    ApplyTexture(NamePlateHealthBar(plate))
end

local function ApplyToAllNamePlates()
    for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
        pcall(ApplyTexture, NamePlateHealthBar(plate))
    end
end

local function ApplyToPersonalResourceDisplay()
    local frame = PersonalResourceDisplayFrame
    if not frame or not Accessible(frame) then
        return
    end
    local container = frame.HealthBarsContainer
    ApplyTexture(container and container.healthBar)
    ApplyTexture(frame.PowerBar)
end

-- Lifecycle ------------------------------------------------------------------------------------------

function M:Apply()
    ApplyToUnitFrames()
    ApplyToCompactFrames()
    ApplyToAllNamePlates()
    ApplyToPersonalResourceDisplay()
end

function M:Refresh()
    self:Apply()
end

function M:Init()
    RegisterSharedTextures()
    hooksecurefunc("CompactUnitFrame_SetUnit", function(frame) ApplyCompactFrame(frame) end)
    S:On("NAME_PLATE_UNIT_ADDED", function(_, unit) ApplyToNamePlateUnit(unit) end)
    S:On("PLAYER_ENTERING_WORLD", function() M:Apply() end)
end
