-- Slot Filler: visual style.
-- When EllesmereUI is installed the window registers with its public skinning
-- API (EllesmereUI/SKINNING_API.md) and is painted by EllesmereUI itself, so it
-- follows the user's window style, accent colour and font like any of its own
-- modules. Without EllesmereUI (or with third-party skinning turned off) the
-- same flat look is painted here with fixed colours.
local _, ns = ...

local Style = {}
ns.Style = Style

-- Fallback palette: the EllesmereUI window-skin defaults.
local ACCENT   = { 12 / 255, 210 / 255, 157 / 255 }
local BG       = { 0.08, 0.08, 0.08, 0.92 }
local INSET    = { 0.04, 0.04, 0.04, 0.85 }
local BORDER   = { 0.20, 0.20, 0.20, 1 }
local TAB_BG   = { 0.068, 0.056, 0.052, 1 }
local BAR      = { 0, 0, 0, 0.5 }
local FONT     = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local CLOSE_ATLAS = "uitools-icon-close"

Style.mode = nil        -- nil until decided, then "skin" or "flat"
local S                 -- EllesmereUI facade
local entries = {}      -- every styling request, replayed when the mode is decided or changes
local looksCallbacks = {}
local flat = {}         -- flat-mode painters, keyed like the public functions
local skin = {}         -- skin-mode painters

-------------------------------------------------------------------------------
-- Dispatch
-------------------------------------------------------------------------------
local function Apply(entry)
    local impl = (Style.mode == "skin" and skin or flat)[entry.kind]
    if impl then
        local ok, err = pcall(impl, unpack(entry.args, 1, entry.n))
        if not ok then geterrorhandler()(err) end
    end
end

local function Request(kind, ...)
    local entry = { kind = kind, args = { ... }, n = select("#", ...) }
    entries[#entries + 1] = entry
    if Style.mode then Apply(entry) end
end

-- Decide (or switch) the mode and paint everything requested so far.
function Style.Finalize(mode, facade)
    if mode == "skin" then
        S = facade
    elseif Style.mode == "skin" then
        return -- never downgrade a skinned window
    end
    if Style.mode == mode then return end
    Style.mode = mode
    for _, entry in ipairs(entries) do Apply(entry) end
    if mode == "skin" and S.OnLooksChanged then
        S.OnLooksChanged(function() Style.FireLooksChanged() end)
    end
    Style.FireLooksChanged()
end

function Style.IsSkinned()
    return Style.mode == "skin"
end

function Style.OnLooksChanged(fn)
    looksCallbacks[#looksCallbacks + 1] = fn
end

function Style.FireLooksChanged()
    for _, fn in ipairs(looksCallbacks) do
        local ok, err = pcall(fn)
        if not ok then geterrorhandler()(err) end
    end
end

-------------------------------------------------------------------------------
-- Colours and fonts
-------------------------------------------------------------------------------
function Style.Accent()
    if S and S.GetAccentColor then
        local r, g, b = S.GetAccentColor()
        if r then return r, g, b end
    end
    return ACCENT[1], ACCENT[2], ACCENT[3]
end

function Style.AccentHex()
    local r, g, b = Style.Accent()
    return string.format("|cff%02x%02x%02x", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

function Style.FontPath()
    if S and S.GetFont then
        local path, flag = S.GetFont()
        if path then return path, flag or "" end
    end
    return FONT, ""
end

-------------------------------------------------------------------------------
-- Flat helpers
-------------------------------------------------------------------------------
local function Solid(parent, layer, c, sublevel)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

-- 1px border on a child frame one level above the parent.
local function FlatBorder(frame, c)
    if frame.sfBorder then return frame.sfBorder end
    local bf = CreateFrame("Frame", nil, frame)
    bf:SetAllPoints(frame)
    bf:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
    bf:EnableMouse(false)
    local edges = {}
    for i, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = bf:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false); t:SetTexelSnappingBias(0) end
        if side == "TOP" or side == "BOTTOM" then
            t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT"); t:SetHeight(1)
        else
            t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side); t:SetWidth(1)
        end
        edges[i] = t
    end
    bf.edges = edges
    function bf:SetColor(r, g, b, a)
        for _, t in ipairs(self.edges) do t:SetColorTexture(r, g, b, a or 1) end
    end
    frame.sfBorder = bf
    return bf
end

local function FadeTextures(frame, keep)
    for i = 1, select("#", frame:GetRegions()) do
        local r = select(i, frame:GetRegions())
        if r and r.IsObjectType and r:IsObjectType("Texture") and not (keep and keep[r]) then
            r:SetAlpha(0)
        end
    end
end

local function Label(widget)
    return widget.Text or (widget.GetFontString and widget:GetFontString())
end

-------------------------------------------------------------------------------
-- Window shell / panels
-------------------------------------------------------------------------------
-- opts.bottomBar = height adds a footer band; opts.noTopBar skips the title band.
function Style.Shell(frame, opts) Request("Shell", frame, opts) end
function skin.Shell(frame, opts) S.Shell(frame, opts) end
function flat.Shell(frame, opts)
    if frame.sfShell then return end
    frame.sfShell = true
    local bg = Solid(frame, "BACKGROUND", BG, -8)
    bg:SetAllPoints()
    if not (opts and opts.noTopBar) then
        local top = Solid(frame, "BACKGROUND", BAR, -5)
        top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(25)
    end
    local bb = opts and opts.bottomBar
    if bb then
        local bottom = Solid(frame, "BACKGROUND", BAR, -5)
        bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
        bottom:SetHeight(type(bb) == "number" and bb or 25)
    end
    if not (opts and opts.noBorder) then FlatBorder(frame, BORDER) end
end

-- opts.inset = darker fill, opts.noBorder, opts.noBg
function Style.Panel(frame, opts) Request("Panel", frame, opts) end
function skin.Panel(frame, opts) S.Panel(frame, opts) end
function flat.Panel(frame, opts)
    if frame.sfPanel then return end
    frame.sfPanel = true
    if not (opts and opts.noBg) then
        local bg = Solid(frame, "BACKGROUND", (opts and opts.inset) and INSET or BG, -6)
        bg:SetAllPoints()
    end
    if not (opts and opts.noBorder) then FlatBorder(frame, BORDER) end
end

-------------------------------------------------------------------------------
-- Text
-------------------------------------------------------------------------------
-- Re-font an existing FontString (keeps its size). Colour optional.
function Style.Font(fs, r, g, b) Request("Font", fs, r, g, b) end
function skin.Font(fs, r, g, b)
    if r then S.Font(fs, r, g, b); return end
    -- the skin primes a shadow font object; keep the colour set at creation
    local cr, cg, cb, ca = fs:GetTextColor()
    S.Font(fs)
    if cr then fs:SetTextColor(cr, cg, cb, ca or 1) end
end
function flat.Font(fs, r, g, b)
    local _, size = fs:GetFont()
    fs:SetFont(FONT, size or 12, "")
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
    if r then fs:SetTextColor(r, g, b or r) end
end

-- New FontString in the house font at the given size.
function Style.Text(parent, size, r, g, b, a, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(FONT, size or 12, "")
    fs:SetTextColor(r or 1, g or 1, b or 1, a or 1)
    Style.Font(fs)
    return fs
end

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------
-- Flat block button. Expects a .Text FontString (or GetFontString) for the label.
-- keepKeys names texture regions (e.g. { "Icon" }) that must stay visible.
function Style.Button(btn, keepKeys) Request("Button", btn, keepKeys) end
function skin.Button(btn, keepKeys)
    S.Button(btn, keepKeys)
    local fs = Label(btn)
    if fs then S.Font(fs); S.StateButtonLabel(btn) end
end
function flat.Button(btn, keepKeys)
    if btn.sfButton then return end
    btn.sfButton = true
    local keep = {}
    if keepKeys then
        for _, k in ipairs(keepKeys) do if btn[k] then keep[btn[k]] = true end end
    end
    FadeTextures(btn, keep)
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local t = btn[getter] and btn[getter](btn)
        if t and not keep[t] then t:SetAlpha(0) end
    end
    local fill = Solid(btn, "BACKGROUND", BG)
    fill:SetAllPoints()
    FlatBorder(btn, BORDER)
    local hover = Solid(btn, "HIGHLIGHT", { 1, 1, 1, 0.1 })
    hover:SetAllPoints()
    local fs = Label(btn)
    if fs then
        flat.Font(fs)
        local function reflect()
            if btn:IsEnabled() then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(0.5, 0.5, 0.5) end
        end
        btn:HookScript("OnEnable", reflect)
        btn:HookScript("OnDisable", reflect)
        reflect()
    end
end

-- Text input (InputBoxTemplate): near-black box with a border.
function Style.EditBox(eb) Request("EditBox", eb) end
function skin.EditBox(eb)
    S.EditBox(eb)
    S.Font(eb)
end
function flat.EditBox(eb)
    if eb.sfEdit then return end
    eb.sfEdit = true
    FadeTextures(eb)
    for _, k in ipairs({ "Left", "Right", "Middle", "Mid" }) do
        local r = eb[k]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
    local fill = Solid(eb, "BACKGROUND", { 0.02, 0.02, 0.02, 1 })
    fill:SetAllPoints()
    FlatBorder(eb, BORDER)
    flat.Font(eb)
end

-- Close (X) glyph button.
function Style.CloseButton(btn) Request("CloseButton", btn) end
function skin.CloseButton(btn) S.CloseButton(btn) end
function flat.CloseButton(btn)
    if btn.sfClose then return end
    if btn.SetNormalTexture then btn:SetNormalTexture("") end
    if btn.SetPushedTexture then btn:SetPushedTexture("") end
    if btn.SetHighlightTexture then btn:SetHighlightTexture("") end
    if btn.SetDisabledTexture then btn:SetDisabledTexture("") end
    FadeTextures(btn)
    local x = btn:CreateTexture(nil, "OVERLAY")
    x:SetAtlas(CLOSE_ATLAS)
    x:SetSize(14, 14)
    x:SetPoint("CENTER", -2, 0)
    x:SetVertexColor(1, 1, 1, 0.75)
    btn.sfClose = x
    btn:HookScript("OnEnter", function() x:SetVertexColor(1, 1, 1, 1) end)
    btn:HookScript("OnLeave", function() x:SetVertexColor(1, 1, 1, 0.75) end)
end

-------------------------------------------------------------------------------
-- Tabs. A tab is a Button with a .Text label and a .tabID; its parent carries
-- .selectedTabID. Style.SelectTab(parent, tabID) switches the active tab.
-------------------------------------------------------------------------------
local function TabParent(tab)
    local parent = tab:GetParent()
    if parent and not parent.SetTabVisuallySelected then
        -- EllesmereUI hooks this to refresh its tab visuals; the flat painter
        -- refreshes from Style.SelectTab.
        parent.SetTabVisuallySelected = function() end
        parent.sfTabs = {}
    end
    return parent
end

local function UpdateFlatTab(tab)
    local parent = tab:GetParent()
    local sel = parent and parent.selectedTabID ~= nil and parent.selectedTabID == tab.tabID
    if tab.Text then tab.Text:SetAlpha(sel and 1 or 0.5) end
    if tab.sfUnderline then
        local r, g, b = Style.Accent()
        tab.sfUnderline:SetColorTexture(r, g, b, 1)
        tab.sfUnderline:SetShown(sel and true or false)
    end
end

function Style.Tab(tab) Request("Tab", tab) end
function skin.Tab(tab)
    local parent = TabParent(tab)
    if parent and parent.sfTabs and not tab.sfRegistered then
        tab.sfRegistered = true
        table.insert(parent.sfTabs, tab)
    end
    S.Tab(tab)
end
function flat.Tab(tab)
    local parent = TabParent(tab)
    if tab.sfTab then UpdateFlatTab(tab); return end
    tab.sfTab = true
    FadeTextures(tab, { [tab.Text or false] = true })
    local hl = tab.GetHighlightTexture and tab:GetHighlightTexture()
    if hl then hl:SetTexture("") end
    local bg = Solid(tab, "BACKGROUND", TAB_BG)
    bg:SetAllPoints()
    local hover = Solid(tab, "HIGHLIGHT", { 1, 1, 1, 0.06 })
    hover:SetAllPoints()
    local underline = tab:CreateTexture(nil, "OVERLAY", nil, 6)
    if underline.SetSnapToPixelGrid then underline:SetSnapToPixelGrid(false); underline:SetTexelSnappingBias(0) end
    underline:SetHeight(1)
    underline:SetPoint("BOTTOMLEFT")
    underline:SetPoint("BOTTOMRIGHT")
    tab.sfUnderline = underline
    if tab.Text then
        flat.Font(tab.Text)
        tab.Text:SetTextColor(1, 1, 1)
    end
    if parent and parent.sfTabs and not tab.sfRegistered then
        tab.sfRegistered = true
        table.insert(parent.sfTabs, tab)
    end
    UpdateFlatTab(tab)
end

function Style.SelectTab(parent, tabID)
    parent.selectedTabID = tabID
    if not parent.sfTabs then return end
    for _, tab in ipairs(parent.sfTabs) do
        if Style.mode ~= "skin" then UpdateFlatTab(tab) end
        if tab.tabID == tabID and parent.SetTabVisuallySelected then
            parent:SetTabVisuallySelected(tab)
        end
    end
end

Style.OnLooksChanged(function()
    if Style.mode == "skin" then return end
    for _, entry in ipairs(entries) do
        if entry.kind == "Tab" then UpdateFlatTab(entry.args[1]) end
    end
end)

-------------------------------------------------------------------------------
-- Check buttons (UICheckButtonTemplate)
-------------------------------------------------------------------------------
function Style.Checkbox(cb) Request("Checkbox", cb) end
function skin.Checkbox(cb) S.Checkbox(cb, { borderInset = 4 }) end
function flat.Checkbox(cb)
    if cb.sfCheck then return end
    cb.sfCheck = true
    if cb.SetNormalTexture then cb:SetNormalTexture("") end
    if cb.SetPushedTexture then cb:SetPushedTexture("") end
    if cb.SetHighlightTexture then cb:SetHighlightTexture("") end
    local checked = cb.GetCheckedTexture and cb:GetCheckedTexture()
    local dchecked = cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture()
    FadeTextures(cb, { [checked or false] = true, [dchecked or false] = true })
    local fill = Solid(cb, "BACKGROUND", { 0.02, 0.02, 0.02, 1 })
    fill:SetPoint("TOPLEFT", 4, -4)
    fill:SetPoint("BOTTOMRIGHT", -4, 4)
    local bh = CreateFrame("Frame", nil, cb)
    bh:SetPoint("TOPLEFT", 4, -4)
    bh:SetPoint("BOTTOMRIGHT", -4, 4)
    bh:SetFrameLevel(cb:GetFrameLevel() + 1)
    FlatBorder(bh, { 0.25, 0.25, 0.25, 1 })
    if checked then
        local r, g, b = Style.Accent()
        checked:SetVertexColor(r, g, b, 1)
    end
end

-------------------------------------------------------------------------------
-- Scroll frames (MinimalScrollBar with a slim thumb)
-------------------------------------------------------------------------------
function Style.ScrollBar(sb) Request("ScrollBar", sb) end
function skin.ScrollBar(sb) S.ScrollBar(sb) end
function flat.ScrollBar(sb)
    if sb.sfScroll then return end
    sb.sfScroll = true
    for _, k in ipairs({ "Back", "Forward" }) do
        local b = sb[k]
        if b then
            FadeTextures(b)
            if b.Texture then b.Texture:SetAlpha(0) end
        end
    end
    if sb.Track then FadeTextures(sb.Track) end
    local thumb = (sb.Track and sb.Track.Thumb) or (sb.GetThumb and sb:GetThumb())
    if thumb then
        FadeTextures(thumb)
        local t = Solid(thumb, "ARTWORK", { 1, 1, 1, 0.3 })
        t:SetPoint("TOP"); t:SetPoint("BOTTOM"); t:SetWidth(4)
    end
end

-- Creates a scroll frame plus bar inside `parent`; the caller anchors the
-- scroll frame. Returns scrollFrame, scrollBar, content. The bar sits in a
-- gutter on the scroll frame's right.
function Style.ScrollFrame(parent, width)
    local sf, sb
    if ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar then
        sf = CreateFrame("ScrollFrame", nil, parent)
        sb = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
        sb:SetPoint("TOPLEFT", sf, "TOPRIGHT", 2, 0)
        sb:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 2, 0)
        sb:SetWidth(8)
        ScrollUtil.InitScrollFrameWithScrollBar(sf, sb)
        sf:EnableMouseWheel(true)
    else
        sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        sb = sf.ScrollBar
    end
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(width or 100, 10)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(_, w) content:SetWidth(w) end)
    if sb then Style.ScrollBar(sb) end
    return sf, sb, content
end

-------------------------------------------------------------------------------
-- Icons and bars
-------------------------------------------------------------------------------
-- Crops the baked bevel off an icon; with `parent` also draws a 1px black frame.
function Style.SquareIcon(tex, parent)
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if parent and not tex.sfBacking then
        local back = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
        back:SetColorTexture(0, 0, 0, 1)
        back:SetPoint("TOPLEFT", tex, "TOPLEFT", -1, 1)
        back:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 1, -1)
        tex.sfBacking = back
    end
end

function Style.BarFill(bar) Request("BarFill", bar) end
function skin.BarFill(bar) S.ApplyBarFill(bar) end
function flat.BarFill(bar)
    local r, g, b = Style.Accent()
    bar:SetStatusBarColor(r * 0.8, g * 0.8, b * 0.8, 0.95)
end

-- First atlas from the list that exists on this client, or nil.
function Style.FindAtlas(names)
    if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
    for _, name in ipairs(names) do
        local ok, info = pcall(C_Texture.GetAtlasInfo, name)
        if ok and info then return name end
    end
    return nil
end

-------------------------------------------------------------------------------
-- Registration
-------------------------------------------------------------------------------
if EllesmereUI and EllesmereUI.RegisterSkin then
    EllesmereUI.RegisterSkin("SlotFiller", function(facade)
        Style.Finalize("skin", facade)
    end)
end

-- EllesmereUI dispatches skin callbacks at PLAYER_LOGIN, before this runs.
-- Anything still undecided one frame later gets the flat look.
ns:On("LOGIN", function()
    C_Timer.After(0, function()
        if not Style.mode then Style.Finalize("flat") end
    end)
end)
