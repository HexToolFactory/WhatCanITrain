local addonName, wt = ...
local L = wt.L

wt.ICON = "Interface\\Icons\\INV_Misc_Book_09"
wt.PREFIX = "|cff33ff99What Can I Train|r: "

local DB_VERSION = 1

function wt.Print(msg)
    print(wt.PREFIX .. tostring(msg))
end

-- Calls fn and returns its results, or nil when fn is missing or raises. The trainer and
-- spell APIs of the Forever client are still changing between beta builds.
function wt.try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if ok then return a, b, c, d, e, f end
    return nil
end

-- Events ---------------------------------------------------------------------

local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, handler in ipairs(list) do handler(...) end
end)

-- Unknown event names raise in RegisterEvent, so optional events are registered protected.
function wt.On(event, handler)
    if not handlers[event] then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        handlers[event] = {}
    end
    tinsert(handlers[event], handler)
    return true
end

-- Player and saved data --------------------------------------------------------

local function initPlayer()
    local className, classFile = UnitClass("player")
    local faction = UnitFactionGroup("player") or "Neutral"
    local _, _, raceID = UnitRace("player")
    wt.player = {
        class = classFile or "UNKNOWN",
        className = className or classFile or "?",
        faction = faction,
        -- most specific first, see wt.VisibleScope
        scopes = { "r" .. tostring(raceID or 0), "f" .. faction },
    }
end

local function initDB()
    local db = WhatCanITrainDB
    local locale = GetLocale()
    if type(db) ~= "table" or db.version ~= DB_VERSION then
        db = { version = DB_VERSION }
        WhatCanITrainDB = db
    end
    -- names are stored as the trainer shows them, so they only fit one client language
    if db.locale ~= locale then
        db.locale = locale
        db.groups = {}
    end
    db.groups = db.groups or {}
    db.chars = db.chars or {}
    wt.db = db

    local charKey = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
    local char = db.chars[charKey] or {}
    db.chars[charKey] = char
    char.known = char.known or {}       -- service key -> true (trainer listed it as already known)
    char.reqHas = char.reqHas or {}     -- required ability name -> had it at the last trainer visit
    char.blocked = char.blocked or {}   -- service key -> true (unavailable for a reason we cannot see)
    char.ignored = char.ignored or {}
    char.scanned = char.scanned or {}   -- group key -> true
    wt.char = char
end

-- Game state helpers ---------------------------------------------------------

local PET_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet

function wt.IsSpellKnown(spellID, includePet)
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if wt.try(C_SpellBook.IsSpellKnown, spellID) then return true end
        if includePet and PET_BANK and wt.try(C_SpellBook.IsSpellKnown, spellID, PET_BANK) then return true end
        return false
    end
    if IsPlayerSpell and wt.try(IsPlayerSpell, spellID) then return true end
    if IsSpellKnown and (wt.try(IsSpellKnown, spellID) or (includePet and wt.try(IsSpellKnown, spellID, true))) then
        return true
    end
    return false
end

-- skill name -> { rank, maxRank, id } for everything the character has
function wt.GetSkills()
    local skills = {}
    if GetProfessions and GetProfessionInfo then
        local profs = { wt.try(GetProfessions) }
        for i = 1, 6 do
            local index = profs[i]
            if index then
                local name, _, rank, maxRank, _, _, skillLine = wt.try(GetProfessionInfo, index)
                if name then
                    skills[name] = { rank = rank or 0, maxRank = maxRank or 0, id = skillLine }
                end
            end
        end
    end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        for i = 1, (wt.try(C_SkillInfo.GetNumSkillLines) or 0) do
            local info = wt.try(C_SkillInfo.GetSkillLineInfo, i)
            if type(info) == "table" and info.name and not info.isHeader and not skills[info.name] then
                skills[info.name] = { rank = info.rank or 0, maxRank = info.maxRank or 0, id = info.skillID }
            end
        end
    end
    return skills
end

function wt.CoinString(amount)
    amount = amount or 0
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(amount)
    end
    if GetCoinTextureString then return GetCoinTextureString(amount) end
    if GetMoneyString then return GetMoneyString(amount) end
    return tostring(amount)
end

-- Rebuild scheduling ---------------------------------------------------------

local rebuildPending = false
function wt.RequestRebuild()
    if rebuildPending or not wt.db then return end
    rebuildPending = true
    C_Timer.After(0.2, function()
        rebuildPending = false
        wt.Rebuild()
    end)
end

wt.On("PLAYER_LOGIN", function()
    initPlayer()
    initDB()
    wt.Rebuild()
    if wt.SetupUI then wt.SetupUI() end
end)

for _, event in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE",
                         "PLAYER_MONEY", "UNIT_PET_TRAINING_POINTS" }) do
    wt.On(event, function() wt.RequestRebuild() end)
end

-- A recipe learned from a drop or a quest never passes through the trainer window.
wt.On("NEW_RECIPE_LEARNED", function(recipeID)
    if wt.char and type(recipeID) == "number" then
        wt.char.known["s" .. recipeID] = true
        wt.RequestRebuild()
    end
end)

-- Slash command --------------------------------------------------------------

local function printStatus()
    local any = false
    for groupKey, group in pairs(wt.db.groups) do
        local count = 0
        for _ in pairs(group.services) do count = count + 1 end
        wt.Print(format("%s (%s): " .. L.STATUS_SCANNED_FORMAT, group.name or groupKey, groupKey, count,
            group.trainer or "?", group.time and date("%Y-%m-%d", group.time) or "?"))
        any = true
    end
    if not any then wt.Print(L.BROKER_NO_DATA) end
end

SLASH_WHATCANITRAIN1 = "/wcit"
SLASH_WHATCANITRAIN2 = "/whatcanitrain"
SlashCmdList["WHATCANITRAIN"] = function(msg)
    if not wt.db then return end
    msg = strlower(strtrim(msg or ""))
    if msg == "" then
        wt.Open()
    elseif msg == "reset" then
        wt.db.groups = {}
        for _, char in pairs(wt.db.chars) do
            char.known, char.reqHas, char.blocked, char.scanned = {}, {}, {}, {}
        end
        wt.Rebuild()
        wt.Print(L.RESET_DONE)
    elseif msg == "unignore" then
        wt.char.ignored = {}
        wt.Rebuild()
        wt.Print(L.RESET_CHAR_DONE)
    elseif msg == "status" then
        printStatus()
    else
        wt.Print(L.HELP_1)
        wt.Print(L.HELP_2)
        wt.Print(L.HELP_3)
        wt.Print(L.HELP_4)
    end
end
