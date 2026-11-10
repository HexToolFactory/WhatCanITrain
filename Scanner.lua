local _, wt = ...
local L = wt.L

-- Reads the open trainer window and records what it offers. Nothing about spells or
-- recipes is shipped with the addon; one visit per trainer type fills the lists.

local FILTERS = { "available", "unavailable", "used" }
local VALID_STATUS = { available = true, unavailable = true, used = true }

-- Weapon masters are ordinary trainers; their services are told apart by spell.
local WEAPON_SPELLS = {
    [196] = true, [197] = true, [198] = true, [199] = true, [200] = true, [201] = true, [202] = true,
    [227] = true, [264] = true, [266] = true, [1180] = true, [2567] = true, [5009] = true, [5011] = true,
    [15590] = true,
}

local trainerOpen = false
local scanPending = false
local inScan = false
local sawSyncUpdate = false
-- TRAINER_UPDATE events caused by our own filter changes, when they arrive after the scan
local ownUpdates, ownUpdatesExpire = 0, 0

local function nonEmpty(text)
    if type(text) == "string" and text ~= "" then return text end
end

local function serviceRef(index)
    if not (C_TooltipInfo and C_TooltipInfo.GetTrainerService) then return end
    local data = wt.try(C_TooltipInfo.GetTrainerService, index)
    local types = Enum and Enum.TooltipDataType
    if type(data) ~= "table" or not types or type(data.id) ~= "number" or data.id <= 0 then return end
    if data.type == types.Spell then return "spell", data.id end
    if data.type == types.Item then return "item", data.id end
end

local function makeKey(refType, id, name, sub)
    if refType then return (refType == "spell" and "s" or "i") .. id end
    return "n:" .. name .. ":" .. (sub or "")
end

-- Saved-data key of the service at this index of the open trainer window
function wt.TrainerServiceKey(index)
    local name, _, _, _, subText = wt.try(GetTrainerServiceInfo, index)
    if not nonEmpty(name) then return end
    local refType, id = serviceRef(index)
    return makeKey(refType, id, name, nonEmpty(subText))
end

local function readServices()
    local list = {}
    for index = 1, (wt.try(GetNumTrainerServices) or 0) do
        local name, status, icon, reqLevel, subText, category = wt.try(GetTrainerServiceInfo, index)
        if nonEmpty(name) and VALID_STATUS[status] then
            local skill, skillRank = wt.try(GetTrainerServiceSkillReq, index)
            local reqs
            for r = 1, (wt.try(GetTrainerServiceNumAbilityReq, index) or 0) do
                local ability, has = wt.try(GetTrainerServiceAbilityReq, index, r)
                if nonEmpty(ability) then
                    reqs = reqs or {}
                    tinsert(reqs, { name = ability, has = has and true or false })
                end
            end
            local refType, id = serviceRef(index)
            tinsert(list, {
                name = name,
                status = status,
                icon = icon,
                level = tonumber(reqLevel) or 0,
                sub = nonEmpty(subText),
                cat = nonEmpty(category),
                cost = tonumber((wt.try(GetTrainerServiceCost, index))) or 0,
                skill = nonEmpty(skill),
                skillRank = tonumber(skillRank),
                reqs = reqs,
                t = refType,
                id = id,
                line = nonEmpty((wt.try(GetTrainerServiceSkillLine, index))),
            })
        end
    end
    return list
end

local function trainerKind()
    local trainerType = C_Trainer and wt.try(C_Trainer.GetTrainerType)
    local types = Enum and Enum.TrainerType
    if types and trainerType == types.Pet then return "pet" end
    if (types and trainerType == types.Tradeskills) or wt.try(IsTradeskillTrainer) then return "prof" end
    return "general"
end

-- The profession most services of this trainer belong to, for services that name none.
local function commonSkill(list)
    local counts, best, bestCount = {}, nil, 0
    for _, s in ipairs(list) do
        local name = s.line or s.skill
        if name then
            counts[name] = (counts[name] or 0) + 1
            if counts[name] > bestCount then best, bestCount = name, counts[name] end
        end
    end
    return best
end

local function store(list)
    local db, char, player = wt.db, wt.char, wt.player
    if not db or #list == 0 then return end

    local kind = trainerKind()
    local npc = UnitName("npc") or UNKNOWN or "?"
    local build = select(2, GetBuildInfo())
    local fallbackSkill = kind == "prof" and commonSkill(list) or nil
    local added, touched, touchedNames = 0, {}, {}

    for _, s in ipairs(list) do
        local groupKey, groupKind, groupName, skillName
        if kind == "pet" then
            groupKey, groupKind, groupName = "pet:" .. player.class, "pet", L.VIEW_PET
        elseif kind == "prof" then
            skillName = s.line or s.skill or fallbackSkill or npc
            groupKey, groupKind, groupName = "prof:" .. skillName, "prof", skillName
        elseif s.t == "spell" and WEAPON_SPELLS[s.id] then
            groupKey, groupKind, groupName = "weapon", "weapon", L.VIEW_WEAPON
        else
            groupKey, groupKind, groupName = "class:" .. player.class, "class", player.className
        end

        local group = db.groups[groupKey]
        if not group then
            group = { kind = groupKind, name = groupName, services = {}, scopes = {} }
            db.groups[groupKey] = group
        end
        group.scopes = group.scopes or {}
        group.skill = skillName or group.skill
        group.trainer, group.time, group.build = npc, time(), build
        if not touched[groupKey] then
            touched[groupKey] = group
            tinsert(touchedNames, groupName)
        end

        local key = makeKey(s.t, s.id, s.name, s.sub)
        local svc = group.services[key]
        if not svc then
            svc = { seen = {} }
            group.services[key] = svc
            added = added + 1
        end
        svc.t, svc.id, svc.name, svc.sub, svc.icon, svc.cat = s.t, s.id, s.name, s.sub, s.icon, s.cat
        svc.level, svc.cost, svc.skill, svc.skillRank = s.level, s.cost, s.skill, s.skillRank
        svc.reqs = nil
        if s.reqs then
            svc.reqs = {}
            for _, req in ipairs(s.reqs) do
                tinsert(svc.reqs, req.name)
                char.reqHas[req.name] = req.has
            end
        end
        svc.seen = svc.seen or {}
        for _, scope in ipairs(player.scopes) do
            svc.seen[scope] = true
            group.scopes[scope] = true
        end

        char.known[key] = (s.status == "used") or nil
        char.scanned[groupKey] = true
        s.key, s.group = key, group
    end

    -- Remember the skill line id so the rank can be read while the skill list is collapsed.
    local skills = wt.GetSkills()
    for _, group in pairs(touched) do
        if group.skill and skills[group.skill] then group.skillID = skills[group.skill].id end
    end

    -- A service the trainer greys out although level, skill and abilities look fine has a
    -- requirement that cannot be read; keep that verdict until the next visit.
    local ctx = wt.NewContext()
    for _, s in ipairs(list) do
        local blocked = false
        if s.status == "unavailable" then
            blocked = wt.ComputeStatus(s.group.services[s.key], s.key, s.group, ctx, true) == "available"
        end
        char.blocked[s.key] = blocked or nil
    end

    if added > 0 then
        wt.Print(format(L.SCAN_NEW_FORMAT, added, npc, table.concat(touchedNames, ", ")))
    end
    wt.Rebuild()
end

local function doScan()
    scanPending = false
    if not trainerOpen or inScan or not wt.db then return end

    local getFilter, setFilter = GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter
    local restore, calls = {}, 0
    inScan, sawSyncUpdate = true, false

    local ok, err = pcall(function()
        -- Show every service for the duration of the read, then put the player's filters back.
        if getFilter and setFilter then
            for _, filter in ipairs(FILTERS) do
                if not getFilter(filter) then
                    setFilter(filter, true)
                    calls = calls + 1
                    -- only undo what verifiably took effect
                    if getFilter(filter) then tinsert(restore, filter) end
                end
            end
        end
        local list = readServices()
        while #restore > 0 do
            setFilter(tremove(restore), false)
            calls = calls + 1
        end
        store(list)
    end)

    for _, filter in ipairs(restore) do pcall(setFilter, filter, false) end
    inScan = false
    if calls > 0 and not sawSyncUpdate then
        ownUpdates, ownUpdatesExpire = calls, GetTime() + 0.5
    else
        ownUpdates = 0
    end
    if not ok then geterrorhandler()(err) end
end

local function requestScan()
    if scanPending then return end
    scanPending = true
    C_Timer.After(0.1, doScan)
end

local function onTrainerUpdate()
    if inScan then
        sawSyncUpdate = true
        return
    end
    if ownUpdates > 0 then
        if GetTime() < ownUpdatesExpire then
            ownUpdates = ownUpdates - 1
            return
        end
        ownUpdates = 0
    end
    if not trainerOpen and ClassTrainerFrame and ClassTrainerFrame:IsShown() then trainerOpen = true end
    requestScan()
end

wt.On("TRAINER_SHOW", function()
    trainerOpen = true
    requestScan()
end)
wt.On("TRAINER_CLOSED", function() trainerOpen = false end)
wt.On("TRAINER_UPDATE", onTrainerUpdate)
wt.On("TRAINER_SERVICE_INFO_NAME_UPDATE", onTrainerUpdate)
