local _, S = ...
local M = S:NewModule("LossOfControl")

-- The loss of control alert: centered on screen, its icon cropped and framed in black.

function M:Init()
    local frame = LossOfControlFrame
    if not frame then
        return
    end

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

    local icon = frame.Icon or frame.icon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local layer, sublevel = icon:GetDrawLayer()
        local border = frame:CreateTexture(nil, layer, nil, math.max((sublevel or 0) - 1, -8))
        border:SetColorTexture(0, 0, 0, 1)
        PixelUtil.SetPoint(border, "TOPLEFT", icon, "TOPLEFT", -2, 2)
        PixelUtil.SetPoint(border, "BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    end
end
