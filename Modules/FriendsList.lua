local _, S = ...
local M = S:NewModule("FriendsList")

-- Tints each Battle.net friend row by the faction of their active WoW character
-- (gameAccountInfo.factionName). Plain, non-BNet C_FriendList friends carry no faction info through
-- any stock API - same as retail, where they're always your own faction - so those rows are left
-- alone; EllesmereUI_FriendsKit.lua (same WoW Forever client) doesn't attempt it for them either,
-- confirming this is a real stock limitation rather than a hidden Forever API.
--
-- Hooks Blizzard's own per-row update entry points directly and paints a single translucent
-- texture over the existing row - no frame is recreated or replaced. Which list style is shown
-- (the legacy row list vs. the newer card list) is a server-side switch WoW Forever can flip
-- mid-session (confirmed via EllesmereUI_FriendsKit.lua, which hooks both for the same reason), so
-- both are hooked here too.
local ALLIANCE_COLOR = { 0.15, 0.50, 0.90 }
local HORDE_COLOR = { 0.80, 0.15, 0.15 }
local ALPHA = 0.25

local function GetOverlay(row)
    local tex = row.smuveFactionTint
    if not tex then
        tex = row:CreateTexture(nil, "BACKGROUND", nil, 4)
        tex:SetAllPoints(row)
        tex:SetColorTexture(1, 1, 1, 1)
        row.smuveFactionTint = tex
    end
    return tex
end

local function Paint(row, factionName)
    local color = S.db.qol.friendFactionColors
        and ((factionName == "Alliance" and ALLIANCE_COLOR) or (factionName == "Horde" and HORDE_COLOR))
    if not color then
        if row.smuveFactionTint then
            row.smuveFactionTint:Hide()
        end
        return
    end
    local tex = GetOverlay(row)
    tex:SetVertexColor(color[1], color[2], color[3], ALPHA)
    tex:Show()
end

-- Game mode tag ---------------------------------------------------------------------------------------
-- The Battle.net launcher shows which WoW Forever mode a friend is on (Normal / PvP / Roleplay);
-- the in-game list doesn't. Confirmed live via /smuve dump (15 friends, no mismatch) that it's
-- readable two ways, the same two EllesmereUI_FriendsKit.lua uses: the end of
-- gameAccountInfo.realmName ("CAMWOWEU5Realm2PvP") and the middle of richPresence
-- ("Forever - PvP - Badlands"). Appended to the row's zone text as " [PvP]".
--
-- The realm name is read first: it's a fixed token, so the tag stays short and the same for
-- everyone, where the rich presence wording is whatever the client localizes it to.
local MODE_TAGS = { PvE = "Normal", PvP = "PvP", RP = "RP", RPPvP = "RP-PvP" }

local function PlainString(value)
    return type(value) == "string" and not S.IsSecret(value) and value or nil
end

local function GameMode(gi)
    -- Same client only: another WoW flavor's realm names and rich presence mean other things.
    if type(gi) ~= "table" or not gi.isOnline or gi.wowProjectID ~= WOW_PROJECT_ID then
        return nil
    end
    local realm = PlainString(gi.realmName)
    local suffix = realm and realm:match("Realm%s*%d+%s*(%a+)$")
    if suffix and MODE_TAGS[suffix] then
        return MODE_TAGS[suffix]
    end
    local rich = PlainString(gi.richPresence)
    local mode = rich and rich:match("^.- %- (.-) %- ")
    return mode ~= "" and mode or nil
end

-- fontString -> the tag we last appended to it, so it can be taken off again (option switched
-- off, or the row recycled for a friend on another mode) without guessing at the text.
local appliedTags = setmetatable({}, { __mode = "k" })

-- True while TagInfo itself is writing, so the SetText hook on a card's Location (see PaintCard)
-- doesn't answer our own write.
local taggingInfo = false

local function TagInfo(fontString, gi)
    if not fontString or not fontString.GetText then
        return
    end
    local text = fontString:GetText()
    if S.IsSecret(text) then
        return
    end
    text = text or ""
    local old = appliedTags[fontString]
    if old and text:sub(-#old) == old then
        text = text:sub(1, -#old - 1)
    end
    local mode = S.db.qol.friendGameMode and GameMode(gi)
    local tag = mode and ((text ~= "" and " [" or "[") .. mode .. "]") or nil
    -- The card list color-wraps its zone ("|cff7c848aBadlands|r", confirmed via /smuve dump);
    -- text appended after that "|r" would fall back to the font string's own white, so the tag
    -- takes the same color code.
    local color = tag and text:match("^(|c%x%x%x%x%x%x%x%x)")
    if color then
        tag = color .. tag .. "|r"
    end
    appliedTags[fontString] = tag
    local wanted = tag and (text .. tag) or text
    if wanted ~= fontString:GetText() then
        taggingInfo = true
        fontString:SetText(wanted)
        taggingInfo = false
    end
end

-- Every row/card either hook has touched, for /smuve dump (see DebugVisibleRows) - the card
-- list didn't show up under FriendsListFrame in a dump, and the hooks see both styles either way.
local seenRows = setmetatable({}, { __mode = "k" })

local locationHooked = setmetatable({}, { __mode = "k" })

-- The newer "Social" card list (FriendsListSocialCardMixin).
local function PaintCard(card)
    local accountInfo = card.elementData and card.elementData.accountInfo
    local gi = accountInfo and accountInfo.gameAccountInfo
    seenRows[card] = "card"
    Paint(card, gi and gi.factionName)
    -- card.Location is the card's zone line (confirmed via /smuve dump). Whether the client only
    -- ever writes it during Initialize isn't known, so besides tagging it now, re-tag whenever
    -- anything sets it again - otherwise a later zone update would silently drop the tag.
    local location = card.Location
    if location and location.SetText then
        if not locationHooked[location] then
            locationHooked[location] = true
            hooksecurefunc(location, "SetText", function(self)
                if taggingInfo then
                    return
                end
                local info = card.elementData and card.elementData.accountInfo
                pcall(TagInfo, self, info and info.gameAccountInfo)
            end)
        end
        TagInfo(location, gi)
    end
end

-- The legacy row list, updated via the global FriendsFrame_UpdateFriendButton.
local function PaintRow(button)
    if button.buttonType ~= FRIENDS_BUTTON_TYPE_BNET or not button.id then
        Paint(button, nil)
        return
    end
    local accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
    local gi = accountInfo and accountInfo.gameAccountInfo
    seenRows[button] = "row"
    Paint(button, gi and gi.factionName)
    -- button.info is the legacy row's zone line; Blizzard has just re-set it (this is a post-hook).
    TagInfo(button.info, gi)
end

function M:Init()
    if FriendsListSocialCardMixin then
        hooksecurefunc(FriendsListSocialCardMixin, "Initialize", PaintCard)
    end
    if FriendsFrame_UpdateFriendButton then
        hooksecurefunc("FriendsFrame_UpdateFriendButton", PaintRow)
    end
end

-- Re-paints whatever's on screen right now so the options toggle takes effect without a reload.
function M:Refresh()
    local box = _G.FriendsListFrame and _G.FriendsListFrame.ScrollBox
    if box and box.ForEachFrame then
        box:ForEachFrame(function(frame)
            if frame.elementData then
                PaintCard(frame)
            elseif frame.buttonType then
                PaintRow(frame)
            end
        end)
    end
    -- Not every row was found under FriendsListFrame in a dump; go through what the hooks saw too.
    for frame, kind in pairs(seenRows) do
        pcall(kind == "card" and PaintCard or PaintRow, frame)
    end
end

-- Debug (/smuve dump) -------------------------------------------------------------------------------
-- Research for a "which game mode is this friend on" indicator (Normal / PvP / Roleplay / Roleplay
-- PvP - the Battle.net launcher shows it, the in-game list doesn't). EllesmereUI_FriendsKit.lua
-- (same client) reads it from gameAccountInfo two ways: the middle of richPresence
-- ("Forever - Roleplay PvP - Tirisfal Glades"), falling back to the end of realmName
-- ("CAMWOWUS2Realm10RPPvP"). This records what this client really returns for every online
-- friend, raw, plus what those two readings would make of it.

-- Left out of these data lines: free text and identity a friend didn't choose to hand to a debug
-- file. Rows are identified by list index and character name instead.
local PRIVATE_KEYS = {
    accountName = true, battleTag = true, note = true, customMessage = true,
    customMessageTime = true, bnetAccountID = true, playerGuid = true, gameAccountID = true,
}

-- Every field of a record, sorted, so a WoW-Forever-only field we don't know to ask for by name
-- still shows up (same reasoning as CLAUDE.md's weapon-imbue precedent).
local function FieldList(record)
    if type(record) ~= "table" then
        return tostring(record)
    end
    local keys = {}
    for key in pairs(record) do
        if type(key) == "string" and not PRIVATE_KEYS[key] then
            table.insert(keys, key)
        end
    end
    table.sort(keys)
    local parts = {}
    for _, key in ipairs(keys) do
        local value = record[key]
        local text
        if S.IsSecret(value) then
            text = "<secret>"
        elseif type(value) == "table" then
            text = "{table}"
        elseif type(value) == "string" then
            text = '"' .. value .. '"'
        else
            text = tostring(value)
        end
        table.insert(parts, key .. "=" .. text)
    end
    return table.concat(parts, " | ")
end

local function DescribeGameAccount(prefix, gi, lines)
    if type(gi) ~= "table" then
        table.insert(lines, prefix .. "no gameAccountInfo")
        return
    end
    table.insert(lines, prefix .. FieldList(gi))
    local rich, realm = PlainString(gi.richPresence), PlainString(gi.realmName)
    table.insert(lines, string.format("%s-> richPresence middle=%s | realmName suffix=%s", prefix,
        tostring(rich and rich:match("^.- %- (.-) %- ")),
        tostring(realm and realm:match("Realm%s*%d+%s*(%a+)$"))))
end

local function RuleState(name)
    local rule = Enum and Enum.GameRule and Enum.GameRule[name]
    if not rule then
        return "no such Enum.GameRule"
    end
    if not (C_GameRules and C_GameRules.IsGameRuleActive) then
        return "no C_GameRules.IsGameRuleActive"
    end
    local ok, active = pcall(C_GameRules.IsGameRuleActive, rule)
    if not ok then
        return "error: " .. tostring(active)
    end
    return S.IsSecret(active) and "<secret>" or tostring(active)
end

-- Called from Debug.lua's S:Dump(); mirrors Modules\BarTextures.lua's own DebugLines pattern.
function M:DebugLines()
    local lines = {}
    -- Our own side: what this character's mode reads as, to compare a friend's against (and the
    -- client's own localized mode names, in case the indicator should reuse them).
    table.insert(lines, string.format("self: WOW_PROJECT_ID=%s | GetRealmName=%s | GetNormalizedRealmName=%s",
        tostring(WOW_PROJECT_ID), tostring(GetRealmName and GetRealmName()),
        tostring(GetNormalizedRealmName and GetNormalizedRealmName())))
    table.insert(lines, string.format("self rules: PvPRuleset=%s | RPRuleset=%s | HardcoreRuleset=%s",
        RuleState("PvPRuleset"), RuleState("RPRuleset"), RuleState("HardcoreRuleset")))
    table.insert(lines, string.format(
        "labels: GDAPI_REALMTYPE_NORMAL=%s | _PVP=%s | _RP=%s | _PVP_RP=%s | GUILD_PLAYSTYLE_HARDCORE=%s",
        tostring(GDAPI_REALMTYPE_NORMAL), tostring(GDAPI_REALMTYPE_PVP), tostring(GDAPI_REALMTYPE_RP),
        tostring(GDAPI_REALMTYPE_PVP_RP), tostring(GUILD_PLAYSTYLE_HARDCORE)))
    table.insert(lines, string.format("list style hooks: FriendsListSocialCardMixin=%s | FriendsFrame_UpdateFriendButton=%s",
        type(FriendsListSocialCardMixin), type(FriendsFrame_UpdateFriendButton)))

    if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then
        table.insert(lines, "no BNGetNumFriends / C_BattleNet.GetFriendAccountInfo")
        return lines
    end
    local total, online = BNGetNumFriends()
    table.insert(lines, string.format("BNGetNumFriends: total=%s online=%s", tostring(total), tostring(online)))
    for i = 1, (type(total) == "number" and total or 0) do
        local ok, accountInfo = pcall(C_BattleNet.GetFriendAccountInfo, i)
        local gi = ok and type(accountInfo) == "table" and accountInfo.gameAccountInfo
        -- Offline friends carry nothing useful here; skip them to keep the dump small.
        if type(gi) == "table" and gi.isOnline then
            table.insert(lines, string.format("== BNet friend %d (%s)", i, tostring(PlainString(gi.characterName) or "no character")))
            table.insert(lines, "  account: " .. FieldList(accountInfo))
            DescribeGameAccount("  active: ", gi, lines)
            -- A friend can be on the launcher and in a game at once; the "active" one above is
            -- only whichever the client picked.
            local getNum, getInfo = C_BattleNet.GetFriendNumGameAccounts, C_BattleNet.GetFriendGameAccountInfo
            local okNum, num = pcall(function() return getNum and getNum(i) end)
            if okNum and type(num) == "number" and num > 1 and getInfo then
                for j = 1, num do
                    local okInfo, info = pcall(getInfo, i, j)
                    DescribeGameAccount(string.format("  account %d/%d: ", j, num), okInfo and info, lines)
                end
            end
        elseif not ok then
            table.insert(lines, string.format("== BNet friend %d: error %s", i, tostring(accountInfo)))
        end
    end
    return lines
end

-- The row/card frames currently on screen (friends window must be open), for Debug.lua to walk -
-- where an indicator could be anchored differs between the two list styles.
function M:DebugVisibleRows(limit)
    local rows, others, cards, legacy = {}, {}, 0, 0
    for frame, kind in pairs(seenRows) do
        if kind == "card" then cards = cards + 1 else legacy = legacy + 1 end
        local okVisible, visible = pcall(frame.IsVisible, frame)
        if okVisible and visible then
            -- Prefer a friend who's in this game right now: that's the row the tag goes on.
            local gi
            if kind == "card" then
                local accountInfo = frame.elementData and frame.elementData.accountInfo
                gi = accountInfo and accountInfo.gameAccountInfo
            elseif frame.id then
                local okInfo, accountInfo = pcall(C_BattleNet.GetFriendAccountInfo, frame.id)
                gi = okInfo and accountInfo and accountInfo.gameAccountInfo
            end
            if GameMode(gi) and #rows < limit then
                table.insert(rows, frame)
            elseif #others < limit then
                table.insert(others, frame)
            end
        end
    end
    if #rows == 0 then
        rows = others
    end
    return rows, string.format("cards seen=%d | legacy rows seen=%d", cards, legacy)
end
