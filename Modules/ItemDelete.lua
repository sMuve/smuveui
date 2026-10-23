local _, S = ...
local M = S:NewModule("ItemDelete")

-- Deleting a rare+ quality item normally requires typing the localized "DELETE" word into the
-- confirmation popup before its Confirm button becomes clickable (StaticPopupDialogs.DELETE_GOOD_
-- ITEM/DELETE_GOOD_QUEST_ITEM's own OnShow disables it, EditBoxOnTextChanged only re-enables it
-- once the typed text matches). With this on, a plain click on Confirm is enough instead.

local DIALOGS = {
    DELETE_GOOD_ITEM = true,
    DELETE_GOOD_QUEST_ITEM = true,
}

local function Enabled()
    return S.db.qol.skipDeleteConfirmText
end

-- A single Enable() right after StaticPopup_Show isn't enough on this client - confirmed live,
-- the dialog it actually shows is stock DELETE_GOOD_ITEM (same key), but something keeps
-- re-disabling the button after that (the confirmation text/button labels are themselves
-- customized here, unlike stock Blizzard's, so this server likely re-validates the edit box on
-- its own OnUpdate too). A short ticker that keeps re-asserting Enable() for as long as the
-- dialog is up wins regardless of what's fighting it or how, the same hook-and-reassert pattern
-- used elsewhere in this addon for frames the client insists on re-asserting its own state onto.
local ticker

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function OnStaticPopupShow(which)
    StopTicker()
    if not DIALOGS[which] or not Enabled() then
        return
    end
    -- The field itself is still the default dialog's, just sitting there empty - a clickable Yes
    -- next to an apparently-untouched "type DELETE" field reads as broken, not as "not required
    -- anymore". Filling it with the confirm word itself (same one named in the dialog's own text)
    -- makes it read as already satisfied instead, with no layout changes from hiding anything.
    local dialog = StaticPopup_FindVisible(which)
    local editBox = dialog and dialog.GetEditBox and dialog:GetEditBox()
    if editBox then
        editBox:SetText(DELETE_ITEM_CONFIRM_STRING or "DELETE")
        editBox:ClearFocus()
    end
    ticker = C_Timer.NewTicker(0.05, function()
        local dialog = StaticPopup_FindVisible(which)
        local button = dialog and dialog:IsShown() and dialog.GetButton1 and dialog:GetButton1()
        if not button then
            StopTicker()
            return
        end
        if not button:IsEnabled() then
            button:Enable()
        end
    end)
end

function M:Init()
    hooksecurefunc("StaticPopup_Show", OnStaticPopupShow)
end
