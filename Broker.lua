local addonName, wt = ...
local L = wt.L
local ldb = LibStub:GetLibrary("LibDataBroker-1.1", true)
if not ldb then return end

local MAX_LINES = 10
local title = "What Can I Train?"

local plugin = ldb:NewDataObject(addonName, {
    type = "data source",
    text = title,
    icon = wt.ICON,
    OnClick = function() wt.Open() end,
})

local function addCategory(tt, category, header, r, g, b)
    if #category.entries == 0 then return end
    tt:AddLine(format("%s (%d)", header, #category.entries), r, g, b)
    for i, entry in ipairs(category.entries) do
        if i > MAX_LINES then
            tt:AddLine("  " .. format(L.BROKER_HIDDEN_FORMAT, #category.entries - MAX_LINES), 0.6, 0.6, 0.6)
            break
        end
        local right = entry.status == "available" and wt.CostText(entry) or entry.reqText
        tt:AddDoubleLine("  " .. entry.fullName, right, 1, 1, 1, 0.8, 0.8, 0.8)
    end
    tt:AddLine(" ")
end

function plugin.OnTooltipShow(tt)
    tt:AddLine(L.TAB_TEXT)
    tt:AddLine(" ")
    if not wt.db then return end

    local result = wt.results[wt.ClassGroupKey()]
    if not result or result.total == 0 then
        tt:AddLine(L.BROKER_NO_DATA, 1, 1, 1)
        tt:AddLine(L.NO_DATA_CLASS, 0.8, 0.8, 0.8, true)
    elseif #result.byStatus.available.entries == 0 and #result.byStatus.soon.entries == 0 then
        tt:AddLine(L.BROKER_NOTHING, 1, 1, 1)
    else
        addCategory(tt, result.byStatus.available, L.AVAILABLE_HEADER, 0.1, 1, 0.1)
        addCategory(tt, result.byStatus.soon, L.NEXTLEVEL_HEADER, 0.51, 0.77, 1)
    end

    for _, groupKey in ipairs(wt.KnownProfessionKeys()) do
        local profession = wt.results[groupKey]
        if profession then
            tt:AddLine(format(L.BROKER_VIEW_FORMAT, profession.group.name or groupKey,
                #profession.byStatus.available.entries), 1, 0.82, 0)
        end
    end
    tt:AddLine(" ")
    tt:AddLine(L.BROKER_CLICK_OPEN, 0.1, 1, 0.1)
end

function wt.UpdateBroker()
    local result = wt.results[wt.ClassGroupKey()]
    local available = result and #result.byStatus.available.entries or 0
    local soon = result and #result.byStatus.soon.entries or 0
    if available > 0 then
        plugin.text = format("|cff19ff19%d|r %s", available, L.AVAILABLE_HEADER)
    elseif soon > 0 then
        plugin.text = format("|cff82c5ff%d|r %s", soon, L.NEXTLEVEL_HEADER)
    else
        plugin.text = title
    end
end
