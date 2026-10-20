local _, S = ...
local M = S:NewModule("Fonts")

-- Rajdhani is bundled under Media\Fonts (SIL Open Font License 1.1, see the .txt next to it
-- there): clean, modern and self-contained, so it works with every other addon disabled. Picked
-- over Expressway (what a lot of other UIs use, including one in this user's own addon list)
-- specifically because Expressway's own free license excludes font-file embedding in games/
-- software, and the addon that ships it forbids reusing its files elsewhere - neither applies to
-- an OFL font, which is written to permit exactly this.
local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri", path = "Fonts\\skurri.ttf" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.ttf" },
    { name = "Rajdhani", path = "Interface\\AddOns\\SmuveUI\\Media\\Fonts\\Rajdhani-Regular.ttf" },
    -- A bold weight is a separate font file, not a flag the client can apply to Regular (the
    -- "OUTLINE"/"THICKOUTLINE"/"MONOCHROME" flags SetFont takes don't include bold).
    { name = "Rajdhani Bold", path = "Interface\\AddOns\\SmuveUI\\Media\\Fonts\\Rajdhani-Bold.ttf" },
}

local originalFonts = {}     -- font object -> file
local defaultFont            -- STANDARD_TEXT_FONT at login (read only)

-- The fonts offered in the options: the client's own plus anything registered with LibSharedMedia.
function M:GetFontList()
    local list, seen = {}, {}
    for _, font in ipairs(BUILTIN_FONTS) do
        table.insert(list, font)
        seen[font.path:lower()] = true
    end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local extra = {}
        for name, path in pairs(LSM:HashTable("font")) do
            if type(path) == "string" and not seen[path:lower()] then
                seen[path:lower()] = true
                table.insert(extra, { name = name, path = path })
            end
        end
        table.sort(extra, function(a, b) return a.name < b.name end)
        for _, font in ipairs(extra) do
            table.insert(list, font)
        end
    end
    return list
end

-- The font SmuveUI's own text uses.
function S:GetFont()
    local path = self.db and self.db.appearance.font
    if path and path ~= "DEFAULT" then
        return path
    end
    return defaultFont or STANDARD_TEXT_FONT
end

local function EachFontObject(callback)
    if not GetFonts then
        return
    end
    for _, entry in ipairs(GetFonts()) do
        local fontObject = type(entry) == "string" and _G[entry] or entry
        if type(fontObject) == "table" and fontObject.GetFont and fontObject.SetFont then
            callback(fontObject)
        end
    end
end

function M:Init()
    defaultFont = STANDARD_TEXT_FONT
    EachFontObject(function(fontObject)
        originalFonts[fontObject] = fontObject:GetFont()
    end)
end

function M:Refresh()
    local path = S.db.appearance.font
    local useDefault = not path or path == "DEFAULT"
    if useDefault and not self.changed then
        return
    end
    self.changed = not useDefault

    -- Only font objects are changed. Client globals such as UNIT_NAME_FONT are never written:
    -- the client's own code reads them, and a value written by an addon taints that code, which
    -- then fails on protected unit data (unit frame names stop updating).
    EachFontObject(function(fontObject)
        local _, size, flags = fontObject:GetFont()
        local file = useDefault and originalFonts[fontObject] or path
        if file and size and size > 0 then
            fontObject:SetFont(file, size, flags or "")
        end
    end)

    S:Refresh("Auras")
    S:Refresh("Character")
end
