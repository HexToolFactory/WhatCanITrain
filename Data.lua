local _, wt = ...
local L = wt.L

-- Turns the recorded trainer services into the categorized lists the panels show.

local ORDER = { "available", "missingReqs", "soon", "later", "ignored", "known" }
local HEADER = {
    available = { text = L.AVAILABLE_HEADER, costFormat = L.TOTALCOST_FORMAT },
    missingReqs = { text = L.MISSINGREQS_HEADER, costFormat = L.TOTALCOST_FORMAT },
    soon = { text = L.NEXTLEVEL_HEADER, costFormat = L.TOTALCOST_FORMAT },
    later = { text = L.NOTLEVEL_HEADER, costFormat = L.TOTALCOST_FORMAT },
    -- unchecked by the player: not bought now, so left out of every other total
    ignored = { text = L.SKIPPED_HEADER, costFormat = L.SKIPPED_COST_FORMAT },
    known = { text = L.KNOWN_HEADER, costFormat = L.TOTALSPENT_FORMAT },
}
-- "Coming Soon" reaches this far ahead of the character
local SOON_LEVELS, SOON_SKILL = 2, 25

wt.results = {}

function wt.NewContext()
    return {
        level = UnitLevel("player") or 1,
        petLevel = UnitLevel("pet") or 0,
        skills = wt.GetSkills(),
        money = GetMoney and GetMoney() or 0,
    }
end

local function skillRank(name, group, ctx)
    local skill = ctx.skills[name]
    if skill then return skill.rank end
    if group.skillID and group.skill == name and C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local info = wt.try(C_SkillInfo.GetSkillLineInfoByID, group.skillID)
        if type(info) == "table" and (info.maxRank or 0) > 0 then return info.rank or 0 end
    end
end

-- Spell lookups by name only resolve for spells the character has, which covers talents
-- picked up since the last trainer visit; the trainer's own verdict is the fallback.
local function hasAbility(name)
    if C_Spell and C_Spell.GetSpellInfo and wt.try(C_Spell.GetSpellInfo, name) then return true end
    return wt.char.reqHas[name] == true
end

local function effectiveLevel(group, ctx)
    if group.kind == "pet" and ctx.petLevel > 0 then return ctx.petLevel end
    return ctx.level
end

-- raw: judge only level, skill and ability requirements (used while scanning)
function wt.ComputeStatus(svc, key, group, ctx, raw)
    local char = wt.char
    if not raw then
        if char.known[key] or (svc.t == "spell" and svc.id and wt.IsSpellKnown(svc.id, group.kind == "pet")) then
            return "known"
        end
        if char.ignored[key] then return "ignored" end
    end

    local levelGap = math.max(0, (svc.level or 0) - effectiveLevel(group, ctx))
    local skillGap = 0
    if svc.skill and svc.skillRank then
        local rank = skillRank(svc.skill, group, ctx)
        skillGap = rank and math.max(0, svc.skillRank - rank) or math.huge
    end
    if levelGap > 0 or skillGap > 0 then
        return (levelGap <= SOON_LEVELS and skillGap <= SOON_SKILL) and "soon" or "later"
    end

    if svc.reqs then
        for _, name in ipairs(svc.reqs) do
            if not hasAbility(name) then return "missingReqs" end
        end
    end
    if not raw and char.blocked[key] then return "missingReqs" end
    return "available"
end

-- Lists differ by race and faction (racial priest spells, city portals). Show what a
-- character of the same race recorded; failing that the same faction; failing that all.
local function visibleScope(group)
    local scopes = group.scopes or {}
    for _, scope in ipairs(wt.player.scopes) do
        if scopes[scope] then return scope end
    end
end

local function rankNumber(entry)
    return tonumber(strmatch(entry.sub or "", "%d+")) or 0
end

local function byRequirement(a, b)
    if a.sortReq ~= b.sortReq then return a.sortReq < b.sortReq end
    if a.name ~= b.name then return a.name < b.name end
    return rankNumber(a) < rankNumber(b)
end

local function byName(a, b)
    if a.name ~= b.name then return a.name < b.name end
    if a.sortReq ~= b.sortReq then return a.sortReq < b.sortReq end
    return rankNumber(a) < rankNumber(b)
end

local function requirementText(svc, group)
    if group.kind == "prof" and svc.skillRank then return format(L.SKILL_FORMAT, svc.skillRank) end
    if (svc.level or 0) > 0 then return format(L.LEVEL_FORMAT, svc.level) end
    return ""
end

function wt.BuildGroup(groupKey, ctx)
    local group = wt.db.groups[groupKey]
    local result = { key = groupKey, group = group, byStatus = {}, total = 0 }
    for _, status in ipairs(ORDER) do
        result.byStatus[status] = { status = status, entries = {}, cost = 0 }
    end
    if not group then return result end

    local scope = visibleScope(group)
    for key, svc in pairs(group.services) do
        if not scope or (svc.seen and svc.seen[scope]) then
            local status = wt.ComputeStatus(svc, key, group, ctx)
            local fullName = svc.sub and format("%s (%s)", svc.name, svc.sub) or svc.name
            local category = result.byStatus[status]
            tinsert(category.entries, {
                key = key,
                svc = svc,
                group = group,
                status = status,
                name = svc.name,
                sub = svc.sub,
                fullName = fullName,
                cost = svc.cost or 0,
                reqText = requirementText(svc, group),
                sortReq = (svc.skillRank or 0) * 1000 + (svc.level or 0),
                search = strlower(fullName .. " " .. (svc.cat or "")),
            })
            category.cost = category.cost + (svc.cost or 0)
            result.total = result.total + 1
        end
    end
    for _, status in ipairs(ORDER) do
        local sorter = (status == "known" or status == "ignored") and byName or byRequirement
        sort(result.byStatus[status].entries, sorter)
    end
    return result
end

-- Flat row list for a panel: one header per non-empty category, then its entries.
function wt.Rows(result, filter)
    local rows = {}
    filter = filter or ""
    for _, status in ipairs(ORDER) do
        local matched, cost = {}, 0
        for _, entry in ipairs(result.byStatus[status].entries) do
            if filter == "" or strfind(entry.search, filter, 1, true) then
                tinsert(matched, entry)
                cost = cost + entry.cost
            end
        end
        if #matched > 0 then
            tinsert(rows, {
                isHeader = true,
                status = status,
                text = HEADER[status].text,
                costFormat = HEADER[status].costFormat,
                cost = cost,
                count = #matched,
                group = result.group,
            })
            for _, entry in ipairs(matched) do tinsert(rows, entry) end
        end
    end
    return rows
end

function wt.CostText(row)
    if row.group and row.group.kind == "pet" then return format(L.TRAINING_POINTS_FORMAT, row.cost or 0) end
    return wt.CoinString(row.cost or 0)
end

-- { text, ok } for every requirement of an entry
function wt.DescribeReqs(entry)
    local svc, group, ctx = entry.svc, entry.group, wt.ctx or wt.NewContext()
    local list = {}
    if (svc.level or 0) > 1 then
        tinsert(list, { text = format(L.LEVEL_FORMAT, svc.level), ok = effectiveLevel(group, ctx) >= svc.level })
    end
    if svc.skill and svc.skillRank then
        local rank = skillRank(svc.skill, group, ctx)
        tinsert(list, {
            text = format(L.REQUIRES_SKILL_FORMAT, svc.skill, svc.skillRank),
            ok = rank ~= nil and rank >= svc.skillRank,
        })
    end
    if svc.reqs then
        for _, name in ipairs(svc.reqs) do
            tinsert(list, { text = name, ok = hasAbility(name) })
        end
    end
    return list
end

function wt.AllRanks(entry)
    local keys = {}
    for key, svc in pairs(entry.group.services) do
        if svc.name == entry.name then tinsert(keys, key) end
    end
    return keys
end

function wt.SetIgnored(keys, ignored)
    for _, key in ipairs(keys) do
        wt.char.ignored[key] = ignored or nil
    end
    wt.Rebuild()
end

function wt.ClassGroupKey()
    return "class:" .. wt.player.class
end

-- Views of the spellbook panel; professions live in the profession window instead.
function wt.BookViews()
    local views = { { key = wt.ClassGroupKey(), label = format(L.VIEW_CLASS_FORMAT, wt.player.className) } }
    local weapon = wt.results["weapon"]
    if weapon and weapon.total > 0 then tinsert(views, { key = "weapon", label = L.VIEW_WEAPON }) end
    local petKey = "pet:" .. wt.player.class
    if wt.results[petKey] and wt.results[petKey].total > 0 then tinsert(views, { key = petKey, label = L.VIEW_PET }) end
    return views
end

-- info: the profession window's professionInfo
function wt.FindProfessionGroup(info)
    if type(info) ~= "table" then return end
    for _, name in ipairs({ info.parentProfessionName or false, info.professionName or false }) do
        if name and wt.db.groups["prof:" .. name] then return "prof:" .. name, name end
    end
    for groupKey, group in pairs(wt.db.groups) do
        if group.kind == "prof" and group.skillID
            and (group.skillID == info.professionID or group.skillID == info.parentProfessionID) then
            return groupKey, group.name
        end
    end
    return nil, info.parentProfessionName or info.professionName
end

-- Professions with recorded data that this character has
function wt.KnownProfessionKeys()
    local keys = {}
    for groupKey, group in pairs(wt.db.groups) do
        if group.kind == "prof" and (wt.char.scanned[groupKey] or (wt.ctx and wt.ctx.skills[group.skill or ""])) then
            tinsert(keys, groupKey)
        end
    end
    sort(keys)
    return keys
end

function wt.Rebuild()
    if not wt.db then return end
    local ctx = wt.NewContext()
    wt.ctx = ctx
    wipe(wt.results)

    local ownSuffix = ":" .. wt.player.class
    for groupKey, group in pairs(wt.db.groups) do
        local shared = group.kind == "prof" or group.kind == "weapon"
        if shared or strsub(groupKey, -#ownSuffix) == ownSuffix then
            wt.results[groupKey] = wt.BuildGroup(groupKey, ctx)
        end
    end
    local classKey = wt.ClassGroupKey()
    wt.results[classKey] = wt.results[classKey] or wt.BuildGroup(classKey, ctx)

    if wt.RefreshUI then wt.RefreshUI() end
    if wt.UpdateBroker then wt.UpdateBroker() end
end
