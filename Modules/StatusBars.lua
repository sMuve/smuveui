local _, S = ...
local M = S:NewModule("StatusBars")

-- Scalable experience / reputation bar (the main status tracking bar above the action bars).
-- Scaling keeps the client's own layout (dividers, rested marker) intact, unlike resizing.

local function Container()
    local manager = StatusTrackingBarManager
    return manager and manager.MainStatusTrackingBarContainer
end

function M:Apply()
    local container = Container()
    if not container then
        return
    end
    local scale = S.db.actionbars.xpScale or 1
    -- Never touched while at 1, unless it was scaled before (then it goes back to 1).
    if scale == 1 and not self.scaled then
        return
    end
    self.scaled = scale ~= 1
    if math.abs(container:GetScale() - scale) > 0.001 then
        container:SetScale(scale)
    end
end

function M:Init()
    local container = Container()
    if not container then
        return
    end
    -- Edit Mode may set the scale back when it lays out its systems.
    hooksecurefunc(container, "SetScale", function()
        if (S.db.actionbars.xpScale or 1) ~= 1 then
            C_Timer.After(0, function() M:Apply() end)
        end
    end)
    S:On("PLAYER_ENTERING_WORLD", function()
        M:Apply()
    end)
end

function M:Refresh()
    self:Apply()
end
