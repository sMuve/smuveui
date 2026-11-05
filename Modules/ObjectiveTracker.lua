local _, S = ...
local M = S:NewModule("ObjectiveTracker")

-- With a questing guide addon loaded (RestedXP, Journey, Polestar), the default objective tracker
-- can be switched off completely. Off by default (QoL options).

-- Matched against each loaded addon's folder name and title (color codes removed).
local GUIDE_PATTERNS = {
    "^RXPGuides", "RestedXP", "Rested XP",
    "%f[%a]Journey%f[%A]",
    "^Polestar$", "^Polestar ", "^Polestar_",
}

local TRACKERS = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }

local detected
local hooked = {}

local function Matches(text)
    if type(text) ~= "string" then
        return false
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    for _, pattern in ipairs(GUIDE_PATTERNS) do
        if text:find(pattern) then
            return true
        end
    end
    return false
end

-- The display name of the first loaded guide addon, or nil.
function M:DetectGuide()
    local getNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local getInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    for index = 1, getNum() do
        local name, title = getInfo(index)
        if name and S.IsAddOnLoaded(name) and (Matches(name) or Matches(title)) then
            return (title and title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or name
        end
    end
    return nil
end

local function ShouldHide()
    return S.db.qol.hideObjectiveTracker and detected ~= nil
end

local function KeepHidden(tracker)
    if not ShouldHide() then
        return
    end
    -- SetAlpha instead of Hide(): the tracker can hold secure quest item buttons, and Hide()ing
    -- it is blocked during combat lockdown - which previously let it flash fully visible for a
    -- moment every time a tracked objective updated mid-combat before the hide could land.
    tracker:SetAlpha(0)
end

function M:Apply()
    for _, name in ipairs(TRACKERS) do
        local tracker = _G[name]
        if tracker and not tracker:IsForbidden() then
            if not hooked[tracker] then
                hooked[tracker] = true
                hooksecurefunc(tracker, "Show", KeepHidden)
                tracker:HookScript("OnShow", KeepHidden)
            end
            if ShouldHide() then
                tracker:SetAlpha(0)
                self.hidden = true
            elseif self.hidden then
                tracker:SetAlpha(1)
            end
        end
    end
    if not ShouldHide() then
        self.hidden = false
    end
end

function M:GetDetected()
    return detected
end

function M:Init()
    detected = self:DetectGuide()
    S:On("ADDON_LOADED", function()
        if not detected then
            detected = M:DetectGuide()
            if detected then
                M:Apply()
            end
        end
    end)
    S:On("PLAYER_ENTERING_WORLD", function()
        M:Apply()
    end)
end

function M:Refresh()
    self:Apply()
end
