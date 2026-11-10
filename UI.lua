local _, wt = ...
local L = wt.L

-- Two panels share one list widget:
--   * a book tab in the spellbook's icon row -> class, weapon and pet training
--   * a book button in the profession window -> that profession's training
-- Both only add our own frames on top of Blizzard's; nothing of theirs is modified, so
-- the spell buttons underneath stay untainted.

local function fontName(name, fallback)
    return _G[name] and name or fallback
end

local bookText = { 0.20, 0.12, 0.06 }
if SPELLBOOK_FONT_COLOR and SPELLBOOK_FONT_COLOR.GetRGB then
    bookText = { SPELLBOOK_FONT_COLOR:GetRGB() }
end

local THEMES = {
    -- dark ink on the spellbook's parchment
    book = {
        rowHeight = 24,
        iconSize = 20,
        nameFont = fontName("SystemFont_Med3", "GameFontHighlight"),
        smallFont = fontName("SystemFont_Med1", "GameFontHighlightSmall"),
        headerFont = fontName("SystemFont_Large", "GameFontHighlightLarge"),
        text = bookText,
        sub = { 0.38, 0.28, 0.18 },
        dim = { 0.47, 0.40, 0.32 },
        bad = { 0.62, 0.08, 0.05 },
        line = { 0.25, 0.15, 0.05, 0.45 },
        highlight = { 0.35, 0.20, 0.05, 0.14 },
        status = {
            available = { 0.08, 0.38, 0.08 },
            missingReqs = { 0.62, 0.30, 0.00 },
            soon = { 0.10, 0.25, 0.55 },
            later = { 0.50, 0.10, 0.10 },
            ignored = { 0.42, 0.36, 0.12 },
            known = { 0.40, 0.34, 0.28 },
        },
    },
    -- light text on the profession window's dark pane
    dark = {
        rowHeight = 20,
        iconSize = 16,
        nameFont = "GameFontHighlight",
        smallFont = "GameFontHighlightSmall",
        headerFont = "GameFontNormal",
        text = { 1.00, 0.82, 0.00 },
        sub = { 0.85, 0.85, 0.85 },
        dim = { 0.50, 0.50, 0.50 },
        bad = { 1.00, 0.25, 0.25 },
        line = { 1, 1, 1, 0.15 },
        highlight = { 1, 1, 1, 0.10 },
        status = {
            available = { 0.10, 1.00, 0.10 },
            missingReqs = { 1.00, 0.50, 0.25 },
            soon = { 0.51, 0.77, 1.00 },
            later = { 1.00, 0.35, 0.35 },
            ignored = { 1.00, 1.00, 0.60 },
            known = { 0.55, 0.55, 0.55 },
        },
    },
}

-- Rows -----------------------------------------------------------------------

local function showTooltip(row)
    local data = row.data
    if not data then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if data.isHeader then
        GameTooltip:SetText(data.text, 1, 1, 1)
        if (data.cost or 0) > 0 then
            GameTooltip:AddLine(format(data.costFormat, wt.CostText(data)), 1, 1, 1)
        end
    else
        local svc = data.svc
        if svc.id and svc.t == "spell" then
            pcall(GameTooltip.SetSpellByID, GameTooltip, svc.id)
        elseif svc.id and svc.t == "item" then
            pcall(GameTooltip.SetItemByID, GameTooltip, svc.id)
        end
        if GameTooltip:NumLines() == 0 then GameTooltip:SetText(data.fullName, 1, 1, 1) end
        GameTooltip:AddLine(" ")
        if data.cost > 0 and data.status ~= "known" then
            local canAfford = data.group.kind == "pet" or (wt.ctx and wt.ctx.money or 0) >= data.cost
            local r, g, b = 1, 1, 1
            if not canAfford then r, g, b = 1, 0.25, 0.25 end
            GameTooltip:AddLine(format(L.COST_FORMAT, wt.CostText(data)), r, g, b)
        end
        if data.status ~= "known" then
            for _, req in ipairs(wt.DescribeReqs(data)) do
                if req.ok then
                    GameTooltip:AddLine(format(L.REQUIRES_FORMAT, req.text), 0.6, 0.6, 0.6)
                else
                    GameTooltip:AddLine(format(L.REQUIRES_FORMAT, req.text), 1, 0.25, 0.25)
                end
            end
            if wt.char.blocked[data.key] then
                GameTooltip:AddLine(L.REQUIRES_UNKNOWN, 1, 0.5, 0.25, true)
            end
        end
        if svc.cat then GameTooltip:AddLine(svc.cat, 0.6, 0.6, 0.6) end
    end
    GameTooltip:Show()
end

local function linkFor(svc)
    if not svc.id then return end
    if svc.t == "spell" and C_Spell and C_Spell.GetSpellLink then
        return (wt.try(C_Spell.GetSpellLink, svc.id))
    elseif svc.t == "item" and C_Item and C_Item.GetItemInfo then
        local _, link = wt.try(C_Item.GetItemInfo, svc.id)
        return link
    end
end

local function insertLink(link)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        if not ChatFrameUtil.InsertLink(link) and ChatFrameUtil.OpenChat then ChatFrameUtil.OpenChat(link) end
    elseif ChatEdit_InsertLink then
        if not ChatEdit_InsertLink(link) and ChatFrame_OpenChat then ChatFrame_OpenChat(link) end
    end
end

local function showContextMenu(row, data)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        wt.SetIgnored({ data.key }, not wt.char.ignored[data.key])
        return
    end
    MenuUtil.CreateContextMenu(row, function(_, root)
        root:CreateTitle(data.fullName)
        root:CreateCheckbox(L.IGNORED_TT, function() return wt.char.ignored[data.key] == true end, function()
            wt.SetIgnored({ data.key }, not wt.char.ignored[data.key])
        end)
        local ranks = wt.AllRanks(data)
        if #ranks > 1 then
            local function allIgnored()
                for _, key in ipairs(ranks) do
                    if not wt.char.ignored[key] then return false end
                end
                return true
            end
            root:CreateCheckbox(L.IGNORE_ALL_TT, allIgnored, function()
                wt.SetIgnored(ranks, not allIgnored())
            end)
        end
    end)
end

-- Checks or unchecks one entry; with Ctrl held, every rank of that spell at once.
local function setWanted(data, wanted)
    local keys = IsControlKeyDown() and wt.AllRanks(data) or { data.key }
    wt.SetIgnored(keys, not wanted)
end

local function onRowClick(row, button)
    local data = row.data
    if not data or data.isHeader then return end
    if button == "LeftButton" and IsControlKeyDown() then
        if data.status ~= "known" then setWanted(data, data.status == "ignored") end
    elseif button == "LeftButton" and IsShiftKeyDown() then
        local link = linkFor(data.svc)
        if link then insertLink(link) end
    elseif button == "RightButton" then
        showContextMenu(row, data)
    end
end

local function buildRow(row, theme)
    row.wtBuilt = true
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(unpack(theme.highlight))

    -- checked = on the shopping list; unchecked moves the entry to "Not Buying Now"
    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.check:SetSize(theme.iconSize + 4, theme.iconSize + 4)
    row.check:SetPoint("LEFT", 0, 0)
    row.check:SetScript("OnClick", function(self)
        local data = row.data
        if data and not data.isHeader then setWanted(data, self:GetChecked()) end
    end)
    row.check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.WANTED_TT, 1, 1, 1)
        GameTooltip:AddLine(L.WANTED_TT_ON, 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(L.WANTED_TT_OFF, 0.6, 0.6, 0.6, true)
        GameTooltip:AddLine(L.WANTED_TT_CTRL, 0.1, 1, 0.1, true)
        GameTooltip:Show()
    end)
    row.check:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(theme.iconSize, theme.iconSize)
    row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    row.right = row:CreateFontString(nil, "ARTWORK", theme.smallFont)
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")

    row.name = row:CreateFontString(nil, "ARTWORK", theme.nameFont)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.sub = row:CreateFontString(nil, "ARTWORK", theme.smallFont)
    row.sub:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.sub:SetPoint("RIGHT", row.right, "LEFT", -6, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)

    row.header = row:CreateFontString(nil, "ARTWORK", theme.headerFont)
    row.header:SetPoint("LEFT", 2, -1)
    row.header:SetJustifyH("LEFT")

    row.line = row:CreateTexture(nil, "ARTWORK")
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", 0, 1)
    row.line:SetPoint("BOTTOMRIGHT", 0, 1)
    row.line:SetColorTexture(unpack(theme.line))

    for _, fontString in ipairs({ row.right, row.name, row.sub, row.header }) do
        fontString:SetShadowOffset(0, 0)
    end

    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", onRowClick)
end

local function initRow(row, data, theme)
    if not row.wtBuilt then buildRow(row, theme) end
    row.data = data
    local statusColor = theme.status[data.status] or theme.text

    if data.isHeader then
        row.check:Hide()
        row.icon:Hide()
        row.name:Hide()
        row.sub:Hide()
        row.header:Show()
        row.line:Show()
        row.header:SetText(format("%s (%d)", data.text, data.count))
        row.header:SetTextColor(unpack(statusColor))
        row.right:SetText((data.cost or 0) > 0 and wt.CostText(data) or "")
        row.right:SetTextColor(unpack(theme.sub))
    else
        local faded = data.status == "known" or data.status == "ignored"
        row.header:Hide()
        row.line:Hide()
        -- known entries keep the space so the icons stay in one column
        row.check:SetShown(data.status ~= "known")
        row.check:SetChecked(data.status ~= "ignored")
        row.icon:Show()
        row.name:Show()
        row.sub:Show()
        row.icon:SetTexture(data.svc.icon or wt.ICON)
        row.icon:SetDesaturated(faded)
        row.name:SetText(data.name)
        row.name:SetTextColor(unpack(faded and theme.dim or theme.text))
        row.sub:SetText(data.sub and format("(%s)", data.sub) or "")
        row.sub:SetTextColor(unpack(faded and theme.dim or theme.sub))

        if data.status == "available" or data.status == "missingReqs" then
            local canAfford = data.group.kind == "pet" or (wt.ctx and wt.ctx.money or 0) >= data.cost
            row.right:SetText(data.cost > 0 and wt.CostText(data) or "")
            row.right:SetTextColor(unpack(canAfford and theme.sub or theme.bad))
        elseif data.status == "soon" or data.status == "later" then
            row.right:SetText(data.reqText)
            row.right:SetTextColor(unpack(statusColor))
        elseif data.status == "ignored" then
            row.right:SetText(data.cost > 0 and wt.CostText(data) or "")
            row.right:SetTextColor(unpack(theme.dim))
        else
            row.right:SetText("")
        end
    end

    if GameTooltip:IsOwned(row) then showTooltip(row) end
end

-- List widget ----------------------------------------------------------------

local function createList(parent, theme)
    local list = {}
    local scrollBox = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(theme.rowHeight)
    view:SetElementInitializer("Button", function(row, data) initRow(row, data, theme) end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    list.scrollBox = scrollBox
    function list:SetRows(rows)
        scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    end
    return list
end

local function createSearchBox(parent, name, onChanged)
    local box = CreateFrame("EditBox", name, parent, "SearchBoxTemplate")
    box:SetAutoFocus(false)
    box:HookScript("OnTextChanged", function(self)
        onChanged(strlower(strtrim(self:GetText() or "")))
    end)
    return box
end

local function createBadge(button)
    local badge = button:CreateFontString(nil, "OVERLAY", fontName("NumberFontNormalSmall", "GameFontNormalSmall"))
    badge:SetPoint("BOTTOMRIGHT", -2, 2)
    badge:SetTextColor(0.1, 1, 0.1)
    return badge
end

local function availableCount(groupKey)
    local result = groupKey and wt.results[groupKey]
    return result and #result.byStatus.available.entries or 0
end

local function footerText(result, groupKey)
    local group = result and result.group
    if not group or result.total == 0 then return "" end
    local text = format(L.STATUS_SCANNED_FORMAT, result.total, group.trainer or "?",
        group.time and date("%Y-%m-%d", group.time) or "?")
    if not wt.char.scanned[groupKey] then text = text .. "\n" .. L.STATUS_OTHER_CHARACTER end
    return text
end

-- Fills list, empty-state text and footer of a panel from one group's result.
local function fillPanel(panel, groupKey, filter, noDataText)
    local result = groupKey and (wt.results[groupKey] or wt.BuildGroup(groupKey, wt.ctx))
    local rows = result and wt.Rows(result, filter) or {}
    panel.list:SetRows(rows)
    if not result or result.total == 0 then
        panel.empty:SetText(L.NO_DATA_TITLE .. "\n\n" .. noDataText)
        panel.empty:Show()
    elseif #rows == 0 then
        panel.empty:SetText(L.SEARCH_NO_RESULTS)
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
    panel.footer:SetText(footerText(result, groupKey))
end

-- Spellbook ------------------------------------------------------------------

local TOP_OFFSET = 60      -- the parchment starts this far below the top of SpellBookFrame (below the tab row)
local PAGE_LEFT = 85
local PAGE_RIGHT = 30      -- keeps the list and its scroll bar off the parchment's right edge
local PAGE_WIDTH = 660     -- at most; the book's width differs between client builds

local book = { filter = "" }

local function bookRefresh()
    local panel = book.panel
    if not panel then return end
    local count = availableCount(wt.ClassGroupKey())
    book.tab.badge:SetText(count > 0 and count or "")
    if not panel:IsShown() then return end

    local views = wt.BookViews()
    local viewKey = views[1].key
    local signature = ""
    for _, view in ipairs(views) do
        if view.key == wt.char.view then viewKey = view.key end
        signature = signature .. view.key .. ";"
    end
    book.viewKey = viewKey
    panel.dropdown:SetShown(#views > 1)
    if signature ~= book.viewSignature then
        book.viewSignature = signature
        if panel.dropdown.GenerateMenu then panel.dropdown:GenerateMenu() end
    end

    local isClass = viewKey == wt.ClassGroupKey()
    fillPanel(panel, viewKey, book.filter, isClass and L.NO_DATA_CLASS or L.NO_DATA_OTHER)
end

local function setPageArt(texture, atlas)
    if C_Texture and C_Texture.GetAtlasInfo and wt.try(C_Texture.GetAtlasInfo, atlas) then
        texture:SetAtlas(atlas)
    else
        texture:SetColorTexture(0.62, 0.48, 0.30, 1)
    end
end

-- One page when the book is minimized, two when it is maximized (same as Blizzard's art).
local function bookLayoutArt()
    local panel = book.panel
    local width = panel:GetWidth() or 0
    local minimized = width < 1000
    panel.artSingle:SetShown(minimized)
    panel.artLeft:SetShown(not minimized)
    panel.artRight:SetShown(not minimized)
    -- the list stays on one page: the only page, or the left one of two
    local pageWidth = minimized and width or width / 2
    if pageWidth > 0 then
        panel.page:SetWidth(min(PAGE_WIDTH, pageWidth - PAGE_LEFT - PAGE_RIGHT))
    end
end

local function selectedBlizzardTab()
    local tabs = book.frame.CategoryTabSystem.tabs
    if type(tabs) ~= "table" then return end
    for _, tab in ipairs(tabs) do
        if tab.isSelected and tab:IsShown() then return tab end
    end
end

-- The selected Blizzard tab is disabled, so it cannot be clicked to get back. A dimmed
-- button of ours sits on top of it while the panel is open.
local function bookPlaceCatcher()
    local catcher = book.catcher
    local tab = book.panel:IsShown() and selectedBlizzardTab()
    if tab then
        catcher:ClearAllPoints()
        catcher:SetAllPoints(tab)
        catcher:SetFrameLevel(tab:GetFrameLevel() + 5)
        catcher:Show()
    else
        catcher:Hide()
    end
end

local function bookUpdateTab()
    local tab, shown = book.tab, book.panel:IsShown()
    tab.normal:SetShown(not shown)
    tab.active:SetShown(shown)
    tab.glow:SetShown(shown)
end

local function bookHide()
    if book.panel then book.panel:Hide() end
end

local function bookShow()
    local panel, frame = book.panel, book.frame
    if not panel or not frame:IsVisible() then return end
    book.shownForTab = frame.CategoryTabSystem.selectedTabID
    panel:SetFrameLevel(frame:GetFrameLevel() + 60)
    panel:Show()
end

local function createBookTab(frame, tabs)
    local tab = CreateFrame("Button", "WhatCanITrainTab", frame)
    tab:SetSize(44, 32)
    tab:SetPoint("BOTTOMLEFT", tabs, "BOTTOMRIGHT", 12, 0)
    tab:SetFrameLevel(tabs:GetFrameLevel() + 2)

    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(34, 32)
    icon:SetPoint("CENTER")
    icon:SetTexture(wt.ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- same art as the neighbouring category tabs
    tab.normal = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.normal:SetAtlas("spellbook-Tab-Frame-C60", true)
    tab.normal:SetPoint("BOTTOM", 0, 1)
    tab.active = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.active:SetAtlas("spellbook-Tab-Frame-Glow-C60", true)
    tab.active:SetPoint("BOTTOM", 0, 1)
    tab.glow = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.glow:SetAtlas("spellbook-Tab-Frame-glow-gradient-C60", true)
    tab.glow:SetPoint("BOTTOM", 0, 0)

    local highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints(icon)
    highlight:SetColorTexture(1, 1, 1, 0.15)

    tab.badge = createBadge(tab)

    tab:SetScript("OnClick", function()
        if book.panel:IsShown() then bookHide() else bookShow() end
        PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN or SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TAB_TEXT)
        local result = wt.results[wt.ClassGroupKey()]
        if result and result.total > 0 then
            local available = result.byStatus.available
            GameTooltip:AddLine(format("%s: %d", L.AVAILABLE_HEADER, #available.entries), 0.1, 1, 0.1)
            if available.cost > 0 then
                GameTooltip:AddLine(format(L.TOTALCOST_FORMAT, wt.CoinString(available.cost)), 1, 1, 1)
            end
            GameTooltip:AddLine(format("%s: %d", L.NEXTLEVEL_HEADER, #result.byStatus.soon.entries), 0.51, 0.77, 1)
        else
            GameTooltip:AddLine(L.NO_DATA_CLASS, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return tab
end

local function createBookPanel(frame)
    local theme = THEMES.book
    local panel = CreateFrame("Frame", "WhatCanITrainPanel", frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -TOP_OFFSET)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    panel:EnableMouse(true)             -- keeps clicks from reaching the spells underneath
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function() end)
    panel:Hide()

    -- The book art is drawn again at exactly Blizzard's position and size, so it lines up
    -- with theirs, and clipped to the panel so the tab row above stays untouched.
    local clip = CreateFrame("Frame", nil, panel)
    clip:SetAllPoints(panel)
    clip:SetClipsChildren(true)
    local art = CreateFrame("Frame", nil, clip)
    art:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    art:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    panel.artSingle = art:CreateTexture(nil, "BACKGROUND")
    panel.artSingle:SetAllPoints()
    panel.artLeft = art:CreateTexture(nil, "BACKGROUND")
    panel.artLeft:SetPoint("TOPLEFT")
    panel.artLeft:SetPoint("BOTTOMRIGHT", art, "BOTTOM")
    panel.artRight = art:CreateTexture(nil, "BACKGROUND")
    panel.artRight:SetPoint("TOPLEFT", art, "TOP")
    panel.artRight:SetPoint("BOTTOMRIGHT")
    setPageArt(panel.artSingle, "spellbook-Page-Right-C60")
    setPageArt(panel.artLeft, "spellbook-Page-Left-C60")
    setPageArt(panel.artRight, "spellbook-Page-Right-C60")

    -- everything lives on the left page, above the art
    local page = CreateFrame("Frame", nil, panel)
    page:SetFrameLevel(art:GetFrameLevel() + 2)
    page:SetPoint("TOPLEFT", panel, "TOPLEFT", PAGE_LEFT, -36)
    page:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PAGE_LEFT, 52)
    page:SetWidth(PAGE_WIDTH)
    panel.page = page

    local title = page:CreateFontString(nil, "ARTWORK", fontName("SystemFont_Huge2", "GameFontNormalHuge"))
    title:SetPoint("TOPLEFT", -8, 0)
    title:SetText(L.TAB_TEXT)
    title:SetTextColor(unpack(theme.text))
    title:SetShadowOffset(0, 0)

    local divider = page:CreateTexture(nil, "ARTWORK")
    divider:SetAtlas("spellbook-divider")
    divider:SetHeight(11)
    divider:SetPoint("TOPLEFT", page, "TOPLEFT", -32, -40)
    divider:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -40)

    local dropdown = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(190)
    dropdown:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -6)
    dropdown:SetupMenu(function(_, root)
        for _, view in ipairs(wt.BookViews()) do
            root:CreateRadio(view.label, function(key) return book.viewKey == key end, function(key)
                wt.char.view = key
                bookRefresh()
            end, view.key)
        end
    end)
    panel.dropdown = dropdown

    local search = createSearchBox(page, "WhatCanITrainSearchBox", function(text)
        if text ~= book.filter then
            book.filter = text
            bookRefresh()
        end
    end)
    search:SetSize(200, 22)
    search:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -58)

    panel.list = createList(page, theme)
    panel.list.scrollBox:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -88)
    panel.list.scrollBox:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, 34)

    panel.empty = page:CreateFontString(nil, "ARTWORK", theme.nameFont)
    panel.empty:SetPoint("TOPLEFT", page, "TOPLEFT", 40, -150)
    panel.empty:SetPoint("TOPRIGHT", page, "TOPRIGHT", -40, -150)
    panel.empty:SetTextColor(unpack(theme.sub))
    panel.empty:SetShadowOffset(0, 0)
    panel.empty:Hide()

    panel.footer = page:CreateFontString(nil, "ARTWORK", theme.smallFont)
    panel.footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 0, 0)
    panel.footer:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
    panel.footer:SetJustifyH("LEFT")
    panel.footer:SetTextColor(unpack(theme.dim))
    panel.footer:SetShadowOffset(0, 0)

    panel:SetScript("OnShow", function()
        bookLayoutArt()
        bookUpdateTab()
        bookPlaceCatcher()
        bookRefresh()
    end)
    panel:SetScript("OnHide", function()
        bookUpdateTab()
        book.catcher:Hide()
    end)
    panel:SetScript("OnSizeChanged", function(self)
        if self:IsShown() then bookLayoutArt() end
    end)
    return panel
end

local function setupBook()
    if book.panel then return true end
    local frame = PlayerSpellsFrame and PlayerSpellsFrame.SpellBookFrame
    local tabs = frame and frame.CategoryTabSystem
    if not tabs then return false end

    book.frame = frame
    book.catcher = CreateFrame("Button", nil, frame)
    book.catcher:Hide()
    -- the tab's button can be much wider than its icon, so only the icon is dimmed
    local dim = book.catcher:CreateTexture(nil, "OVERLAY")
    dim:SetSize(38, 34)
    dim:SetPoint("BOTTOM", 0, 0)
    dim:SetColorTexture(0, 0, 0, 0.45)
    book.catcher:SetScript("OnClick", bookHide)

    book.tab = createBookTab(frame, tabs)
    book.panel = createBookPanel(frame)
    bookUpdateTab()

    -- Another category was chosen (or the tabs were rebuilt after a spell change).
    if type(tabs.SetTabVisuallySelected) == "function" then
        hooksecurefunc(tabs, "SetTabVisuallySelected", function(_, tabID)
            if not book.panel:IsShown() then return end
            if tabID ~= book.shownForTab then bookHide() else bookPlaceCatcher() end
        end)
    end
    if frame.SearchBox then
        frame.SearchBox:HookScript("OnEditFocusGained", bookHide)
    end
    frame:HookScript("OnHide", bookHide)
    frame:HookScript("OnShow", function()
        if book.pendingShow then
            book.pendingShow = nil
            C_Timer.After(0, bookShow)
        end
    end)

    bookRefresh()
    if book.pendingShow and frame:IsVisible() then
        book.pendingShow = nil
        bookShow()
    end
    return true
end

-- Profession window ----------------------------------------------------------

local prof = { filter = "" }

local function profCurrent()
    local info = Professions and wt.try(Professions.GetProfessionInfo) or prof.info
    return wt.FindProfessionGroup(info)
end

local function profRefresh()
    local panel = prof.panel
    if not panel then return end
    local groupKey, name = profCurrent()
    local count = availableCount(groupKey)
    prof.button.badge:SetText(count > 0 and count or "")
    if not panel:IsShown() then return end

    panel.title:SetText(name and format("%s - %s", L.TAB_TEXT, name) or L.TAB_TEXT)
    fillPanel(panel, groupKey, prof.filter, L.NO_DATA_OTHER)
end

local function setupProfessions()
    if prof.panel then return true end
    local frame = ProfessionsFrame
    local page = frame and frame.CraftingPage
    local form = page and page.SchematicForm
    if not form then return false end
    local theme = THEMES.dark

    local button = CreateFrame("Button", "WhatCanITrainProfessionButton", page)
    button:SetSize(30, 30)
    button:SetPoint("CENTER", frame, "TOPRIGHT", -37, -53)
    button:SetFrameLevel(page:GetFrameLevel() + 20)
    local border = button:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 0.9)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(wt.ICON)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.2)
    button.badge = createBadge(button)
    prof.button = button

    local panel = CreateFrame("Frame", "WhatCanITrainProfessionPanel", page)
    panel:SetPoint("TOPLEFT", form, "TOPLEFT", 0, 0)
    panel:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -6, 34)
    panel:EnableMouse(true)
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function() end)
    panel:Hide()
    local background = panel:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.06, 0.05, 0.04, 1)
    prof.panel = panel

    panel.title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    panel.title:SetPoint("TOPLEFT", 12, -12)
    panel.title:SetPoint("TOPRIGHT", -12, -12)
    panel.title:SetJustifyH("LEFT")
    panel.title:SetWordWrap(false)

    local search = createSearchBox(panel, "WhatCanITrainProfessionSearchBox", function(text)
        if text ~= prof.filter then
            prof.filter = text
            profRefresh()
        end
    end)
    search:SetHeight(22)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 18, -36)
    search:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -14, -36)

    panel.list = createList(panel, theme)
    panel.list.scrollBox:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -64)
    panel.list.scrollBox:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 40)

    panel.empty = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.empty:SetPoint("TOPLEFT", 24, -110)
    panel.empty:SetPoint("TOPRIGHT", -24, -110)
    panel.empty:Hide()

    panel.footer = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    panel.footer:SetPoint("BOTTOMLEFT", 12, 8)
    panel.footer:SetPoint("BOTTOMRIGHT", -12, 8)
    panel.footer:SetJustifyH("LEFT")

    panel:SetScript("OnShow", function(self)
        self:SetFrameLevel(form:GetFrameLevel() + 60)
        profRefresh()
    end)

    button:SetScript("OnClick", function()
        panel:SetShown(not panel:IsShown())
        PlaySound(SOUNDKIT.U_CHAT_SCROLL_BUTTON)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TAB_TEXT)
        local groupKey = profCurrent()
        local result = groupKey and wt.results[groupKey]
        if result and result.total > 0 then
            GameTooltip:AddLine(format("%s: %d", L.AVAILABLE_HEADER, #result.byStatus.available.entries), 0.1, 1, 0.1)
            GameTooltip:AddLine(format("%s: %d", L.NEXTLEVEL_HEADER, #result.byStatus.soon.entries), 0.51, 0.77, 1)
        else
            GameTooltip:AddLine(L.NO_DATA_OTHER, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    page:HookScript("OnHide", function() panel:Hide() end)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("Professions.ProfessionSelected", function(_, info)
            prof.info = info
            profRefresh()
        end, prof)
        -- picking a recipe means the player wants to see it, not our list
        EventRegistry:RegisterCallback("Professions.RecipeSelected", function() panel:Hide() end, prof)
    end

    profRefresh()
    return true
end

-- Entry points ---------------------------------------------------------------

function wt.RefreshUI()
    bookRefresh()
    profRefresh()
    if wt.RefreshTrainerButton then wt.RefreshTrainerButton() end
end

-- Opening the spellbook from addon code would taint its spell buttons, so the list is
-- only armed here and appears the next time the player opens the book.
function wt.Open()
    if book.panel and book.frame:IsVisible() then
        bookShow()
        return
    end
    book.pendingShow = true
    wt.Print(L.OPEN_SPELLBOOK)
end

local function attach(addon, setup)
    local function run()
        local ok, result = pcall(setup)
        if not ok then
            geterrorhandler()(result)
        elseif not result then
            wt.Print(format(L.LOAD_FAILED, addon))
        end
    end
    if EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded(addon, run)
    else
        wt.On("ADDON_LOADED", function(name)
            if name == addon then run() end
        end)
    end
end

function wt.SetupUI()
    attach("Blizzard_PlayerSpells", setupBook)
    attach("Blizzard_Professions", setupProfessions)
    if wt.SetupTrainer then wt.SetupTrainer(attach) end
end

-- Trainer window -------------------------------------------------------------

do

-- "Buy All" button in the trainer window: learns every service the trainer offers right
-- now that is still checked in the What can I train? list. Unchecked entries are skipped,
-- new professions too (those need Blizzard's own confirmation dialog).

local button

local function isPetTrainer()
    local types = Enum and Enum.TrainerType
    return types and C_Trainer and wt.try(C_Trainer.GetTrainerType) == types.Pet
end

local function budget(pet)
    if pet then
        local total, used = wt.try(C_PetInfo and C_PetInfo.GetPetTrainingPoints)
        return math.max((total or 0) - (used or 0), 0)
    end
    return GetMoney and GetMoney() or 0
end

-- What one click would buy, plus what is left out and why
local function plan()
    local result = { buy = {}, cost = 0, skipped = 0, poor = 0, newProf = 0 }
    if not wt.char then return result end
    local pet = isPetTrainer()
    result.pet = pet
    local left = budget(pet)
    for index = 1, (wt.try(GetNumTrainerServices) or 0) do
        local _, status = wt.try(GetTrainerServiceInfo, index)
        if status == "available" then
            local key = wt.TrainerServiceKey(index)
            local cost, isProfession = wt.try(GetTrainerServiceCost, index)
            cost = tonumber(cost) or 0
            if key and wt.char.ignored[key] then
                result.skipped = result.skipped + 1
            elseif isProfession then
                result.newProf = result.newProf + 1
            elseif cost > left then
                result.poor = result.poor + 1
            else
                left = left - cost
                result.cost = result.cost + cost
                tinsert(result.buy, index)
            end
        end
    end
    return result
end

local function costText(amount, pet)
    if pet then return format(L.TRAINING_POINTS_FORMAT, amount) end
    return wt.CoinString(amount)
end

function wt.RefreshTrainerButton()
    if not button or not button:IsVisible() then return end
    button:SetEnabled(#plan().buy > 0)
    if GameTooltip:IsOwned(button) then button:GetScript("OnEnter")(button) end
end

local function onClick()
    local p = plan()
    if #p.buy == 0 then return end
    -- indices stay valid until the trainer sends its update, which comes after this frame
    for _, index in ipairs(p.buy) do
        BuyTrainerService(index)
    end
    wt.Print(format(L.BUY_DONE_FORMAT, #p.buy, costText(p.cost, p.pet)))
    PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN or SOUNDKIT.U_CHAT_SCROLL_BUTTON)
end

local function onEnter(self)
    local p = plan()
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L.BUY_ALL, 1, 1, 1)
    if #p.buy > 0 then
        GameTooltip:AddLine(format(L.BUY_ALL_TT_FORMAT, #p.buy), 0.1, 1, 0.1, true)
        GameTooltip:AddLine(format(L.TOTALCOST_FORMAT, costText(p.cost, p.pet)), 1, 1, 1)
    else
        GameTooltip:AddLine(L.BUY_ALL_NONE, 1, 1, 1, true)
    end
    if p.skipped > 0 then GameTooltip:AddLine(format(L.BUY_ALL_SKIPPED_FORMAT, p.skipped), 0.6, 0.6, 0.6, true) end
    if p.poor > 0 then GameTooltip:AddLine(format(L.BUY_ALL_POOR_FORMAT, p.poor), 1, 0.25, 0.25, true) end
    if p.newProf > 0 then GameTooltip:AddLine(L.BUY_ALL_NEW_PROF, 0.6, 0.6, 0.6, true) end
    GameTooltip:AddLine(L.BUY_ALL_RANKS, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function setup()
    local frame = ClassTrainerFrame
    local train = frame and (frame.TrainButton or ClassTrainerTrainButton)
    if not train then return false end

    button = CreateFrame("Button", "WhatCanITrainBuyAllButton", frame, "UIPanelButtonTemplate")
    button:SetSize(90, train:GetHeight() > 0 and train:GetHeight() or 22)
    button:SetPoint("RIGHT", train, "LEFT", 0, 0)
    button:SetText(L.BUY_ALL)
    button:SetMotionScriptsWhileDisabled(true)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", onEnter)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnShow", wt.RefreshTrainerButton)
    button:SetEnabled(false)
    wt.RefreshTrainerButton()
    return true
end

local function refreshSoon()
    -- the trainer's lists settle a moment after the event
    C_Timer.After(0.15, wt.RefreshTrainerButton)
end
for _, event in ipairs({ "TRAINER_SHOW", "TRAINER_UPDATE", "PLAYER_MONEY", "UNIT_PET_TRAINING_POINTS" }) do
    wt.On(event, refreshSoon)
end

function wt.SetupTrainer(attach)
    attach("Blizzard_TrainerUI", setup)
end
end
