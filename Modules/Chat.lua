local addonName, S = ...
local M = S:NewModule("Chat")

-- 1. Chat windows (tabs, names, channels, message types, colors, docking, position, font size) are
--    stored account-wide in SmuveUIDB.chatLayout when you log out, and given to whichever character
--    logs in next. The last character you changed the chat on wins.
-- 2. URLs in chat become links; clicking one opens a box to copy it from.
-- Both are skipped while Chattynator is loaded, since it replaces the chat frames and already does both.
--
-- The layout is applied through the client's stored chat window settings (SetChatWindow*), never
-- through the chat frame functions: frame code run by an addon is tainted, and tainted chat code
-- breaks on protected chat messages in instances. The client builds its windows from those stored
-- settings itself, so after they change a reload shows them.

local function MaxWindows()
    return (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows)
        or NUM_CHAT_WINDOWS or 10
end

local function ChattynatorActive()
    return S.IsAddOnLoaded("Chattynator")
end

local COMBAT_LOG_WINDOW = 2

local function DifferentNumber(a, b)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) > 0.01
end

local function ToSet(list)
    local set = {}
    for _, value in ipairs(list or {}) do
        set[value] = true
    end
    return set
end

-- Every other value of GetChatWindowChannels is a channel name.
local function GetChannels(id)
    local channels, raw = {}, { GetChatWindowChannels(id) }
    for c = 1, #raw, 2 do
        table.insert(channels, raw[c])
    end
    return channels
end

-- Layout capture ----------------------------------------------------------------------------------

local function CaptureLayout()
    local layout = { version = 2, windows = {}, colors = {} }

    for id = 1, MaxWindows() do
        local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(id)
        if name then
            local window = {
                name = name,
                fontSize = fontSize,
                r = r, g = g, b = b, alpha = alpha,
                shown = shown and true or false,
                locked = locked and true or false,
                docked = tonumber(docked) or false,
                uninteractable = uninteractable and true or false,
                messages = { GetChatWindowMessages(id) },
                channels = GetChannels(id),
            }
            if GetChatWindowSavedPosition then
                local point, x, y = GetChatWindowSavedPosition(id)
                if point then
                    window.position = { point = point, x = x, y = y }
                end
            end
            if GetChatWindowSavedDimensions then
                window.width, window.height = GetChatWindowSavedDimensions(id)
            end
            layout.windows[id] = window
        end
    end

    for chatType, info in pairs(ChatTypeInfo or {}) do
        if type(info) == "table" and info.r then
            layout.colors[chatType] = { info.r, info.g, info.b, info.colorNameByClass and true or false }
        end
    end

    return layout
end

-- Layout apply ------------------------------------------------------------------------------------

-- Writes the stored layout into this character's chat settings. Returns true when anything changed.
local function ApplyLayout(layout)
    local changed = false
    local function Call(functionName, ...)
        local fn = _G[functionName]
        if fn then
            fn(...)
            changed = true
        end
    end

    for id = 1, MaxWindows() do
        local window = layout.windows and layout.windows[id]
        local name, fontSize, r, g, b, alpha, shown, locked, docked, uninteractable = GetChatWindowInfo(id)
        if window and name then
            if window.name and window.name ~= name then
                Call("SetChatWindowName", id, window.name)
            end
            if window.fontSize and window.fontSize > 0 and window.fontSize ~= fontSize then
                Call("SetChatWindowSize", id, window.fontSize)
            end
            if window.r and (DifferentNumber(window.r, r) or DifferentNumber(window.g, g) or DifferentNumber(window.b, b)) then
                Call("SetChatWindowColor", id, window.r, window.g, window.b)
            end
            if window.alpha and DifferentNumber(window.alpha, alpha) then
                Call("SetChatWindowAlpha", id, window.alpha)
            end
            if id ~= 1 and window.shown ~= (shown and true or false) then
                Call("SetChatWindowShown", id, window.shown)
            end
            if window.locked ~= (locked and true or false) then
                Call("SetChatWindowLocked", id, window.locked)
            end
            if window.uninteractable ~= (uninteractable and true or false) then
                Call("SetChatWindowUninteractable", id, window.uninteractable)
            end
            local wantDocked = window.docked or nil
            if id ~= 1 and wantDocked ~= (tonumber(docked) or nil) then
                Call("SetChatWindowDocked", id, wantDocked)
            end
            if window.position and window.position.point and GetChatWindowSavedPosition then
                local point, x, y = GetChatWindowSavedPosition(id)
                if point ~= window.position.point or DifferentNumber(x, window.position.x) or DifferentNumber(y, window.position.y) then
                    Call("SetChatWindowSavedPosition", id, window.position.point, window.position.x, window.position.y)
                end
            end
            if window.width and window.height and GetChatWindowSavedDimensions then
                local width, height = GetChatWindowSavedDimensions(id)
                if DifferentNumber(width, window.width) or DifferentNumber(height, window.height) then
                    Call("SetChatWindowSavedDimensions", id, window.width, window.height)
                end
            end

            if id ~= COMBAT_LOG_WINDOW then
                local wanted, current = ToSet(window.messages), ToSet({ GetChatWindowMessages(id) })
                for group in pairs(current) do
                    if not wanted[group] then
                        Call("RemoveChatWindowMessages", id, group)
                    end
                end
                for group in pairs(wanted) do
                    if not current[group] then
                        Call("AddChatWindowMessages", id, group)
                    end
                end

                local wantedChannels, currentChannels = ToSet(window.channels), ToSet(GetChannels(id))
                for channel in pairs(currentChannels) do
                    if not wantedChannels[channel] then
                        Call("RemoveChatWindowChannel", id, channel)
                    end
                end
                for channel in pairs(wantedChannels) do
                    if not currentChannels[channel] then
                        Call("AddChatWindowChannel", id, channel)
                    end
                end
            end
        end
    end

    -- Message colors update live (the client handles UPDATE_CHAT_COLOR itself).
    for chatType, color in pairs(layout.colors or {}) do
        local info = ChatTypeInfo and ChatTypeInfo[chatType]
        if info then
            if ChangeChatColor and (DifferentNumber(info.r, color[1]) or DifferentNumber(info.g, color[2]) or DifferentNumber(info.b, color[3])) then
                ChangeChatColor(chatType, color[1], color[2], color[3])
            end
            if SetChatColorNameByClass and (info.colorNameByClass and true or false) ~= color[4] then
                SetChatColorNameByClass(chatType, color[4])
            end
        end
    end

    return changed
end

-- Version tracking -------------------------------------------------------------------------------
-- A layout only becomes the new shared one when its content really changed, and every character
-- remembers which version it already received, so a layout is applied (and the reload offered)
-- once per character and version.

-- Stable text form of a layout: sorted keys, rounded numbers.
local function Serialize(value)
    if type(value) == "table" then
        local keys = {}
        for key in pairs(value) do
            table.insert(keys, key)
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, key in ipairs(keys) do
            if key ~= "stamp" then
                table.insert(parts, tostring(key) .. "=" .. Serialize(value[key]))
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif type(value) == "number" then
        return string.format("%.2f", value)
    end
    return tostring(value)
end

local function CharacterKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function MarkReceived(stamp)
    S.db.chatReceived = S.db.chatReceived or {}
    S.db.chatReceived[CharacterKey()] = stamp
end

-- Stores a layout as the shared one when it differs from what is stored.
local function Store(layout)
    local current = S.db.chatLayout
    if current and current.version == layout.version and Serialize(current) == Serialize(layout) then
        return
    end
    layout.stamp = time() .. "-" .. math.random(1000000)
    S.db.chatLayout = layout
    MarkReceived(layout.stamp)
end

StaticPopupDialogs["SMUVEUI_CHAT_RELOAD"] = {
    text = "SmuveUI set up your shared chat tabs for this character.\nReload the interface to show them?",
    button1 = RELOADUI or "Reload",
    button2 = LATER or "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- URLs --------------------------------------------------------------------------------------------

local URL_PATTERNS = {
    "%f[%S](%a[%w+.-]+://%S+)",           -- scheme://anything
    "%f[%S](www%.[-%w_%%]+%.%a%a+/%S+)",  -- www.domain.tld/path
    "%f[%S](www%.[-%w_%%]+%.%a%a+)",      -- www.domain.tld
}
local LINK_PREFIX = "addon:" .. addonName .. "url:"
local URL_LINK = "|cff4fb8ff|H" .. LINK_PREFIX .. "%1|h[%1]|h|r"

local URL_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
    "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_WHISPER",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_SYSTEM", "CHAT_MSG_AFK", "CHAT_MSG_DND", "CHAT_MSG_COMMUNITIES_CHANNEL",
    "CHAT_MSG_BN_INLINE_TOAST_ALERT",
}

local function LinkURLs(message)
    if type(message) ~= "string" or S.IsSecret(message) then
        return nil
    end
    if not (message:find("://", 1, true) or message:find("www.", 1, true)) or message:find(LINK_PREFIX, 1, true) then
        return nil
    end
    -- Leave existing hyperlinks (items, players, ...) alone: only the plain text between them changes.
    local pieces, position, changed = {}, 1, false
    while position <= #message do
        local linkStart, linkEnd = message:find("|H.-|h.-|h", position)
        local plain = message:sub(position, (linkStart or 0) - 1)
        for _, pattern in ipairs(URL_PATTERNS) do
            local replaced, count = plain:gsub(pattern, URL_LINK)
            if count > 0 then
                plain = replaced
                changed = true
                break
            end
        end
        table.insert(pieces, plain)
        if not linkStart then
            break
        end
        table.insert(pieces, message:sub(linkStart, linkEnd))
        position = linkEnd + 1
    end
    if not changed then
        return nil
    end
    return table.concat(pieces)
end

local function URLFilter(_, _, message, ...)
    if not S.db.qol.chatUrls then
        return false
    end
    local linked = LinkURLs(message)
    if linked then
        return false, linked, ...
    end
    -- Returning nothing else keeps the original (untainted) arguments.
    return false
end

StaticPopupDialogs["SMUVEUI_COPY_URL"] = {
    text = "Press |cffffd200Ctrl+C|r to copy the link.",
    button1 = CLOSE or "Close",
    hasEditBox = true,
    editBoxWidth = 340,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self, data)
        local editBox = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
        if editBox then
            editBox.smuveURL = data
            editBox:SetText(data or "")
            editBox:HighlightText()
            editBox:SetFocus()
        end
    end,
    EditBoxOnTextChanged = function(editBox)
        -- Keep the box read-only: any typing snaps back to the link.
        if editBox.smuveURL and editBox:GetText() ~= editBox.smuveURL then
            editBox:SetText(editBox.smuveURL)
            editBox:HighlightText()
        end
    end,
    EditBoxOnEnterPressed = function(editBox)
        editBox:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide()
    end,
}

local function OnLinkClicked(_, link)
    if type(link) ~= "string" then
        return
    end
    local url = link:match("^" .. LINK_PREFIX:gsub("%p", "%%%0") .. "(.*)")
    if url then
        StaticPopup_Show("SMUVEUI_COPY_URL", nil, nil, url)
    end
end


-- Chat history --------------------------------------------------------------------------------------
-- The last lines of each chat window (except the combat log, far too busy to keep) are kept in
-- SavedVariables per character and shown again, under a divider, the next time that window opens.
-- Only ever appended to the window with AddMessage, the same as any chat-logging addon; the
-- client's own window configuration (SetChatWindow*) is still the only thing that ever changes a
-- window's setup (see the note at the top of this file).

local HISTORY_LIMIT = 200  -- lines kept per window
local historyHooked = {}   -- chat frame -> true
local historyReplayed = {} -- chat frame -> true, once per session
local historyReplaying = {} -- chat frame -> true while replaying (so the replay isn't re-recorded)

local function HistoryStore()
    S.db.chatHistory = S.db.chatHistory or {}
    local key = CharacterKey()
    S.db.chatHistory[key] = S.db.chatHistory[key] or {}
    return S.db.chatHistory[key]
end

local function RecordLine(id, text, r, g, b)
    if type(text) ~= "string" or S.IsSecret(text) or text == "" then
        return
    end
    local store = HistoryStore()
    local lines = store[id]
    if not lines then
        lines = {}
        store[id] = lines
    end
    table.insert(lines, { text, r, g, b })
    while #lines > HISTORY_LIMIT do
        table.remove(lines, 1)
    end
end

local function HookHistory(chatFrame)
    if not chatFrame or historyHooked[chatFrame] or chatFrame:GetID() == COMBAT_LOG_WINDOW then
        return
    end
    historyHooked[chatFrame] = true
    hooksecurefunc(chatFrame, "AddMessage", function(self, text, r, g, b)
        if not historyReplaying[self] and S.db.qol.chatHistory then
            RecordLine(self:GetID(), text, r, g, b)
        end
    end)
end

local function ReplayHistory(chatFrame)
    local id = chatFrame:GetID()
    local store = S.db.chatHistory and S.db.chatHistory[CharacterKey()]
    local lines = store and store[id]
    if not lines or #lines == 0 then
        return
    end
    historyReplaying[chatFrame] = true
    chatFrame:AddMessage("|cff808080---- previous session ----|r")
    for _, line in ipairs(lines) do
        chatFrame:AddMessage(line[1], line[2] or 1, line[3] or 1, line[4] or 1)
    end
    chatFrame:AddMessage("|cff808080---- new messages ----|r")
    historyReplaying[chatFrame] = false
end

local function SetUpHistory()
    if not S.db.qol.chatHistory then
        return
    end
    for id = 1, MaxWindows() do
        local chatFrame = _G["ChatFrame" .. id]
        if chatFrame and id ~= COMBAT_LOG_WINDOW and GetChatWindowInfo(id) then
            HookHistory(chatFrame)
            if not historyReplayed[chatFrame] then
                historyReplayed[chatFrame] = true
                ReplayHistory(chatFrame)
            end
        end
    end
end

-- Outline --------------------------------------------------------------------------------------
-- An outline on all chat text, applied the same way the resize slider already changes a window's
-- font (SetFont on the chat frame itself) - each chat window is its own Frame with its own font,
-- not the shared font objects Modules\Fonts.lua touches, so this needs its own pass. Resizing a
-- window (or anything else that calls SetFont on it) resets the flags Blizzard's own way, so the
-- outline is watched and reapplied rather than set once.

local outlineHooked = {}
local applyingOutline = {} -- chat frame -> true while our own SetFont runs

local function ApplyOutline(chatFrame)
    local file, size = chatFrame:GetFont()
    if not file or not size then
        return
    end
    applyingOutline[chatFrame] = true
    chatFrame:SetFont(file, size, S.db.qol.chatOutline and "OUTLINE" or "")
    applyingOutline[chatFrame] = nil
end

local function HookOutline(chatFrame)
    if outlineHooked[chatFrame] then
        return
    end
    outlineHooked[chatFrame] = true
    hooksecurefunc(chatFrame, "SetFont", function(self)
        if not applyingOutline[self] then
            ApplyOutline(self)
        end
    end)
end

local function ApplyOutlineAll()
    for id = 1, MaxWindows() do
        local chatFrame = _G["ChatFrame" .. id]
        if chatFrame then
            HookOutline(chatFrame)
            ApplyOutline(chatFrame)
        end
    end
end

-- Module ------------------------------------------------------------------------------------------

function M:Init()
    if ChattynatorActive() then
        return
    end

    local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    for _, event in ipairs(URL_EVENTS) do
        addFilter(event, URLFilter)
    end
    if EventRegistry then
        EventRegistry:RegisterCallback("SetItemRef", OnLinkClicked, self)
    end

    S.SafeCall(ApplyOutlineAll)

    -- Bring this character's chat settings in line with the shared layout, once per session.
    S:On("PLAYER_ENTERING_WORLD", function()
        if self.started then
            return
        end
        self.started = true
        C_Timer.After(1, function()
            local layout = S.db.chatLayout
            if layout and not layout.stamp then
                layout.stamp = "initial" -- stored before versions existed
            end
            local received = S.db.chatReceived and S.db.chatReceived[CharacterKey()]
            if S.db.qol.chatSync and layout and layout.version == 2 and layout.stamp and layout.stamp ~= received then
                local ok, changed = pcall(ApplyLayout, layout)
                if not ok then
                    geterrorhandler()(changed)
                else
                    MarkReceived(layout.stamp)
                    if changed then
                        -- Until the reload, the open chat windows still show the old layout.
                        StaticPopup_Show("SMUVEUI_CHAT_RELOAD")
                    end
                end
            end
            -- What this character's chat looks like now; only real changes are shared at logout.
            local ok, baseline = pcall(CaptureLayout)
            self.baseline = ok and Serialize(baseline) or nil
            self.ready = true

            -- Shows last session's lines (SetUpHistory also starts recording this session's for
            -- next time); after ApplyLayout so a freshly reconfigured window isn't replayed into
            -- right before its reload wipes it anyway.
            S.SafeCall(SetUpHistory)
        end)
    end)

    -- PLAYER_LOGOUT also fires on /reload.
    S:On("PLAYER_LOGOUT", function()
        if not (S.db.qol.chatSync and self.ready) then
            return
        end
        local ok, layout = pcall(CaptureLayout)
        if ok and layout and (not S.db.chatLayout or Serialize(layout) ~= self.baseline) then
            Store(layout)
        end
    end)
end

-- Used by the options panel: makes this character's chat the shared layout right away.
function M:SaveNow()
    if ChattynatorActive() then
        return
    end
    local layout = CaptureLayout()
    Store(layout)
    self.baseline = Serialize(layout)
end

function M:IsAvailable()
    return not ChattynatorActive()
end

-- Turning the history option on after login (it defaults to on) starts it without a reload.
function M:Refresh()
    if ChattynatorActive() then
        return
    end
    S.SafeCall(ApplyOutlineAll)
    if self.ready then
        S.SafeCall(SetUpHistory)
    end
end
