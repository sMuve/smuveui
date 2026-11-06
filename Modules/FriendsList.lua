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

-- The newer "Social" card list (FriendsListSocialCardMixin).
local function PaintCard(card)
    local accountInfo = card.elementData and card.elementData.accountInfo
    local gi = accountInfo and accountInfo.gameAccountInfo
    Paint(card, gi and gi.factionName)
end

-- The legacy row list, updated via the global FriendsFrame_UpdateFriendButton.
local function PaintRow(button)
    if button.buttonType ~= FRIENDS_BUTTON_TYPE_BNET or not button.id then
        Paint(button, nil)
        return
    end
    local accountInfo = C_BattleNet.GetFriendAccountInfo(button.id)
    local gi = accountInfo and accountInfo.gameAccountInfo
    Paint(button, gi and gi.factionName)
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
end
