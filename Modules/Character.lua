local _, S = ...
local M = S:NewModule("Character")

-- Character frame: every equipped item gets a border in its rarity color, and enchantable slots
-- show a short note of their enchant ("+8 Armor", "+1 Stam") or a red "Missing".

local SIDE_LEFT, SIDE_RIGHT, SIDE_BOTTOM = 1, 2, 3

-- Which side of the slot button the note goes on (the left column writes to its right, etc.).
local SLOT_SIDE = {
    [INVSLOT_HEAD or 1] = SIDE_LEFT,
    [INVSLOT_NECK or 2] = SIDE_LEFT,
    [INVSLOT_SHOULDER or 3] = SIDE_LEFT,
    [INVSLOT_BODY or 4] = SIDE_LEFT,
    [INVSLOT_CHEST or 5] = SIDE_LEFT,
    [INVSLOT_BACK or 15] = SIDE_LEFT,
    [INVSLOT_TABARD or 19] = SIDE_LEFT,
    [INVSLOT_WRIST or 9] = SIDE_LEFT,
    [INVSLOT_HAND or 10] = SIDE_RIGHT,
    [INVSLOT_WAIST or 6] = SIDE_RIGHT,
    [INVSLOT_LEGS or 7] = SIDE_RIGHT,
    [INVSLOT_FEET or 8] = SIDE_RIGHT,
    [INVSLOT_FINGER1 or 11] = SIDE_RIGHT,
    [INVSLOT_FINGER2 or 12] = SIDE_RIGHT,
    [INVSLOT_TRINKET1 or 13] = SIDE_RIGHT,
    [INVSLOT_TRINKET2 or 14] = SIDE_RIGHT,
    [INVSLOT_MAINHAND or 16] = SIDE_BOTTOM,
    [INVSLOT_OFFHAND or 17] = SIDE_BOTTOM,
    [INVSLOT_RANGED or 18] = SIDE_BOTTOM,
}

-- Slots that can always carry an enchant (Classic era: arcanums, shoulder enchants, ...).
local ENCHANTABLE = {
    [INVSLOT_HEAD or 1] = true,
    [INVSLOT_SHOULDER or 3] = true,
    [INVSLOT_BACK or 15] = true,
    [INVSLOT_CHEST or 5] = true,
    [INVSLOT_WRIST or 9] = true,
    [INVSLOT_HAND or 10] = true,
    [INVSLOT_LEGS or 7] = true,
    [INVSLOT_FEET or 8] = true,
    [INVSLOT_MAINHAND or 16] = true,
}

local RANGED_SCOPE_SUBCLASSES = { [2] = true, [3] = true, [18] = true } -- bows, guns, crossbows

-- Real equip slots only. On this client a non-equippable item's equipLoc isn't the empty string
-- Blizzard normally uses - confirmed live via /smuve dump: it's "INVTYPE_NON_EQUIP_IGNORE", which
-- is still a non-empty, truthy string - so excluding bag/bank items from the item level note
-- needs a whitelist of the slots that are actually equipment, not a blacklist of "".
local EQUIPPABLE_LOC = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = true,
    INVTYPE_CHEST = true, INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true,
    INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true, INVTYPE_FINGER = true,
    INVTYPE_TRINKET = true, INVTYPE_CLOAK = true, INVTYPE_WEAPON = true, INVTYPE_SHIELD = true,
    INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_THROWN = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_RELIC = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true,
}

-- Abbreviations, longest match first.
local ABBREVIATIONS = {
    { "Enchant [^%-]+%- ", "" },
    { "Ranged Attack Power", "RAP" },
    { "Attack Power", "AP" },
    { "Spell Damage and Healing", "SP" },
    { "Damage and Healing Spells", "SP" },
    { "Healing and Spell Damage", "SP" },
    { "Healing Spells", "Healing" },
    { "Spell Power", "SP" },
    { "Spell Damage", "SP" },
    { "All Resistances", "All Res" },
    { "All Stats", "Stats" },
    { "Stamina", "Stam" },
    { "Strength", "Str" },
    { "Agility", "Agi" },
    { "Intellect", "Int" },
    { "Spirit", "Spi" },
    { "Defense", "Def" },
    { "Critical Strike", "Crit" },
    { "Fire Resistance", "Fire Res" },
    { "Frost Resistance", "Frost Res" },
    { "Shadow Resistance", "Shadow Res" },
    { "Nature Resistance", "Nature Res" },
    { "Arcane Resistance", "Arcane Res" },
    { "Mana every 5 sec%.?", "MP5" },
    { "mana every 5 sec%.?", "MP5" },
    { "Mana per 5 sec%.?", "MP5" },
    { "Minor Speed Increase", "Speed" },
    { "Run speed increased slightly", "Speed" },
    { "Weapon Damage", "Dmg" },
    { "Health", "HP" },
}

local ENCHANT_PATTERN = ENCHANTED_TOOLTIP_LINE and ("^" .. ENCHANTED_TOOLTIP_LINE:gsub("%%s", "(.+)") .. "$")

local function GetItemInfoInstantCompat(item)
    if C_Item and C_Item.GetItemInfoInstant then
        return C_Item.GetItemInfoInstant(item)
    end
    return GetItemInfoInstant(item)
end

-- The "effective" level (gear upgrades, Timewalking-style scaling, ...) when the client can tell
-- us, otherwise just the item's own base level.
local function GetItemLevelCompat(link)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local effective = C_Item.GetDetailedItemLevelInfo(link)
        if effective and effective > 0 then
            return effective
        end
    elseif GetDetailedItemLevelInfo then
        local effective = GetDetailedItemLevelInfo(link)
        if effective and effective > 0 then
            return effective
        end
    end
    if not GetItemInfo then
        return nil
    end
    local _, _, _, level = GetItemInfo(link)
    return level
end

local function GetEnchantID(link)
    local enchant = link and link:match("item:%-?%d+:(%-?%d*)")
    return tonumber(enchant) or 0
end

local function CanEnchant(slot, link)
    if ENCHANTABLE[slot] then
        return true
    end
    if slot == (INVSLOT_OFFHAND or 17) then
        local _, _, _, equipLoc = GetItemInfoInstantCompat(link)
        return equipLoc ~= "INVTYPE_HOLDABLE"
    end
    if slot == (INVSLOT_RANGED or 18) then
        local _, classFile = UnitClass("player")
        local _, _, _, _, _, classID, subclassID = GetItemInfoInstantCompat(link)
        return classFile == "HUNTER" and classID == 2 and RANGED_SCOPE_SUBCLASSES[subclassID] == true
    end
    return false
end

local function Abbreviate(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for _, rule in ipairs(ABBREVIATIONS) do
        text = text:gsub(rule[1], rule[2])
    end
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- The enchant's tooltip text, nil when the tooltip doesn't list it (yet).
local function GetEnchantText(slot)
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then
        return nil
    end
    local data = C_TooltipInfo.GetInventoryItem("player", slot)
    if not data or not data.lines then
        return nil
    end
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not S.IsSecret(text) then
            local enchant = ENCHANT_PATTERN and text:match(ENCHANT_PATTERN)
            if enchant then
                return Abbreviate(enchant)
            end
        end
    end
    return nil
end

-- Note -------------------------------------------------------------------------------------------

local function GetNote(button)
    if button.smuveNote then
        return button.smuveNote
    end
    local note = button:CreateFontString(nil, "OVERLAY")
    note:SetFont(S:GetFont(), 10, "OUTLINE")
    note:SetWordWrap(true)
    note:SetMaxLines(2)

    local side = SLOT_SIDE[button:GetID()]
    if side == SIDE_LEFT then
        note:SetPoint("LEFT", button, "RIGHT", 6, 0)
        note:SetJustifyH("LEFT")
        note:SetWidth(90)
    elseif side == SIDE_RIGHT then
        note:SetPoint("RIGHT", button, "LEFT", -6, 0)
        note:SetJustifyH("RIGHT")
        note:SetWidth(90)
    else
        note:SetPoint("BOTTOM", button, "TOP", 0, 4)
        note:SetJustifyH("CENTER")
        note:SetWidth(70)
    end
    button.smuveNote = note
    return note
end

-- Item level, in the same bottom corner spot as an aura's remaining duration (Auras.lua), colored
-- by the item's rarity instead of staying plain white.
local function GetLevelText(button)
    local text = button.smuveItemLevel
    if not text then
        text = button:CreateFontString(nil, "OVERLAY")
        text:SetShadowOffset(0, 0)
        text:SetPoint("BOTTOM", button, "BOTTOM", 1, 1)
        button.smuveItemLevel = text
    end
    return text
end

local function GetQualityColor(quality)
    if not quality then
        return 1, 1, 1
    end
    if C_Item and C_Item.GetItemQualityColor then
        -- Returns r, g, b, hexColor; only the first three are wanted here, otherwise the hex
        -- string lands in SetTextColor's alpha argument.
        local r, g, b = C_Item.GetItemQualityColor(quality)
        return r, g, b
    elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local color = ITEM_QUALITY_COLORS[quality]
        return color.r, color.g, color.b
    end
    return 1, 1, 1
end

local function SetItemLevelText(button, level, quality)
    local text = GetLevelText(button)
    text:SetFont(S:GetFont(), S.db.appearance.auraDurationSize + 1, "OUTLINE")
    text:SetTextColor(GetQualityColor(quality))
    text:SetText(level)
end

local function ClearItemLevelText(button)
    if button.smuveItemLevel then
        button.smuveItemLevel:SetText("")
    end
end

local function UpdateItemLevel(button, slot)
    if not S.db.qol.itemLevel then
        ClearItemLevelText(button)
        return
    end
    local link = GetInventoryItemLink("player", slot)
    local level = link and GetItemLevelCompat(link)
    if not level or level <= 0 then
        ClearItemLevelText(button)
        return
    end
    SetItemLevelText(button, level, GetInventoryItemQuality("player", slot))
end

-- Bag and bank item buttons: the same item-level note, but only for equipment (a non-empty
-- equip slot), not consumables/reagents/etc. which clutters up without being wrong.
local function GetContainerItemCompat(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bagID, slotID)
    end
    if GetContainerItemInfo then
        local icon, stackCount, locked, quality, readable, lootable, link, isFiltered, noValue, itemID = GetContainerItemInfo(bagID, slotID)
        if link then
            return { hyperlink = link, quality = quality, itemID = itemID }
        end
    end
    return nil
end

local function UpdateBagButton(button)
    if not button then
        return
    end
    if not S.db.qol.itemLevel then
        ClearItemLevelText(button)
        return
    end
    local bagID = button.GetBagID and button:GetBagID()
    local slotID = button.GetID and button:GetID()
    if not bagID then
        -- Classic-style per-bag container frames: no GetBagID on the item button itself, but
        -- the frame holding it is one bag and its own ID is the bag ID.
        local parent = button:GetParent()
        bagID = parent and parent.GetID and parent:GetID()
    end
    if not bagID or not slotID then
        return
    end
    local info = GetContainerItemCompat(bagID, slotID)
    local link = info and info.hyperlink
    if not link then
        ClearItemLevelText(button)
        return
    end
    local _, _, _, equipLoc = GetItemInfoInstantCompat(link)
    if not equipLoc or not EQUIPPABLE_LOC[equipLoc] then
        ClearItemLevelText(button)
        return
    end
    local level = GetItemLevelCompat(link)
    if not level or level <= 0 then
        ClearItemLevelText(button)
        return
    end
    SetItemLevelText(button, level, info.quality)
end

-- Every bag/bank item button currently on screen, regardless of which container frame (classic
-- or combined bags) or bank panel holds it.
local function ForEachBagButton(callback)
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            if frame.Items then
                for _, button in pairs(frame.Items) do
                    callback(button)
                end
            end
            for j = 1, 36 do
                local button = frame["Item" .. j]
                if button then
                    callback(button)
                end
            end
        end
    end
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags.Items then
        for _, button in pairs(ContainerFrameCombinedBags.Items) do
            callback(button)
        end
    end
    if BankFrame then
        if BankFrame.Items then
            for _, button in pairs(BankFrame.Items) do
                callback(button)
            end
        end
        for j = 1, 28 do
            local button = _G["BankFrameItem" .. j]
            if button then
                callback(button)
            end
        end
    end
end

-- Update -----------------------------------------------------------------------------------------

local function UpdateQualityBorder(button, slot)
    local border = button.IconBorder
    if not border then
        return
    end
    local quality = GetInventoryItemQuality("player", slot)
    if not quality then
        border:Hide()
        return
    end
    local r, g, b = 1, 1, 1
    if C_Item and C_Item.GetItemQualityColor then
        r, g, b = C_Item.GetItemQualityColor(quality)
    elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local color = ITEM_QUALITY_COLORS[quality]
        r, g, b = color.r, color.g, color.b
    end
    border:SetTexture("Interface\\Common\\WhiteIconFrame")
    border:SetVertexColor(r, g, b)
    border:Show()
end

local retries = {}
local retryLink = {} -- slot -> the link the retry count above belongs to

local function UpdateEnchant(button, slot)
    local link = GetInventoryItemLink("player", slot)
    -- A different item in the slot (re-equip, or the old one's retries ran out) starts its own
    -- count: otherwise a slot that already used up its 5 retries on a prior item would carry that
    -- exhausted count over and give the next item's not-yet-cached enchant no retries at all.
    if retryLink[slot] ~= link then
        retries[slot] = nil
        retryLink[slot] = link
    end
    if not link or not SLOT_SIDE[slot] or not CanEnchant(slot, link) then
        if button.smuveNote then
            button.smuveNote:SetText("")
        end
        return
    end

    local note = GetNote(button)
    note:SetFont(S:GetFont(), 10, "OUTLINE")
    if GetEnchantID(link) == 0 then
        note:SetText("|cffff3b3bMissing|r")
        return
    end

    local text = GetEnchantText(slot)
    if text then
        retries[slot] = nil
        note:SetText("|cff3bff5a" .. text .. "|r")
    else
        -- Item data not cached yet: try again shortly.
        note:SetText("|cff3bff5aEnchanted|r")
        retries[slot] = (retries[slot] or 0) + 1
        if retries[slot] <= 5 then
            C_Timer.After(0.5, function()
                if button:IsVisible() then
                    UpdateEnchant(button, slot)
                end
            end)
        end
    end
end

local function UpdateButton(button)
    if not button then
        return
    end
    local slot = button:GetID()
    if not slot or slot < 1 or slot > 19 then
        return
    end
    if S.db.qol.characterInfo then
        UpdateQualityBorder(button, slot)
        UpdateEnchant(button, slot)
    elseif button.smuveNote then
        button.smuveNote:SetText("")
    end
    UpdateItemLevel(button, slot)
end

local SLOT_BUTTONS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

-- Name & class color on the title bar -----------------------------------------------------------
-- The title defaults to just the first name (Blizzard's own UnitName("player"), without the
-- "full name" flag this client repurposes on the second argument - already confirmed elsewhere in
-- this addon, e.g. Debug.lua's GetUnitName(unit, true) calls, which return the full
-- "First Last"). Confirmed live that setting the text/color once doesn't stick - something else
-- (the client's own update, on some later pass our OnShow hook doesn't catch) sets it back - so
-- both are watched and reapplied, the same pattern used everywhere else in this addon for
-- something that keeps getting overwritten.

local applyingName = false
local nameHooked = false

local function UpdateName()
    local title = CharacterFrameTitleText
    if not title then
        return
    end
    local fullName = GetUnitName and GetUnitName("player", true)
    local _, classFile = UnitClass("player")
    local color = classFile and ((C_ClassColor and C_ClassColor.GetClassColor(classFile)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]))
    if not nameHooked then
        nameHooked = true
        hooksecurefunc(title, "SetText", function()
            if not applyingName then
                UpdateName()
            end
        end)
        hooksecurefunc(title, "SetTextColor", function()
            if not applyingName then
                UpdateName()
            end
        end)
    end
    applyingName = true
    if type(fullName) == "string" and not S.IsSecret(fullName) then
        title:SetText(fullName)
    end
    if color then
        title:SetTextColor(color.r, color.g, color.b)
    end
    applyingName = false
end

function M:UpdateBags()
    ForEachBagButton(function(button)
        S.SafeCall(UpdateBagButton, button)
    end)
end

function M:UpdateAll()
    S.SafeCall(UpdateName)
    for _, name in ipairs(SLOT_BUTTONS) do
        local button = _G[name]
        if button then
            S.SafeCall(UpdateButton, button)
        end
    end
    M:UpdateBags()
end

function M:Init()
    if PaperDollItemSlotButton_Update then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
            -- The same function updates bag slots; only character slots have a note side.
            if button and SLOT_SIDE[button:GetID()] and button:GetName() and button:GetName():find("^Character") then
                S.SafeCall(UpdateButton, button)
            end
        end)
    end
    -- ContainerFrameItemButton_Update doesn't exist as a global on this client (confirmed live
    -- via /smuve dump), so bag/bank buttons never got refreshed when their contents actually
    -- changed - only on whatever single occasion the character frame's own events happened to
    -- fire. BAG_UPDATE/BAG_UPDATE_DELAYED catch moving, looting and opening bags; the ticker is a
    -- safety net for anything that changes a shown button without firing either (same reasoning
    -- as the one in Auras.lua).
    if ContainerFrameItemButton_Update then
        hooksecurefunc("ContainerFrameItemButton_Update", function(button)
            S.SafeCall(UpdateBagButton, button)
        end)
    end
    S:On("BAG_UPDATE", function() M:UpdateBags() end)
    S:On("BAG_UPDATE_DELAYED", function() M:UpdateBags() end)
    C_Timer.NewTicker(2, function() M:UpdateBags() end)
    if CharacterFrame then
        CharacterFrame:HookScript("OnShow", function()
            M:UpdateAll()
        end)
    end
    S:On("PLAYER_EQUIPMENT_CHANGED", function()
        if CharacterFrame and CharacterFrame:IsShown() then
            M:UpdateAll()
        end
    end)
end

function M:Refresh()
    self:UpdateAll()
end
