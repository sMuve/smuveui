local _, S = ...
local M = S:NewModule("ActionBars")

-- Range indicator: the whole icon of an action button turns red while its spell is out of range,
-- blue while you lack the mana for it, and gray when it can't be used.

local COLORS = {
    normal = { 1, 1, 1 },
    range = { 0.85, 0.15, 0.15 },
    mana = { 0.35, 0.45, 1 },
    unusable = { 0.4, 0.4, 0.4 },
}

local BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local buttons = {}

local IsUsable = (C_ActionBar and C_ActionBar.IsUsableAction) or IsUsableAction
local InRange = (C_ActionBar and C_ActionBar.IsActionInRange) or IsActionInRange

local function Enabled()
    return S.db.actionbars.rangeIndicator
end

local function EnableRangeCheck(button)
    local action = button.action
    if action and C_ActionBar and C_ActionBar.EnableActionRangeCheck and HasAction(action) then
        C_ActionBar.EnableActionRangeCheck(action, true)
    end
end

local function Color(button)
    if not Enabled() then
        return
    end
    local action, icon = button.action, button.icon or button.Icon
    if not action or not icon or not HasAction(action) then
        return
    end

    local usable, noMana = IsUsable(action)
    local key = "normal"
    if S.IsSecret(usable) or S.IsSecret(noMana) then
        return
    elseif usable then
        local inRange = InRange(action)
        if not S.IsSecret(inRange) and (inRange == false or inRange == 0) and UnitExists("target") then
            key = "range"
        end
    elseif noMana then
        key = "mana"
    else
        key = "unusable"
    end

    local color = COLORS[key]
    icon:SetVertexColor(color[1], color[2], color[3])
end

local function HookButton(button)
    if not button or buttons[button] then
        return
    end
    buttons[button] = true
    if type(button.UpdateUsable) == "function" then
        hooksecurefunc(button, "UpdateUsable", Color)
    end
    if type(button.Update) == "function" then
        hooksecurefunc(button, "Update", function(self)
            EnableRangeCheck(self)
            Color(self)
        end)
    end
    EnableRangeCheck(button)
end

function M:UpdateAll(slot)
    for button in pairs(buttons) do
        if (not slot or button.action == slot) and button:IsVisible() then
            Color(button)
        end
    end
end

function M:Init()
    for _, prefix in ipairs(BARS) do
        for i = 1, 12 do
            HookButton(_G[prefix .. i])
        end
    end
    if ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames then
        for _, button in pairs(ActionBarButtonEventsFrame.frames) do
            HookButton(button)
        end
    end
    -- Older clients update usability through a global function instead of a button method.
    if ActionButton_UpdateUsable then
        hooksecurefunc("ActionButton_UpdateUsable", Color)
    end

    pcall(S.On, S, "ACTION_RANGE_CHECK_UPDATE", function(_, slot)
        if Enabled() and not S.IsSecret(slot) then
            M:UpdateAll(slot)
        end
    end)
    -- Usability (mana) changes arrive through the UpdateUsable hooks above.
    S:On("PLAYER_TARGET_CHANGED", function()
        if Enabled() then
            M:UpdateAll()
        end
    end)
    for _, event in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR" }) do
        S:On(event, function()
            for button in pairs(buttons) do
                EnableRangeCheck(button)
            end
            M:UpdateAll()
        end)
    end

    -- Clients without range events: poll a few times a second while there is a target.
    if not (C_ActionBar and C_ActionBar.EnableActionRangeCheck) then
        C_Timer.NewTicker(0.2, function()
            if Enabled() and UnitExists("target") then
                M:UpdateAll()
            end
        end)
    end
end

function M:Refresh()
    if Enabled() then
        self:UpdateAll()
    else
        -- Hand the icon colors back to the client.
        for button in pairs(buttons) do
            if type(button.UpdateUsable) == "function" then
                button:UpdateUsable()
            else
                local icon = button.icon or button.Icon
                if icon then
                    icon:SetVertexColor(1, 1, 1)
                end
            end
        end
    end
end
