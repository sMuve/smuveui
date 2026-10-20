local _, S = ...

-- /smuve dump: writes what the client actually has (frame structure, texts, chat settings) into
-- SmuveUIDB.debug, so it can be read from the saved variables file after a /reload.

local function Safe(value)
    if S.IsSecret(value) then
        return "<secret>"
    end
    return value
end

local function NameOf(region)
    if not region then
        return "nil"
    end
    local ok, name = pcall(function()
        return (region.GetDebugName and region:GetDebugName()) or region:GetName() or tostring(region)
    end)
    if not ok then
        return "?"
    end
    -- tostring() on a secret value stays secret (it doesn't sanitize), unlike Safe() elsewhere
    -- in this file, which is why this slipped into a table.concat further up the call chain.
    if S.IsSecret(name) then
        return "<secret>"
    end
    return tostring(name)
end

local function Points(region)
    local points = {}
    -- GetNumPoints() itself can come back secret for some protected frames (TargetFrameSpellBar
    -- does); used directly as a `for` limit that throws outright ("'for' limit must be a
    -- number"), unlike the point/x/y values below which just degrade to "<secret>" via Safe().
    local count = region:GetNumPoints()
    if S.IsSecret(count) then
        return "<secret point count>"
    end
    for i = 1, count do
        local point, relativeTo, relativePoint, x, y = region:GetPoint(i)
        table.insert(points, string.format("%s>%s:%s(%.1f,%.1f)", tostring(Safe(point)), NameOf(relativeTo),
            tostring(Safe(relativePoint)), tonumber(Safe(x)) or 0, tonumber(Safe(y)) or 0))
    end
    return table.concat(points, " ")
end

local function Describe(region, depth)
    local shown = region:IsShown()
    local parts = {
        string.rep(".", depth) .. region:GetObjectType(),
        NameOf(region),
        S.IsSecret(shown) and "<secret>" or (shown and "shown" or "hidden"),
        string.format("%.1fx%.1f", tonumber(Safe(region:GetWidth())) or -1, tonumber(Safe(region:GetHeight())) or -1),
    }
    if region.GetFrameStrata and region.GetFrameLevel then
        table.insert(parts, "strata=" .. tostring(Safe(region:GetFrameStrata())) ..
            " level=" .. tostring(Safe(region:GetFrameLevel())))
    end
    if region:IsObjectType("Texture") then
        table.insert(parts, "atlas=" .. tostring(region.GetAtlas and region:GetAtlas()))
        table.insert(parts, "file=" .. tostring(region:GetTexture()))
        table.insert(parts, "layer=" .. tostring(region:GetDrawLayer()))
        local r, g, b, a = region:GetVertexColor()
        table.insert(parts, string.format("color=%.2f,%.2f,%.2f,%.2f", tonumber(Safe(r)) or -1,
            tonumber(Safe(g)) or -1, tonumber(Safe(b)) or -1, tonumber(Safe(a)) or -1))
    elseif region:IsObjectType("FontString") then
        table.insert(parts, "text=" .. tostring(Safe(region:GetText())))
        table.insert(parts, "alpha=" .. tostring(Safe(region:GetAlpha())))
        table.insert(parts, "visible=" .. tostring(region:IsVisible()))
        table.insert(parts, "layer=" .. tostring(region:GetDrawLayer()))
        local r, g, b, a = region:GetTextColor()
        table.insert(parts, string.format("textcolor=%.2f,%.2f,%.2f,%.2f", tonumber(Safe(r)) or -1,
            tonumber(Safe(g)) or -1, tonumber(Safe(b)) or -1, tonumber(Safe(a)) or -1))
        table.insert(parts, "stringwidth=" .. tostring(Safe(region:GetStringWidth())))
        if region.HasSecretValues then
            table.insert(parts, "secretvalues=" .. tostring(region:HasSecretValues()))
        end
        local font, size = region:GetFont()
        table.insert(parts, "font=" .. tostring(font) .. "@" .. tostring(size))
    end
    table.insert(parts, Points(region))
    return table.concat(parts, " | ")
end

local function Walk(frame, depth, maxDepth, lines)
    if not frame or frame:IsForbidden() then
        return
    end
    local ok, line = pcall(Describe, frame, depth)
    table.insert(lines, ok and line or ("error: " .. tostring(line)))
    -- GetRegions()/GetChildren() themselves can throw outright ("Attempt to access forbidden
    -- object...") on some of a protected frame's own native children, even when IsForbidden()
    -- above said the frame itself was fine - confirmed live walking into TargetFrame's real
    -- Blizzard aura buttons, which crashed the whole dump uncaught. Both calls are pcall-wrapped
    -- for exactly that reason.
    local regionsOk, regions = pcall(function() return { frame:GetRegions() } end)
    if regionsOk then
        for _, region in ipairs(regions) do
            local regionOk, regionLine = pcall(Describe, region, depth + 1)
            table.insert(lines, regionOk and regionLine or ("error: " .. tostring(regionLine)))
        end
    else
        table.insert(lines, "error getting regions: " .. tostring(regions))
    end
    if depth < maxDepth then
        local childrenOk, children = pcall(function() return { frame:GetChildren() } end)
        if childrenOk then
            for _, child in ipairs(children) do
                Walk(child, depth + 1, maxDepth, lines)
            end
        else
            table.insert(lines, "error getting children: " .. tostring(children))
        end
    end
end

-- Every font string under a frame whose name mentions "name".
local function NameStrings(frame, lines, depth)
    if not frame or depth > 6 or frame:IsForbidden() then
        return
    end
    -- Same reasoning as Walk() above: GetRegions()/GetChildren() themselves can throw outright
    -- on some of a protected frame's native children even past the IsForbidden() check, so both
    -- are pcall-wrapped (confirmed live: this crashed uncaught here, the one recursive walker
    -- that predates that fix being added to Walk() itself).
    local regionsOk, regions = pcall(function() return { frame:GetRegions() } end)
    if regionsOk then
        for _, region in ipairs(regions) do
            local ok, isFontString = pcall(region.IsObjectType, region, "FontString")
            if ok and isFontString and NameOf(region):lower():find("name") then
                local describeOk, line = pcall(Describe, region, 0)
                table.insert(lines, describeOk and line or ("error: " .. tostring(line)))
            end
        end
    end
    local childrenOk, children = pcall(function() return { frame:GetChildren() } end)
    if childrenOk then
        for _, child in ipairs(children) do
            NameStrings(child, lines, depth + 1)
        end
    end
end

function S:Dump()
    local debug = {
        time = date("%Y-%m-%d %H:%M:%S"),
        character = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"),
        build = table.concat({ GetBuildInfo() }, " "),
    }

    -- Whether Build() itself errors right now for either unit - SafeBuild only ever reports its
    -- FIRST error for the whole session, so a later real error could be going completely silent.
    -- Calls the real Build() fresh, bypassing that suppression.
    debug.bigDebuffsBuild = {}
    if S.modules.BigDebuffs and S.modules.BigDebuffs.DebugBuild then
        for _, unit in ipairs({ "player", "target" }) do
            local ok, err = S.modules.BigDebuffs.DebugBuild(unit)
            table.insert(debug.bigDebuffsBuild, unit .. ": " .. (ok and "ok" or ("ERROR: " .. tostring(err))))
        end
    else
        table.insert(debug.bigDebuffsBuild, "BigDebuffs.DebugBuild not available")
    end

    -- XP bar structure.
    debug.xpBar = {}
    Walk(StatusTrackingBarManager, 0, 6, debug.xpBar)

    -- Unit frame names.
    debug.names = {
        "target: " .. tostring(Safe(GetUnitName("target", true))),
        "player: " .. tostring(Safe(GetUnitName("player", true))),
        "target is player: " .. tostring(Safe(UnitIsUnit("target", "player"))),
    }
    for _, frameName in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame" }) do
        table.insert(debug.names, "== " .. frameName)
        NameStrings(_G[frameName], debug.names, 0)
    end

    -- Full player and target frames (name bar, name text and everything around them).
    debug.playerFrame = {}
    Walk(PlayerFrame, 0, 6, debug.playerFrame)
    debug.targetFrame = {}
    Walk(TargetFrame, 0, 6, debug.targetFrame)

    -- Target/focus cast bar repositioning (cast a spell with buffs/debuffs showing first, on
    -- both the target and yourself if possible, to tell the two frames' behavior apart).
    debug.spellBar = {}
    local unitAuras = S.modules.UnitAuras
    for _, info in ipairs({ { unit = "target", bar = "TargetFrameSpellBar" }, { unit = "focus", bar = "FocusFrameSpellBar" } }) do
        local bar = _G[info.bar]
        table.insert(debug.spellBar, "== " .. info.bar)
        if bar then
            local ok, line = pcall(Describe, bar, 0)
            table.insert(debug.spellBar, ok and line or ("error: " .. tostring(line)))
            local count = bar:GetNumPoints()
            if S.IsSecret(count) then
                table.insert(debug.spellBar, "  points: <secret point count>")
            else
                for i = 1, count do
                    local point, relativeTo, relativePoint, x, y = bar:GetPoint(i)
                    table.insert(debug.spellBar, string.format("  point %d: %s > %s:%s (%s, %s)", i,
                        tostring(Safe(point)), NameOf(relativeTo), tostring(Safe(relativePoint)),
                        tostring(Safe(x)), tostring(Safe(y))))
                end
            end
        else
            table.insert(debug.spellBar, "no such frame")
        end
        if unitAuras and unitAuras.spellBarDebug then
            local d = unitAuras.spellBarDebug[info.unit]
            if d then
                table.insert(debug.spellBar, string.format(
                    "  smuve: watchdogHits=%s applies=%s last=%s error=%s",
                    tostring(d.watchdogHits), tostring(d.applies), tostring(d.last), tostring(d.error)))
            else
                table.insert(debug.spellBar, "  smuve: no debug entry for this unit (CaptureSpellBarOriginal never ran)")
            end
        end
    end

    -- Character window border, to check its dark tint.
    -- Character window: the whole frame, to find what draws the band under the title.
    debug.characterFrame = {}
    if CharacterFrame then
        Walk(CharacterFrame, 0, 3, debug.characterFrame)
    end

    -- The target's nameplate (target an enemy before dumping), and what the client offers for
    -- nameplates and aura containers.
    debug.nameplate = {}
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit("target")
    if plate then
        Walk(plate, 0, 7, debug.nameplate)
    else
        table.insert(debug.nameplate, "no nameplate for the target")
    end
    debug.api = {}
    local function Keys(label, source)
        local keys = {}
        for key, value in pairs(source or {}) do
            if type(key) == "string" then
                table.insert(keys, key .. (type(value) == "function" and "()" or ""))
            end
        end
        table.sort(keys)
        debug.api[label] = table.concat(keys, " ")
    end
    Keys("C_NamePlate", C_NamePlate)
    Keys("C_UnitAuras", C_UnitAuras)
    Keys("AuraUtil", AuraUtil)
    Keys("AuraUtil.AuraFilters", AuraUtil and AuraUtil.AuraFilters)
    debug.api["C_CurveUtil"] = tostring(type(_G.C_CurveUtil)) .. " CreateColorCurve=" ..
        tostring(type(_G.C_CurveUtil and _G.C_CurveUtil.CreateColorCurve))
    debug.api["Enum.LuaCurveType"] = tostring(type(_G.Enum and _G.Enum.LuaCurveType))
    debug.api["Enum.CustomAuraButtonDispelTypeTextureStyle"] = tostring(type(_G.Enum and _G.Enum.CustomAuraButtonDispelTypeTextureStyle))
    debug.api["DEBUFF_TYPE_NONE_COLOR"] = tostring(_G.DEBUFF_TYPE_NONE_COLOR and
        (Safe(_G.DEBUFF_TYPE_NONE_COLOR.r) .. "," .. Safe(_G.DEBUFF_TYPE_NONE_COLOR.g) .. "," .. Safe(_G.DEBUFF_TYPE_NONE_COLOR.b)))
    Keys("CustomAuraContainerAuraProcessingPolicy", CustomAuraContainerAuraProcessingPolicy)
    Keys("Enum.UnitAuraSoundTrigger", Enum and Enum.UnitAuraSoundTrigger)
    Keys("NamePlateDriverFrame", NamePlateDriverFrame)
    local ok, container = pcall(CreateFrame, "AuraContainer", nil, nil, "CustomAuraContainerTemplate")
    if ok and container then
        container:Hide()
        local meta = getmetatable(container)
        Keys("AuraContainer methods", meta and meta.__index)
    end
    -- Nameplate settings (CVars) and their values.
    debug.nameplateCVars = {}
    if C_Console and C_Console.GetAllCommands then
        for _, command in ipairs(C_Console.GetAllCommands()) do
            local name = command.command
            if type(name) == "string" and name:lower():find("nameplate") then
                table.insert(debug.nameplateCVars, name .. " = " .. tostring(GetCVar(name)))
            end
        end
        table.sort(debug.nameplateCVars)
    end

    -- The game menu (Esc) and its buttons (open it once before dumping).
    debug.gameMenu = {}
    if GameMenuFrame then
        Walk(GameMenuFrame, 0, 3, debug.gameMenu)
    end

    -- The calendar (open it once before dumping).
    debug.calendar = {}
    if CalendarFrame then
        Walk(CalendarFrame, 0, 2, debug.calendar)
    end

    -- Chat windows as the client stores them, and the shared layout's state.
    debug.chat = {
        "shared stamp: " .. tostring(S.db.chatLayout and S.db.chatLayout.stamp),
        "received here: " .. tostring(S.db.chatReceived and S.db.chatReceived[debug.character]),
    }
    for id = 1, 10 do
        local name, fontSize, _, _, _, alpha, shown, locked, docked = GetChatWindowInfo(id)
        if name then
            table.insert(debug.chat, string.format("%d %q size=%s alpha=%.2f shown=%s locked=%s docked=%s msgs=%d",
                id, name, tostring(fontSize), alpha or 0, tostring(shown), tostring(locked), tostring(docked),
                select("#", GetChatWindowMessages(id))))
        end
    end

    -- World map (open it on a quest-tracked zone first) and the gossip window (talk to an NPC
    -- with quests first), to find the actual name of their embedded quest/dialogue panes.
    debug.questPanels = {}
    if WorldMapFrame and WorldMapFrame:IsShown() then
        Walk(WorldMapFrame, 0, 6, debug.questPanels)
    end
    if GossipFrame and GossipFrame:IsShown() then
        table.insert(debug.questPanels, "== GossipFrame")
        Walk(GossipFrame, 0, 5, debug.questPanels)
    end

    -- Damage meter windows (open a second one before dumping, if you can find how to). Depth 7:
    -- the per-player rows other than LocalPlayerEntry are nested inside MinimizeContainer ->
    -- ScrollBox -> (scroll target) -> row -> StatusBar -> its textures, deeper than the 3 used
    -- here before, which cut off before reaching any of their detail.
    debug.damageMeter = {}
    for i = 1, 3 do
        local window = _G["DamageMeterSessionWindow" .. i]
        if window then
            table.insert(debug.damageMeter, "== DamageMeterSessionWindow" .. i ..
                " shown=" .. tostring(Safe(window:IsShown())))
            Walk(window, 0, 7, debug.damageMeter)
        end
    end
    -- Whatever holds/creates the windows, if it's discoverable by a guessed name.
    for _, name in ipairs({ "DamageMeterFrame", "DamageMeterWindowManager", "DamageMeter", "DamageMeterSessionWindowManager" }) do
        local frame = _G[name]
        if frame then
            table.insert(debug.damageMeter, "== " .. name .. " (exists, type=" .. tostring(type(frame)) .. ")")
            if frame.GetObjectType then
                Walk(frame, 0, 3, debug.damageMeter)
            end
        end
    end
    if C_DamageMeter then
        Keys("C_DamageMeter", C_DamageMeter)
    end

    -- Swing timer bars: search UIParent's own children for any name containing "swing" (not
    -- deeply nested, going by how DamageMeter and the XP bar are both direct UIParent children
    -- too), since the exact frame name isn't known yet.
    debug.swingTimer = {}
    for _, child in ipairs({ UIParent:GetChildren() }) do
        local ok, name = pcall(function() return child.GetName and child:GetName() end)
        if ok and type(name) == "string" and name:lower():find("swing") then
            table.insert(debug.swingTimer, "== " .. name)
            Walk(child, 0, 4, debug.swingTimer)
        end
    end
    if #debug.swingTimer == 0 then
        table.insert(debug.swingTimer, "no UIParent child with \"swing\" in its name")
    end

    -- Loot roll frames (start a group loot roll before dumping, and keep it open).
    local lootModule = S.modules.LootRoll
    debug.lootRoll = {
        "BetterGroupLoot loaded = " ..
            tostring(C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("BetterGroupLoot")),
        "active rolls = " .. tostring(GetActiveLootRollIDs and table.concat(GetActiveLootRollIDs() or {}, ",")),
        -- Module-side state: whether Init() actually set up each frame (SetupFrame used to be
        -- able to silently take the whole module down if one frame's setup threw, with nothing
        -- catching it short of S.SafeCall at the very top of Init - this says directly whether
        -- that happened, instead of inferring it from counter fontstrings missing in the walk
        -- below.
        "LootRoll module initialized=" .. tostring(lootModule and lootModule.initialized) ..
            " frames tracked=" .. tostring(lootModule and lootModule.frames and #lootModule.frames),
    }
    if lootModule and lootModule.frames then
        for _, frame in ipairs(lootModule.frames) do
            table.insert(debug.lootRoll, "tracked: " .. NameOf(frame))
            -- The counter fontstring by its known field (button.smuveCount), directly - no
            -- "smuveCount" entry turned up anywhere in the walk below despite the module tracking
            -- this frame successfully, so this checks whether GetCounter ever actually ran for it.
            for _, key in ipairs({ "NeedButton", "RollButton", "GreedButton", "PassButton" }) do
                local button = frame[key]
                if button then
                    local counter = button.smuveCount
                    if counter then
                        local ok, text = pcall(counter.GetText, counter)
                        table.insert(debug.lootRoll, "  " .. key .. ".smuveCount text=" ..
                            tostring(ok and Safe(text)))
                    else
                        table.insert(debug.lootRoll, "  " .. key .. ".smuveCount = nil")
                    end
                end
            end
        end
    end
    for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
        local frame = _G["GroupLootFrame" .. i]
        if frame then
            table.insert(debug.lootRoll, "== GroupLootFrame" .. i .. " rollID=" .. tostring(frame.rollID))
            Walk(frame, 0, 4, debug.lootRoll)
        end
    end

    -- Target aura test mode's preview holder (our own frame, safe to walk deeply - unlike
    -- TargetFrame's real Blizzard content, which isn't: see the Walk() comment above).
    debug.unitAuras = {}
    local module = S.modules.UnitAuras
    local testMode = S.db.unitAuras.target and S.db.unitAuras.target.testMode
    table.insert(debug.unitAuras, "Target testMode=" .. tostring(testMode))
    local holder = module and module.previews and module.previews.target
    if holder then
        table.insert(debug.unitAuras, "preview holder shown=" .. tostring(Safe(holder:IsShown())))
        Walk(holder, 0, 4, debug.unitAuras)
    else
        table.insert(debug.unitAuras, "no preview holder")
    end

    -- BigDebuffs: strata and level (now that Describe() reports those) for the portrait, the
    -- frame's own border/glow textures, and our own icon containers - to see exactly what's
    -- rendering above/below our icon and why. Named fields only, no GetRegions()/GetChildren()
    -- recursion: that's what crashed the dump twice now walking into unrelated native aura
    -- buttons that happen to share the same ancestor, even with both calls pcall-wrapped.
    debug.bigDebuffs = {}
    local function DescribeNamed(label, region)
        if not region then
            table.insert(debug.bigDebuffs, label .. " = nil")
            return
        end
        local ok, line = pcall(Describe, region, 0)
        table.insert(debug.bigDebuffs, label .. ": " .. (ok and line or ("error: " .. tostring(line))))
    end
    local BIGDEBUFFS_UNITS = {
        player = { frame = "PlayerFrame", container = "PlayerFrameContainer", portrait = "PlayerPortrait" },
        target = { frame = "TargetFrame", container = "TargetFrameContainer", portrait = "Portrait" },
    }
    for unit, info in pairs(BIGDEBUFFS_UNITS) do
        local frame = _G[info.frame]
        local container = frame and frame[info.container]
        table.insert(debug.bigDebuffs, "== " .. info.frame)
        if frame then
            DescribeNamed("frame", frame)
        end
        if container then
            DescribeNamed("container", container)
            DescribeNamed("portrait", container[info.portrait])
            DescribeNamed("FrameTexture", container.FrameTexture)
            DescribeNamed("Flash", container.Flash or container.FrameFlash)
            DescribeNamed("StatusTexture", frame and frame.PlayerFrameContent and
                frame.PlayerFrameContent.PlayerFrameContentMain and frame.PlayerFrameContent.PlayerFrameContentMain.StatusTexture)
        else
            table.insert(debug.bigDebuffs, "no " .. info.container)
        end
        local host = S.modules.BigDebuffs and S.modules.BigDebuffs.hosts and S.modules.BigDebuffs.hosts[unit]
        if host then
            for _, key in ipairs({ "cc", "importantDebuff", "bigDefensive", "externalDefensive", "important" }) do
                DescribeNamed("BigDebuffs." .. key, host[key])
                if key == "importantDebuff" and host[key] then
                    local icon = host[key]
                    local w, h = icon:GetWidth(), icon:GetHeight()
                    table.insert(debug.bigDebuffs, "  importantDebuff icon size=" .. tostring(Safe(w)) .. "x" .. tostring(Safe(h)) ..
                        " shown=" .. tostring(Safe(icon:IsShown())) .. " flatten=" .. tostring(icon.GetFlattensRenderLayers and Safe(icon:GetFlattensRenderLayers())))
                    if icon.art then
                        local okMaskCount, maskCount = pcall(icon.art.GetNumMaskTextures, icon.art)
                        table.insert(debug.bigDebuffs, "  importantDebuff art texture=" .. tostring(Safe(icon.art:GetTexture())) ..
                            " maskCount=" .. tostring(okMaskCount and Safe(maskCount) or ("error:" .. tostring(maskCount))) ..
                            " size=" .. tostring(Safe(icon.art:GetWidth())) .. "x" .. tostring(Safe(icon.art:GetHeight())) ..
                            " layer=" .. tostring(select(1, icon.art:GetDrawLayer())))
                        if okMaskCount and maskCount and maskCount > 0 then
                            local okMask, maskTex = pcall(icon.art.GetMaskTexture, icon.art, 1)
                            if okMask and maskTex then
                                table.insert(debug.bigDebuffs, "  importantDebuff mask atlas=" .. tostring(maskTex.GetAtlas and maskTex:GetAtlas()) ..
                                    " shown=" .. tostring(Safe(maskTex:IsShown())) .. " size=" .. tostring(Safe(maskTex:GetWidth())) .. "x" .. tostring(Safe(maskTex:GetHeight())))
                            end
                        end
                    end
                end
                -- Which aura (if any) actually matched into this specific priority tier - to see
                -- where an aura that isn't showing really lands, instead of guessing at Blizzard's
                -- own (otherwise unreadable) category assignment for it. IsShown() on these
                -- buttons is itself a secret boolean here (confirmed live, crashed the dump
                -- uncaught testing it directly), so instead of filtering on that, every pooled
                -- button is checked and only the ones that resolve to a real aura are reported -
                -- an inactive/empty one naturally has no instance ID to resolve.
                local okChildren, children = pcall(function() return { host[key]:GetChildren() } end)
                if okChildren then
                    local nilId, secretId, resolved = 0, 0, 0
                    for _, button in ipairs(children) do
                        local instanceId = button.auraInstanceID
                        if instanceId == nil and button.GetAuraInstanceID then
                            local okId, id = pcall(button.GetAuraInstanceID, button)
                            if okId then
                                instanceId = id
                            end
                        end
                        if instanceId == nil then
                            nilId = nilId + 1
                        elseif S.IsSecret(instanceId) then
                            secretId = secretId + 1
                        else
                            resolved = resolved + 1
                            local okData, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, instanceId)
                            local name = (okData and auraData and tostring(Safe(auraData.name))) or "no aura data"
                            table.insert(debug.bigDebuffs, "  -- " .. key .. " button instanceId=" ..
                                tostring(Safe(instanceId)) .. ": " .. name)
                        end
                    end
                    table.insert(debug.bigDebuffs, "  " .. key .. " children=" .. #children ..
                        " nilId=" .. nilId .. " secretId=" .. secretId .. " resolved=" .. resolved)
                else
                    table.insert(debug.bigDebuffs, "  " .. key .. " GetChildren error: " .. tostring(children))
                end
            end
        else
            table.insert(debug.bigDebuffs, "no BigDebuffs host for " .. unit)
        end
        -- Every current buff on the unit (plain aura data, not secret - confirmed elsewhere in
        -- this addon), to cross-check against which priority tier (if any) picked each one up.
        for _, kind in ipairs({ "HELPFUL", "HARMFUL" }) do
            local index = 1
            while true do
                local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, kind)
                if not ok or not auraData then
                    break
                end
                table.insert(debug.bigDebuffs, "  " .. kind .. "[" .. index .. "] " .. tostring(Safe(auraData.name)) ..
                    " spellId=" .. tostring(Safe(auraData.spellId)))
                index = index + 1
            end
        end
    end

    -- Compact party frame (join/form a party, or enable the Edit Mode preview, before dumping) -
    -- first look at this part of the UI, so the structure is read rather than guessed.
    debug.partyFrame = {}
    if CompactPartyFrame then
        table.insert(debug.partyFrame, "CompactPartyFrame shown=" .. tostring(Safe(CompactPartyFrame:IsShown())))
        Walk(CompactPartyFrame, 0, 5, debug.partyFrame)
    else
        table.insert(debug.partyFrame, "no CompactPartyFrame global")
    end

    -- The cast bar field directly, by its known name (castBar) rather than a text search - if its
    -- own frame NAME is secret (like several other things on this client), it shows as <secret>
    -- in the walk above and a name-based search would never find it. Cast something as a party
    -- member before dumping so it actually exists to look at.
    for i = 1, 5 do
        local member = _G["CompactPartyFrameMember" .. i]
        local castBar = member and member.castBar
        if castBar then
            table.insert(debug.partyFrame, "== CompactPartyFrameMember" .. i .. ".castBar")
            Walk(castBar, 0, 3, debug.partyFrame)
        elseif member then
            table.insert(debug.partyFrame, "CompactPartyFrameMember" .. i .. ".castBar = nil")
        end
    end

    -- Which aura (if any) actually matched into each of PartyFrames' containers, per member -
    -- same technique as debug.bigDebuffs above (button pools include many inactive entries whose
    -- IsShown() is itself secret here, so this resolves instance IDs instead of trusting shown
    -- state) - to see whether "too many, repetitive" icons means real duplicate matches or just
    -- raw pooled buttons being miscounted.
    debug.partyFrameAuras = {}
    local pfModule = S.modules.PartyFrames
    if pfModule and pfModule.hosts then
        for index = 1, 5 do
            local host = pfModule.hosts[index]
            local frame = _G["CompactPartyFrameMember" .. index]
            local unitName
            if frame and frame.unit then
                local okName, name = pcall(UnitName, frame.unit)
                unitName = okName and Safe(name) or "error"
            end
            table.insert(debug.partyFrameAuras, "== Member" .. index .. " unit=" ..
                tostring(frame and frame.unit) .. " name=" .. tostring(unitName))
            if host then
                for _, key in ipairs({ "buffs", "important" }) do
                    local container = host[key]
                    if container then
                        local okChildren, children = pcall(function() return { container:GetChildren() } end)
                        if okChildren then
                            for _, button in ipairs(children) do
                                local instanceId = button.auraInstanceID
                                if instanceId == nil and button.GetAuraInstanceID then
                                    local okId, id = pcall(button.GetAuraInstanceID, button)
                                    if okId then
                                        instanceId = id
                                    end
                                end
                                if instanceId ~= nil and not S.IsSecret(instanceId) and frame and frame.unit then
                                    local okData, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, frame.unit, instanceId)
                                    local name = (okData and auraData and tostring(Safe(auraData.name))) or "no aura data"
                                    table.insert(debug.partyFrameAuras, "  -- " .. key .. " instanceId=" ..
                                        tostring(Safe(instanceId)) .. ": " .. name)
                                end
                            end
                        end
                    end
                end
            else
                table.insert(debug.partyFrameAuras, "  no host")
            end
        end
    else
        table.insert(debug.partyFrameAuras, "no PartyFrames.hosts")
    end

    -- Player's own buff/debuff border colors (apply a debuff to yourself first, e.g. a poison or
    -- curse, to see its DebuffBorder/smuveBorder color here).
    debug.playerAuras = {}
    for _, frameName in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local auraFrame = _G[frameName]
        if auraFrame then
            table.insert(debug.playerAuras, "== " .. frameName)
            local buttons = auraFrame.auraFrames
            if not buttons and auraFrame.AuraContainer then
                local container = auraFrame.AuraContainer
                local ok, children = pcall(function() return { container:GetChildren() } end)
                buttons = ok and children or {}
            end
            buttons = buttons or {}
            for _, button in ipairs(buttons) do
                table.insert(debug.playerAuras, "-- " .. NameOf(button) ..
                    " AddDispelTypeTexture=" .. type(button.AddDispelTypeTexture) ..
                    " debuffType=" .. tostring(Safe(button.debuffType)))
                local instanceId = button.auraInstanceID
                if instanceId == nil and button.GetAuraInstanceID then
                    local okId, id = pcall(button.GetAuraInstanceID, button)
                    if okId then
                        instanceId = id
                    end
                end
                if instanceId ~= nil and not S.IsSecret(instanceId) then
                    local okData, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", instanceId)
                    table.insert(debug.playerAuras, "   aura=" .. ((okData and auraData and tostring(Safe(auraData.name))) or "no aura data") ..
                        " dispelName=" .. tostring(okData and auraData and Safe(auraData.dispelName)))
                end
                local debuffBorder = button.DebuffBorder
                if debuffBorder then
                    local r, g, b, a = debuffBorder:GetVertexColor()
                    local layer, sublevel = debuffBorder:GetDrawLayer()
                    table.insert(debug.playerAuras, string.format(
                        "DebuffBorder shown=%s alpha=%s layer=%s/%s atlas=%s color=%s,%s,%s,%s",
                        tostring(Safe(debuffBorder:IsShown())), tostring(Safe(debuffBorder:GetAlpha())),
                        tostring(layer), tostring(Safe(sublevel)),
                        tostring(debuffBorder.GetAtlas and debuffBorder:GetAtlas()),
                        tostring(Safe(r)), tostring(Safe(g)), tostring(Safe(b)), tostring(Safe(a))))
                end
                if button.smuveBorder then
                    local r, g, b, a = button.smuveBorder:GetVertexColor()
                    local layer, sublevel = button.smuveBorder:GetDrawLayer()
                    table.insert(debug.playerAuras, string.format("smuveBorder shown=%s alpha=%s layer=%s/%s color=%s,%s,%s,%s",
                        tostring(Safe(button.smuveBorder:IsShown())), tostring(Safe(button.smuveBorder:GetAlpha())),
                        tostring(layer), tostring(Safe(sublevel)),
                        tostring(Safe(r)), tostring(Safe(g)), tostring(Safe(b)), tostring(Safe(a))))
                end
                -- Not every child here is a real aura button - private aura anchor placeholders
                -- end up in the same list and have their own ".Duration", but it's a plain Frame
                -- (no GetText/GetFont), which is what crashed this uncaught before.
                local duration = button.Duration or button.duration
                if duration and duration.GetText and duration.GetFont then
                    local text = duration:GetText()
                    local font, size = duration:GetFont()
                    table.insert(debug.playerAuras, string.format(
                        "Duration text=%q font=%s@%s hooked=%s",
                        tostring(Safe(text)), tostring(font), tostring(Safe(size)), tostring(duration.smuveHooked)))
                end
            end
        end
    end

    -- Bag item buttons (item level feature in Character.lua).
    debug.bags = {
        "ContainerFrameItemButton_Update global=" .. type(_G.ContainerFrameItemButton_Update),
        "C_Container=" .. type(_G.C_Container) ..
            " GetContainerItemInfo=" .. type(_G.C_Container and _G.C_Container.GetContainerItemInfo) ..
            " legacy GetContainerItemInfo=" .. type(_G.GetContainerItemInfo),
        "ContainerFrameCombinedBags=" .. type(_G.ContainerFrameCombinedBags),
    }
    local function DescribeBagButton(button)
        if not button then
            return
        end
        local ok, line = pcall(function()
            local bagID = button.GetBagID and button:GetBagID()
            local slotID = button.GetID and button:GetID()
            local parent = button:GetParent()
            local parentID = parent and parent.GetID and parent:GetID()
            local info
            if _G.C_Container and _G.C_Container.GetContainerItemInfo and bagID and slotID then
                info = _G.C_Container.GetContainerItemInfo(bagID, slotID)
            end
            local legacyLink
            if _G.GetContainerItemInfo and bagID and slotID then
                local _, _, _, _, _, _, link = _G.GetContainerItemInfo(bagID, slotID)
                legacyLink = link
            end
            local link = info and info.hyperlink
            local equipLoc, level
            if link then
                if _G.C_Item and _G.C_Item.GetItemInfoInstant then
                    local _, _, _, loc = _G.C_Item.GetItemInfoInstant(link)
                    equipLoc = loc
                elseif _G.GetItemInfoInstant then
                    local _, _, _, loc = _G.GetItemInfoInstant(link)
                    equipLoc = loc
                end
                if _G.C_Item and _G.C_Item.GetDetailedItemLevelInfo then
                    level = _G.C_Item.GetDetailedItemLevelInfo(link)
                elseif _G.GetDetailedItemLevelInfo then
                    level = _G.GetDetailedItemLevelInfo(link)
                end
                local baseLevel
                if _G.GetItemInfo then
                    local _, _, _, bl = _G.GetItemInfo(link)
                    baseLevel = bl
                end
                return string.format(
                    "%s bagID=%s slotID=%s equipLoc=%q detailedLevel=%s baseLevel=%s smuveItemLevel.text=%s",
                    NameOf(button), tostring(Safe(bagID)), tostring(Safe(slotID)), tostring(Safe(equipLoc)),
                    tostring(Safe(level)), tostring(Safe(baseLevel)),
                    tostring(button.smuveItemLevel and Safe(button.smuveItemLevel:GetText())))
            end
            return string.format(
                "%s bagID=%s slotID=%s parent=%s parentID=%s newInfo.hyperlink=%s newInfo.quality=%s legacyLink=%s smuveItemLevel.text=%s",
                NameOf(button), tostring(Safe(bagID)), tostring(Safe(slotID)), NameOf(parent), tostring(Safe(parentID)),
                tostring(Safe(info and info.hyperlink)), tostring(Safe(info and info.quality)), tostring(Safe(legacyLink)),
                tostring(button.smuveItemLevel and Safe(button.smuveItemLevel:GetText())))
        end)
        table.insert(debug.bags, ok and line or ("error: " .. tostring(line)))
    end
    for i = 1, 13 do
        local frame = _G["ContainerFrame" .. i]
        if frame then
            local shownOk, shown = pcall(frame.IsShown, frame)
            table.insert(debug.bags, "== ContainerFrame" .. i .. " shown=" .. tostring(shownOk and Safe(shown)) ..
                " id=" .. tostring(Safe(frame:GetID())) .. " Items=" .. type(frame.Items))
            if frame.Items then
                for _, button in pairs(frame.Items) do
                    DescribeBagButton(button)
                end
            end
            for j = 1, 36 do
                local button = frame["Item" .. j]
                if button then
                    DescribeBagButton(button)
                end
            end
        end
    end
    if ContainerFrameCombinedBags then
        table.insert(debug.bags, "== ContainerFrameCombinedBags Items=" .. type(ContainerFrameCombinedBags.Items))
        if ContainerFrameCombinedBags.Items then
            for _, button in pairs(ContainerFrameCombinedBags.Items) do
                DescribeBagButton(button)
            end
        end
    end

    -- Modules that are switched off.
    debug.disabledModules = S.db.disabledModules

    S.db.debug = debug
    S.Print("Diagnostics saved. Type /rl so they are written to disk.")
end
