local _, S = ...
local M = S:NewModule("Auras")

-- Player buffs and debuffs (BuffFrame / DebuffFrame): cropped icons with a thin black border and
-- the remaining duration inside the icon, at its bottom.

local styled = {}

local function PlaceDuration(duration)
    local button = duration.smuveButton
    if duration.smuvePlacing then
        return
    end
    duration.smuvePlacing = true
    duration:ClearAllPoints()
    duration:SetPoint("BOTTOM", button.smuveIcon, "BOTTOM", 1, 1)
    duration.smuvePlacing = false
end

-- "8 m" -> "8m" with the unit in the client's yellow; the number stays white. Kept only as a
-- fallback (see StyleDuration below) for whatever rare button doesn't support taking over its
-- duration text outright - on this client duration:GetText() is a SECRET value for every real
-- aura (confirmed live via /smuve dump: "Duration text=<secret>"), so this can never actually
-- match and recolor anything; it's cheap enough to leave running just in case that's ever untrue.
local function CompactDuration(duration)
    if duration.smuveCompacting then
        return
    end
    local text = duration:GetText()
    -- Already done (our own SetText below fires this hook again).
    if type(text) ~= "string" or S.IsSecret(text) or text:find("|c", 1, true) then
        return
    end
    local compact = text:gsub("(%d)%s*(%a+)", "%1|cffffd100%2|r")
    if compact ~= text then
        duration.smuveCompacting = true
        duration:SetText(compact)
        duration.smuveCompacting = false
    end
end

-- The "8m" (white number, yellow unit) format needs the client to apply it internally - the same
-- SetDurationText()+formatter mechanism already used for nameplate, target/focus and BigDebuffs
-- auras - since reading the text back out ourselves to recolor it (the old approach below) can't
-- work on a secret string. Buttons are pooled and reused for different auras, and the client
-- re-registers its OWN duration fontstring whenever a button is reused that way - confirmed live:
-- taking this over only once per button left just whichever aura happened to still be on the
-- button from the last time it was reused correctly formatted, every other one silently reverted.
-- So this is reclaimed on every pass instead of once; SetDurationText is just a binding, calling
-- it again with the same fontstring is harmless.
local function StyleDuration(button)
    local original = button.Duration or button.duration
    if not original and not button.smuveDurationTimer then
        return
    end
    if button.SetDurationText then
        local timer = button.smuveDurationTimer
        if not timer then
            timer = button:CreateFontString(nil, "OVERLAY")
            timer:SetTextColor(1, 1, 1)
            timer:SetShadowOffset(0, 0)
            timer:SetDrawLayer("OVERLAY", 7)
            button.smuveDurationTimer = timer
        end
        local formatter = S.modules.Nameplates.GetUnitDurationFormatter and S.modules.Nameplates.GetUnitDurationFormatter()
        local ok = pcall(button.SetDurationText, button, timer, formatter and { textFormatter = formatter } or {})
        if ok then
            if original and original.SetAlpha then
                original:SetAlpha(0)
            end
            local font, size = S:GetFont(), S.db.appearance.auraDurationSize
            if timer.smuveFont ~= font or timer.smuveSize ~= size then
                timer.smuveFont, timer.smuveSize = font, size
                timer:SetFont(font, size, "OUTLINE")
            end
            timer:ClearAllPoints()
            timer:SetPoint("BOTTOM", button.smuveIcon, "BOTTOM", 1, 1)
            return
        end
        -- Refused this time (a button Blizzard itself built, not one of ours): fall through to
        -- styling its own fontstring directly instead of erroring.
        timer:Hide()
        if original and original.SetAlpha then
            original:SetAlpha(1)
        end
    end
    -- Fallback: couldn't take over the duration display, so Blizzard's own fontstring is styled
    -- directly instead - font, size and position work fine this way, only the yellow-unit
    -- recoloring doesn't (see CompactDuration above).
    if not original then
        return
    end
    original.smuveButton = button
    if not original.smuveHooked then
        original.smuveHooked = true
        hooksecurefunc(original, "SetPoint", PlaceDuration)
        hooksecurefunc(original, "SetText", CompactDuration)
        hooksecurefunc(original, "SetFormattedText", CompactDuration)
    end
    CompactDuration(original)
    local font, size = S:GetFont(), S.db.appearance.auraDurationSize
    if original.smuveFont ~= font or original.smuveSize ~= size then
        original.smuveFont, original.smuveSize = font, size
        original:SetFont(font, size, "OUTLINE")
        original:SetShadowOffset(0, 0)
        original:SetDrawLayer("OVERLAY", 7)
        PlaceDuration(original)
    end
end

-- The stack count sits in the top right corner, as far from the edge as the duration is from
-- the bottom, in the same font.
local function PlaceCount(count)
    if count.smuvePlacing then
        return
    end
    count.smuvePlacing = true
    count:ClearAllPoints()
    count:SetPoint("TOPRIGHT", count.smuveButton.smuveIcon, "TOPRIGHT", -1, -1)
    count.smuvePlacing = false
end

local function StyleCount(button)
    local count = button.Count or button.count
    if not count then
        return
    end
    count.smuveButton = button
    if not count.smuveHooked then
        count.smuveHooked = true
        hooksecurefunc(count, "SetPoint", PlaceCount)
    end
    local font, size = S:GetFont(), S.db.appearance.auraDurationSize
    if count.smuveFont ~= font or count.smuveSize ~= size then
        count.smuveFont, count.smuveSize = font, size
        count:SetFont(font, size, "OUTLINE")
        count:SetShadowOffset(0, 0)
        count:SetDrawLayer("OVERLAY", 7)
        PlaceCount(count)
    end
end

-- All aura text (duration, stacks, debuff type symbol) stays white; the client colors the
-- duration yellow/red as it runs out, which these hooks undo.
local function KeepWhite(fontString)
    if fontString.smuveWhitening then
        return
    end
    fontString.smuveWhitening = true
    fontString:SetTextColor(1, 1, 1)
    fontString.smuveWhitening = false
end

local function WhitenText(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("FontString") then
            if not region.smuveWhiteHooked then
                region.smuveWhiteHooked = true
                hooksecurefunc(region, "SetTextColor", KeepWhite)
                hooksecurefunc(region, "SetVertexColor", KeepWhite)
            end
            KeepWhite(region)
        end
    end
end

local function WhitenButtonText(button)
    WhitenText(button)
    for _, child in ipairs({ button:GetChildren() }) do
        if not child:IsForbidden() then
            WhitenText(child)
        end
    end
end

-- Debuffs keep their dispel type color on the border; everything else is black. The native fix
-- for this (AddDispelTypeTexture, the same one mUI uses - confirmed by reading its forever/
-- Theme/Auras.lua) turned out not to be available here: confirmed live via /smuve dump that
-- "AddDispelTypeTexture=nil" on these specific buttons - it exists on AuraContainer and on
-- buttons an AddAuraGroup call creates itself (used elsewhere in this addon, e.g.
-- Modules\BigDebuffs.lua), but not on Blizzard's own native BuffFrame/DebuffFrame button pool,
-- which this module re-skins rather than replaces. The earlier approach before that (leaving
-- Blizzard's own DebuffBorder visible and just hiding ours) also failed: confirmed live its
-- vertex color stays plain white (1,1,1,1) even for a no-type debuff, so nothing was ever being
-- tinted red/etc automatically to show through in the first place. So this resolves the dispel
-- type by hand instead - the same auraInstanceID -> C_UnitAuras.GetAuraDataByAuraInstanceID
-- lookup already proven non-secret for the player's own auras elsewhere in this addon's debug
-- tooling - and colors our own plain border texture directly from it.
local DISPEL_COLORS = {
    Magic = DEBUFF_TYPE_MAGIC_COLOR,
    Curse = DEBUFF_TYPE_CURSE_COLOR,
    Disease = DEBUFF_TYPE_DISEASE_COLOR,
    Poison = DEBUFF_TYPE_POISON_COLOR,
}

local function GetButtonDispelName(button)
    local instanceId = button.auraInstanceID
    if instanceId == nil and button.GetAuraInstanceID then
        local ok, id = pcall(button.GetAuraInstanceID, button)
        if ok then
            instanceId = id
        end
    end
    if instanceId == nil or S.IsSecret(instanceId) then
        return nil
    end
    local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceId)
    if ok and auraData and not S.IsSecret(auraData.dispelName) then
        return auraData.dispelName
    end
    return nil
end

local function ColorBorder(button, isDebuff)
    local border = button.smuveBorder
    if not isDebuff then
        border:SetColorTexture(0, 0, 0, 1)
        return
    end
    local dispelName = GetButtonDispelName(button)
    local color = (dispelName and DISPEL_COLORS[dispelName]) or DEBUFF_TYPE_NONE_COLOR
    border:SetColorTexture(color.r, color.g, color.b, 1)
end

local function StyleButton(button, isDebuff)
    if not button or button:IsForbidden() then
        return
    end
    local icon = button.Icon or button.icon
    if not icon or not icon.SetTexCoord then
        return
    end
    button.smuveIcon = icon

    if not styled[button] then
        styled[button] = true
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local layer, sublevel = icon:GetDrawLayer()
        local border = button:CreateTexture(nil, layer, nil, math.max((sublevel or 0) - 1, -8))
        PixelUtil.SetPoint(border, "TOPLEFT", icon, "TOPLEFT", -2, 2)
        PixelUtil.SetPoint(border, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
        button.smuveBorder = border

        -- Blizzard's own borders are all hidden - TempEnchantBorder/Border (buffs, never had a
        -- type to show) and DebuffBorder (debuffs - ours takes over that job above) alike.
        for _, key in ipairs({ "TempEnchantBorder", "Border", "DebuffBorder" }) do
            local blizzBorder = button[key]
            if blizzBorder and blizzBorder.SetAlpha then
                blizzBorder:SetAlpha(0)
            end
        end
    end

    ColorBorder(button, isDebuff)
    StyleDuration(button)
    StyleCount(button)
    WhitenButtonText(button)
end

local function StyleContainer(auraFrame, isDebuff)
    if not auraFrame then
        return
    end
    if auraFrame.auraFrames then
        for _, button in ipairs(auraFrame.auraFrames) do
            StyleButton(button, isDebuff)
        end
    end
    local container = auraFrame.AuraContainer
    if container then
        for _, button in ipairs({ container:GetChildren() }) do
            StyleButton(button, isDebuff)
        end
    end
end

function M:StyleAll()
    StyleContainer(BuffFrame, false)
    StyleContainer(DebuffFrame, true)
    -- Classic style aura buttons, if the client still uses them.
    for i = 1, 32 do
        StyleButton(_G["BuffButton" .. i], false)
        StyleButton(_G["DebuffButton" .. i], true)
    end
    for i = 1, 3 do
        StyleButton(_G["TempEnchant" .. i], false)
    end
end

function M:Init()
    for _, auraFrame in ipairs({ BuffFrame or false, DebuffFrame or false }) do
        if auraFrame then
            for _, method in ipairs({ "UpdateAuraButtons", "Update", "UpdateGridLayout" }) do
                if type(auraFrame[method]) == "function" then
                    hooksecurefunc(auraFrame, method, function() M:StyleAll() end)
                end
            end
        end
    end
    if AuraButton_Update then
        hooksecurefunc("AuraButton_Update", function() M:StyleAll() end)
    end
    S:On("UNIT_AURA", function(_, unit)
        if unit == "player" then
            M:StyleAll()
        end
    end)
    S:On("PLAYER_ENTERING_WORLD", function()
        M:StyleAll()
        -- At login the buff/debuff buttons for auras the player already had can be built a
        -- moment after this fires; a plain reload always catches them, so a few delayed
        -- passes here do the same without one.
        for _, delay in ipairs({ 1, 3 }) do
            C_Timer.After(delay, function() M:StyleAll() end)
        end
    end)
    -- Safety net: confirmed live that some buttons' duration takeover (StyleDuration) still
    -- hadn't happened well after login and the delayed passes above, even though the event hooks
    -- that are supposed to catch it (UNIT_AURA, UpdateAuraButtons/Update/UpdateGridLayout) were
    -- all in place - some update path isn't covered by any of them. StyleAll is cheap to repeat
    -- (styled[]/smuveDurationTimer make everything in it a no-op once already done), so this just
    -- keeps calling it at a low, indefinite rate instead of chasing the exact missing trigger.
    C_Timer.NewTicker(2, function() M:StyleAll() end)
end

function M:Refresh()
    self:StyleAll()
end
