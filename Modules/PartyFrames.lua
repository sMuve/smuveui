local _, S = ...
local M = S:NewModule("PartyFrames")

-- The default (raid-style) party frames' own buffs, drawn ourselves and anchored top-right - a
-- /smuve dump of CompactPartyFrame showed no native buff/debuff display anywhere in its
-- structure on this client, so there's nothing to reposition; this draws one instead, the same
-- way every other aura display in this addon does (its own AuraContainer), rather than depending
-- on a native one that isn't there. A second area, centered on the frame and separately sized/
-- capped, shows crowd control first, then important buffs (big/external defensives, other
-- important ones) - the same categories used on enemy nameplates (Modules\Nameplates.lua) and the
-- big portrait icon (Modules\BigDebuffs.lua).
--
-- CompactPartyFrameMember1-5 are static, always-existing frames (confirmed live) - Blizzard just
-- shows/hides them and reassigns their .unit as the group's roster changes, unlike nameplates,
-- which are created and destroyed. So binding is a plain 1-5 loop, no creation/destruction to
-- track.

local AF = AuraUtil and AuraUtil.AuraFilters
local CreateFilterString = AuraUtil and AuraUtil.CreateFilterString
local FlowDirection = AnchorUtil and AnchorUtil.FlowDirection

local MEMBER_COUNT = 5
local CONTAINER_KEYS = { "buffs", "important" }

-- A short, explicit inclusion for buffs Blizzard's own category filter string misses entirely -
-- same list, same reasoning as Modules\BigDebuffs.lua. Needs its OWN aura group below (not
-- candidateFilters bolted onto "Important"): a group's filterString and its candidateFilters are
-- ANDed together, not alternatives, and "Important"'s filter string requires AF.Important
-- membership, which these spells don't have - confirmed live on BigDebuffs.lua the same way
-- before this was split out into its own group there.
local EXTRA_IMPORTANT_SPELLS = {
    [1044] = true,  -- Blessing of Freedom
    [5599] = true,  -- Blessing of Protection
    [5573] = true,  -- Divine Protection
    [20600] = true, -- Perception
    [20216] = true, -- Divine Favor
    [1277462] = true, -- Contingency Plan
    [14751] = true, -- Inner Focus
    [6346] = true, -- Fear Ward
}

local hosts = {} -- index -> { buffs, important, generation }
local generation = 0
M.hosts = hosts -- read by /smuve dump (debug.partyFrameAuras)

local function DB()
    return S.db.partyFrames
end

local function Supported()
    return AF and CreateFilterString and FlowDirection and AuraContainerSortMethod ~= nil
end

local function MemberFrame(index)
    return _G["CompactPartyFrameMember" .. index]
end

-- groups: list of { key, filter, max, size, helpful, candidateFilters }
local function CreateContainer(frame, groups, flowPoint, horizontal, vertical)
    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetEnabled(false)
    container:Hide()
    if container.SetFlattensRenderLayers then
        container:SetFlattensRenderLayers(true)
    end
    container:SetFlowLayoutAnchorPoint(flowPoint)
    container:SetFlowLayoutGrowthDirection(horizontal, vertical)
    for index, group in ipairs(groups) do
        container:AddAuraGroup(group.key, group.filter, {
            maxFrameCount = group.max,
            sortMethod = AuraContainerSortMethod.Default,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = group.candidateFilters,
            initializeFrame = function(button)
                S.modules.Nameplates.InitAuraButton(button, group.size, group.helpful)
            end,
            layout = {
                elementSpacing = 2,
                lineSpacing = 2,
                elementWidth = group.size,
                elementHeight = group.size,
                layoutIndex = index,
            },
        })
    end
    return container
end

-- One combined, flow-managed row for crowd control + important buffs (not four separately
-- centered containers): those would each center their own 1-2 icons on the same point and
-- overlap whenever more than one category is active at once. CC goes first (layoutIndex 1), so
-- it's always the leftmost/first icon when something else is also showing.
local function BuildHost(frame)
    local db = DB()
    local notBig, notExternal, notImportant = "!" .. AF.BigDefensive, "!" .. AF.ExternalDefensive, "!" .. AF.Important
    local host = {}
    host.buffs = CreateContainer(frame, {
        { key = "Buffs", filter = CreateFilterString(AF.Helpful), max = db.buffMax, size = db.buffSize, helpful = true },
    }, "TOPRIGHT", FlowDirection.Left, FlowDirection.Down)
    -- AF.IncludeNameplateOnly: despite the name, this isn't about displaying on a nameplate -
    -- it's needed to even match some of these spells at all (e.g. Blessing of Protection/
    -- Freedom, confirmed missing here the same way on Modules\BigDebuffs.lua; both now match
    -- Modules\Nameplates.lua, which already includes it in this exact filter).
    host.important = CreateContainer(frame, {
        { key = "CC", filter = CreateFilterString(AF.Harmful, AF.IncludeNameplateOnly, AF.CrowdControl), max = db.ccMax, size = db.ccSize, helpful = false },
        { key = "DefBig", filter = CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, AF.BigDefensive), max = db.ccMax, size = db.ccSize, helpful = true },
        { key = "DefExt", filter = CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, notBig, AF.ExternalDefensive), max = db.ccMax, size = db.ccSize, helpful = true },
        { key = "Important", filter = CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, notBig, notExternal, AF.Important), max = db.ccMax, size = db.ccSize, helpful = true },
        -- Excludes the same three categories the other groups above already claim - without that,
        -- a spell on this explicit list that Blizzard also tags BigDefensive/ExternalDefensive/
        -- Important (e.g. Blessing of Protection, both here and ExternalDefensive) matched two
        -- groups at once and rendered twice.
        { key = "Extra", filter = CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, notBig, notExternal, notImportant),
            max = db.ccMax, size = db.ccSize, helpful = true,
            candidateFilters = { includeSpellIDs = EXTRA_IMPORTANT_SPELLS } },
    }, "TOPLEFT", FlowDirection.Right, FlowDirection.Down)
    -- A new frame's strata defaults to MEDIUM regardless of its parent's (confirmed elsewhere in
    -- this addon to matter: Modules\BigDebuffs.lua), so it's pinned to the member frame's own.
    for _, key in ipairs(CONTAINER_KEYS) do
        host[key]:SetFrameStrata(frame:GetFrameStrata())
    end
    host.buffs:SetFrameLevel(frame:GetFrameLevel() + 10)
    host.important:SetFrameLevel(frame:GetFrameLevel() + 11)
    return host
end

local function DisableHost(host)
    if not host then
        return
    end
    for _, key in ipairs(CONTAINER_KEYS) do
        host[key]:SetEnabled(false)
        host[key]:Hide()
    end
end

local function Bind(index)
    local frame = MemberFrame(index)
    if not frame then
        return
    end
    local db = DB()
    local host = hosts[index]
    if host and host.generation ~= generation then
        DisableHost(host)
        hosts[index] = nil
        host = nil
    end

    local unit = frame.unit
    if not db.enabled or not unit then
        DisableHost(host)
        return
    end

    if not host then
        host = BuildHost(frame)
        host.generation = generation
        hosts[index] = host
    end

    host.buffs:ClearAllPoints()
    host.buffs:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    host.important:ClearAllPoints()
    host.important:SetPoint("CENTER", frame, "CENTER", 0, 0)

    for _, key in ipairs(CONTAINER_KEYS) do
        local container = host[key]
        container:SetUnit(unit)
        container:SetEnabled(true)
        container:Show()
        if container.UpdateAllAuras then
            container:UpdateAllAuras()
        end
    end
end

local function BindAll()
    for index = 1, MEMBER_COUNT do
        local ok, err = pcall(Bind, index)
        if not ok then
            geterrorhandler()(err)
        end
    end
end

-- Module -------------------------------------------------------------------------------------------

function M:Init()
    if not Supported() then
        return
    end
    -- Catches a roster change the moment Blizzard reassigns a member frame's unit, rather than
    -- waiting for the group event below.
    if CompactUnitFrame_SetUnit then
        hooksecurefunc("CompactUnitFrame_SetUnit", function(frame)
            local name = frame and frame.GetName and frame:GetName()
            local index = name and name:match("^CompactPartyFrameMember(%d+)$")
            if index then
                pcall(Bind, tonumber(index))
            end
        end)
    end
    S:On("GROUP_ROSTER_UPDATE", function()
        C_Timer.After(0, BindAll)
    end)
    S:On("PLAYER_ENTERING_WORLD", function()
        C_Timer.After(0.5, BindAll)
    end)
end

function M:Refresh()
    if not Supported() then
        return
    end
    generation = generation + 1
    BindAll()
end

function M:IsSupported()
    return Supported()
end
