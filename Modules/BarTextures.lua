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
--
-- Falls back to this known-good path (confirmed via BetterBlizzFrames' source as this client's
-- own default bar fill) only if a bar's original truly can't be captured - never passes 0/nil to
-- SetStatusBarTexture. GetTextureFileID() returning 0 ("no texture set yet") is a real case, not
-- hypothetical: it's truthy in Lua, so an earlier version of this code accepted 0 as a captured
-- "original" and rendered the personal resource display's health bar solid black.
local FALLBACK_TEXTURE = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill"
local originals = {}

-- PlayerFrame/TargetFrame's classic ManaBar -> the unit it belongs to, filled by ApplyUnitFrame()
-- below. Lets the UnitFrameManaBar_UpdateType hook (see Init) know which unit's power type to
-- read without having to re-walk the frame hierarchy on every call. Weak-keyed since these are
-- the client's own frames, never meant to pin them alive.
local manaBarUnit = setmetatable({}, { __mode = "k" })

-- Several of this client's own default bars (confirmed live: the personal resource display's
-- health and power bars) are set via SetAtlas, not SetTexture/SetStatusBarTexture - the
-- underlying Texture object's GetTextureFileID()/GetTexture() both still return the atlas's
-- shared SHEET file, not the specific cropped region, so capturing only the raw file and later
-- replaying it via SetStatusBarTexture stretches the whole uncropped sheet across the bar
-- instead of the intended sub-region - confirmed live via /smuve dump as the actual cause of a
-- bar rendering solid black, not the earlier (also real, but not the whole story) 0-fileID case.
local function CaptureOriginal(bar)
    local current = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    if not current then
        return nil -- not textured yet; try again on the next apply
    end
    local atlas = current.GetAtlas and current:GetAtlas()
    if atlas and atlas ~= "" then
        return { atlas = atlas }
    end
    local fileID = current.GetTextureFileID and current:GetTextureFileID()
    if fileID and fileID ~= 0 then
        return { texture = fileID }
    end
    local filePath = current.GetTexture and current:GetTexture()
    if filePath and filePath ~= "" then
        return { texture = filePath }
    end
    return false -- genuinely nothing to capture; use FALLBACK_TEXTURE instead
end

-- Confirmed live via /smuve dump: this client's StatusBar widgets have no SetStatusBarAtlas
-- convenience method at all (bar.SetStatusBarAtlas was nil on every single bar dumped) - the
-- previous version of this function called it anyway, which silently did nothing and fell through
-- to FALLBACK_TEXTURE for every atlas-based bar. The atlas has to be set on the StatusBar's own
-- inner fill texture object instead (the same object GetStatusBarTexture() returns, and the same
-- one CaptureOriginal() above reads GetAtlas() from) - SetAtlas is a standard Texture method that
-- does exist here.
local function RestoreOriginal(bar, original)
    if type(original) ~= "table" then
        return false
    end
    if original.atlas then
        local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
        if tex and tex.SetAtlas then
            tex:SetAtlas(original.atlas, false)
            return true
        end
    end
    if original.texture then
        bar:SetStatusBarTexture(original.texture)
        return true
    end
    return false
end

-- A custom texture has no built-in inset the way the client's own atlas art does (confirmed this
-- session: the client's edge mask stays attached to a custom texture too, so the "looks bigger"
-- report is a pure shading/contrast illusion, not a lost crop). Tried and abandoned: an edge bevel
-- baked into the texture's own pixels, a proportional version of the same, and SetScale(0.95) on
-- the bar frame - each either did nothing or visibly broke some other bar type. Not pursuing this
-- further; Default and a custom texture simply look slightly different in size, left as-is.
local function ApplyTexture(bar)
    if not bar or not bar.SetStatusBarTexture or not Accessible(bar) then
        return
    end
    if originals[bar] == nil then
        originals[bar] = CaptureOriginal(bar)
    end
    local path = ResolveTexture(S.db.appearance.barTexture)
    if path then
        bar:SetStatusBarTexture(path)
    elseif not RestoreOriginal(bar, originals[bar]) then
        bar:SetStatusBarTexture(FALLBACK_TEXTURE)
    end
end

-- User Story 1: player and target frames -----------------------------------------------------------
-- Both follow the same "<Name>Content.<Name>ContentMain" nesting for the health bar (confirmed via
-- Modules\UnitFrames.lua's FindBar and AlignManaText, which already resolve this same path). The
-- mana bar does NOT follow the same shape on both: target's is a direct ".ManaBar" child (per
-- AlignManaText), but player's sits one level deeper under ".ManaBarArea.ManaBar" - confirmed via
-- BetterBlizzFrames' source, which touches both paths explicitly as two different shapes.

-- A plain (non-atlas) resource-bar texture carries no inherent color - the client's own atlas art
-- supplied the mana/rage/energy tint, and nothing re-applies a tint on a plain SetStatusBarTexture
-- call; only some later, unrelated unit-power event does (which is why this self-corrected on a
-- target switch or a heal, but not immediately on its own). Confirmed via BetterBlizzFrames'
-- ApplyTextureChange (forever/BetterBlizzFrames.lua): it explicitly sets the power-type color
-- right after swapping a mana bar's texture, for exactly this reason.
--
-- This used to skip entirely for Default, on the assumption its own atlas art always supplies the
-- correct tint already. Confirmed wrong live: PlayerFrame/TargetFrame's classic ManaBar (unlike
-- the personal resource display and party/raid frames, which this client's own code does keep
-- correctly tinted) can land on - or revert to - Mana's blue even for classes/specs that never
-- have Mana (warrior, rogue), with Default selected, and nothing else on this client ever
-- corrects it. Runs unconditionally now; re-asserting an already-correct color is a harmless no-op.
--
-- Called both proactively (login/target-change/power-type-change events below) and reactively,
-- right after the client's own UnitFrameManaBar_UpdateType runs (see Init) - confirmed via
-- BetterBlizzFrames' source as the exact function Blizzard itself uses to tint this bar, and the
-- one it hooks for the same reason: whatever makes this client's own tint land wrong sometimes,
-- it happens inside (or because of) that call, so reasserting only beforehand isn't enough -
-- nothing then corrects it until the next proactive trigger, which is why this looked
-- "intermittent" rather than reliably reproducible from a single event.
local function ApplyResourceColor(bar, unit)
    if not bar or not bar.SetStatusBarColor or not Accessible(bar) then
        return
    end
    -- An empty compact-frame slot (e.g. a pet row with no pet) still calls CompactUnitFrame_SetUnit,
    -- but with frame.unit/displayedUnit both nil - confirmed live via BugSack: UnitPowerType errors
    -- outright on a non-string argument, it doesn't just return no result.
    if type(unit) ~= "string" then
        return
    end
    local _, token = UnitPowerType(unit)
    local color = token and PowerBarColor and PowerBarColor[token]
    if color then
        bar:SetStatusBarColor(color.r, color.g, color.b)
    end
end

local function ApplyUnitFrame(frameName, unit)
    local main = S.Resolve(frameName .. "." .. frameName .. "Content." .. frameName .. "ContentMain")
    if not main then
        return
    end
    local healthContainer = main.HealthBarsContainer
    ApplyTexture(healthContainer and healthContainer.HealthBar)
    local manaArea = main.ManaBarArea
    local manaBar = (manaArea and manaArea.ManaBar) or main.ManaBar
    ApplyTexture(manaBar)
    if manaBar then
        manaBarUnit[manaBar] = unit
    end
    ApplyResourceColor(manaBar, unit)
end

local function ApplyToUnitFrames()
    ApplyUnitFrame("PlayerFrame", "player")
    ApplyUnitFrame("TargetFrame", "target")
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
    ApplyResourceColor(frame.powerBar, frame.displayedUnit or frame.unit)
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
    ApplyResourceColor(frame.PowerBar, "player")
end

-- A power TYPE change (UNIT_DISPLAYPOWER - e.g. a druid shifting Caster/Cat/Bear form) swaps which
-- color a bar should show without any texture change, target change, or PLAYER_ENTERING_WORLD -
-- none of which ApplyToUnitFrames()/ApplyToCompactFrames()/ApplyToPersonalResourceDisplay()'s
-- existing triggers cover. Without this, a bar colored for the unit's previous power type (most
-- visibly: Mana's blue, since every class spends some time in a caster-like state) stays stuck
-- that color indefinitely once a custom texture is in use, since nothing else ever re-tints it.
local function ApplyResourceColorForUnit(unit)
    if unit == "player" then
        ApplyResourceColor(PersonalResourceDisplayFrame and PersonalResourceDisplayFrame.PowerBar, "player")
        local playerMain = S.Resolve("PlayerFrame.PlayerFrameContent.PlayerFrameContentMain")
        local manaArea = playerMain and playerMain.ManaBarArea
        ApplyResourceColor((manaArea and manaArea.ManaBar) or (playerMain and playerMain.ManaBar), "player")
    elseif unit == "target" then
        local targetMain = S.Resolve("TargetFrame.TargetFrameContent.TargetFrameContentMain")
        ApplyResourceColor(targetMain and targetMain.ManaBar, "target")
    end
    for frame in pairs(trackedCompactFrames) do
        local frameUnit = frame.displayedUnit or frame.unit
        if frameUnit == unit then
            ApplyResourceColor(frame.powerBar, unit)
        end
    end
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
    S:On("UNIT_DISPLAYPOWER", function(_, unit) ApplyResourceColorForUnit(unit) end)
    -- Reactive half of the fix (see ApplyResourceColor's comment above): whatever call actually
    -- lands PlayerFrame/TargetFrame's classic ManaBar on the wrong color happens inside Blizzard's
    -- own UnitFrameManaBar_UpdateType, not only in response to events we can enumerate ourselves -
    -- hooksecurefunc fires synchronously right after it, closing that window every single time it
    -- runs, for any reason, rather than only at the specific moments this module already hooks.
    hooksecurefunc("UnitFrameManaBar_UpdateType", function(bar)
        local unit = manaBarUnit[bar]
        if unit then
            ApplyResourceColor(bar, unit)
        end
    end)
    -- Unlike party/raid (CompactUnitFrame_SetUnit) and nameplates (NAME_PLATE_UNIT_ADDED), the
    -- target frame has no equivalent "a new unit is now shown here" hook of its own - without
    -- this, acquiring a target after login left TargetFrame showing whatever it had at
    -- PLAYER_ENTERING_WORLD (no target yet, or the client's own default) instead of the selected
    -- texture, confirmed live: only the target frame drifted out of sync after a /reload.
    S:On("PLAYER_TARGET_CHANGED", function() ApplyToUnitFrames() end)
end

-- Debug (/smuve dump) -------------------------------------------------------------------------------

-- Researching the "custom texture looks slightly bigger than Default" report: whether Blizzard's
-- own mask (a sibling MaskTexture, e.g. HealthBarMask, bigger than the bar itself - presumably
-- carrying a built-in soft vignette) is still attached to GetStatusBarTexture() after we swap in a
-- plain file texture, or whether the swap drops it. GetNumMaskTextures()/GetMaskTexture() read
-- back what's actually attached, rather than assuming either way.
local function DescribeMasks(tex, lines, prefix)
    if not tex or not tex.GetNumMaskTextures then
        table.insert(lines, prefix .. "masks: GetNumMaskTextures not available")
        return
    end
    local okCount, count = pcall(tex.GetNumMaskTextures, tex)
    if not okCount then
        table.insert(lines, prefix .. "masks: error " .. tostring(count))
        return
    end
    table.insert(lines, prefix .. "masks: count=" .. tostring(count))
    for i = 1, (count or 0) do
        local okMask, mask = pcall(tex.GetMaskTexture, tex, i)
        if okMask and mask then
            local okAtlas, atlas = mask.GetAtlas and pcall(mask.GetAtlas, mask)
            atlas = okAtlas and atlas
            local w, h = mask.GetSize and mask:GetSize()
            table.insert(lines, prefix .. "  [" .. i .. "] atlas=" .. tostring(atlas) ..
                " size=" .. tostring(w) .. "x" .. tostring(h))
        else
            table.insert(lines, prefix .. "  [" .. i .. "] error " .. tostring(mask))
        end
    end
end

local function DescribeBar(label, bar, lines)
    if not bar then
        table.insert(lines, label .. " = nil")
        return
    end
    local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
    local atlas = tex and tex.GetAtlas and tex:GetAtlas()
    local file = tex and tex.GetTexture and tex:GetTexture()
    local fileID = tex and tex.GetTextureFileID and tex:GetTextureFileID()
    local captured = originals[bar]
    local capturedDesc
    if type(captured) == "table" then
        capturedDesc = "atlas=" .. tostring(captured.atlas) .. " texture=" .. tostring(captured.texture)
    else
        capturedDesc = tostring(captured) .. " (type=" .. type(captured) .. ")"
    end
    local okColor, r, g, b = pcall(bar.GetStatusBarColor, bar)
    table.insert(lines, string.format(
        "%s live: atlas=%s file=%s fileID=%s color=%s | captured original: %s | tex.SetAtlas=%s",
        label, tostring(atlas), tostring(file), tostring(fileID),
        okColor and string.format("%.2f,%.2f,%.2f", r, g, b) or ("error:" .. tostring(r)),
        capturedDesc, type(tex and tex.SetAtlas)))
    DescribeMasks(tex, lines, label .. "  ")
end

-- Called from Debug.lua's S:Dump(); mirrors Modules\RaidFrames.lua's own debugState pattern.
function M:DebugLines()
    local classColor = S.GetClassColor and S:GetClassColor()
    local lines = {
        "S.db.appearance.barTexture = " .. tostring(S.db.appearance.barTexture),
        "ResolveTexture(current) = " .. tostring(ResolveTexture(S.db.appearance.barTexture)),
        "S:GetClassColor() = " .. (classColor and string.format("%.2f,%.2f,%.2f", classColor.r, classColor.g, classColor.b) or "n/a"),
        "S.db.appearance.classColors = " .. tostring(S.db.appearance.classColors),
    }
    for _, unit in ipairs({ "player", "target" }) do
        local okType, _, token = pcall(UnitPowerType, unit)
        local color = okType and token and PowerBarColor and PowerBarColor[token]
        table.insert(lines, string.format("UnitPowerType(%s) token=%s PowerBarColor=%s",
            unit, tostring(token),
            color and string.format("%.2f,%.2f,%.2f", color.r, color.g, color.b) or "nil"))
    end
    local prd = PersonalResourceDisplayFrame
    table.insert(lines, "== PersonalResourceDisplayFrame")
    if prd then
        local container = prd.HealthBarsContainer
        DescribeBar("healthBar", container and container.healthBar, lines)
        DescribeBar("PowerBar", prd.PowerBar, lines)
        DescribeBar("AlternatePowerBar (should stay untouched)", prd.AlternatePowerBar, lines)
    else
        table.insert(lines, "no PersonalResourceDisplayFrame global")
    end
    table.insert(lines, "== PlayerFrame")
    local playerMain = S.Resolve("PlayerFrame.PlayerFrameContent.PlayerFrameContentMain")
    if playerMain then
        local healthContainer = playerMain.HealthBarsContainer
        DescribeBar("healthBar", healthContainer and healthContainer.HealthBar, lines)
        if healthContainer and healthContainer.HealthBarMask then
            local okA, atlas = pcall(healthContainer.HealthBarMask.GetAtlas, healthContainer.HealthBarMask)
            local w, h = healthContainer.HealthBarMask:GetSize()
            table.insert(lines, "  HealthBarMask sibling: atlas=" .. tostring(okA and atlas) .. " size=" .. tostring(w) .. "x" .. tostring(h))
        else
            table.insert(lines, "  no HealthBarMask sibling")
        end
        local manaArea = playerMain.ManaBarArea
        DescribeBar("manaBar", (manaArea and manaArea.ManaBar) or playerMain.ManaBar, lines)
    else
        table.insert(lines, "no PlayerFrameContentMain")
    end
    table.insert(lines, "== TargetFrame")
    local targetMain = S.Resolve("TargetFrame.TargetFrameContent.TargetFrameContentMain")
    if targetMain then
        local healthContainer = targetMain.HealthBarsContainer
        DescribeBar("healthBar", healthContainer and healthContainer.HealthBar, lines)
        if healthContainer and healthContainer.HealthBarMask then
            local okA, atlas = pcall(healthContainer.HealthBarMask.GetAtlas, healthContainer.HealthBarMask)
            local w, h = healthContainer.HealthBarMask:GetSize()
            table.insert(lines, "  HealthBarMask sibling: atlas=" .. tostring(okA and atlas) .. " size=" .. tostring(w) .. "x" .. tostring(h))
        else
            table.insert(lines, "  no HealthBarMask sibling")
        end
        DescribeBar("manaBar", targetMain.ManaBar, lines)
    else
        table.insert(lines, "no TargetFrameContentMain")
    end
    return lines
end
