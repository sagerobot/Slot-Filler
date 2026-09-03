-- Slot Filler: a Pawn string box under Ask Mr. Robot's window.
--
-- The optimizer site hands out a Pawn string next to the addon import
-- code, and the AMR window is where you are while you have it: the box
-- sits under that window and saves the string as a weight profile, which
-- then follows the equipment set AMR made for the same setup.
local _, ns = ...

local box

-------------------------------------------------------------------------------
-- AMR's imported setups: the import code carries every setup's label and
-- its gear, and the AMR addon keeps them. A weight profile whose name ends
-- in a setup's label is that setup's: its "made for" gear is the setup's
-- gear, not whatever was worn when the string was pasted.
-------------------------------------------------------------------------------
-- { { label, specSlot, gear = { [slotID] = itemID } }, ... }
function ns:AmrSetups()
    local amr = AskMrRobot
    local list = type(amr) == "table" and amr.db and amr.db.char and amr.db.char.GearSetups
    local out = {}
    if type(list) ~= "table" then return out end
    for _, setup in ipairs(list) do
        if type(setup) == "table" and type(setup.Label) == "string" then
            local gear = {}
            for slot, obj in pairs(type(setup.Gear) == "table" and setup.Gear or {}) do
                local id = tonumber(type(obj) == "table" and obj.id or nil)
                if type(slot) == "number" and id then gear[slot] = id end
            end
            out[#out + 1] = { label = setup.Label, specSlot = tonumber(setup.SpecSlot), gear = gear }
        end
    end
    return out
end

local function EndsWith(name, label)
    if type(name) ~= "string" or type(label) ~= "string" or label == "" then return false end
    name, label = name:lower(), label:lower()
    return #name >= #label and name:sub(-#label) == label
end

-- The AMR setup a profile belongs to, by its name or Pawn name ending in
-- the setup's label; the longest label wins.
function ns:AmrSetupFor(scale)
    if not scale then return nil end
    local best
    for _, setup in ipairs(self:AmrSetups()) do
        if (EndsWith(scale.name, setup.label) or EndsWith(scale.pawnName, setup.label)) and (not best or #setup.label > #best.label) then
            best = setup
        end
    end
    return best
end

-- A gear snapshot (as GearSnapshot makes) from a setup's item ids.
local function SnapshotFromSetup(setup)
    local snap = {}
    for slot, id in pairs(setup.gear) do
        local name = C_Item and C_Item.GetItemInfo and select(1, C_Item.GetItemInfo(id)) or nil
        snap[slot] = { itemID = id, ilvl = 0, name = name }
    end
    return snap
end

-- Ties every profile of this spec to its AMR setup: the setup's gear as
-- the gear the weights are for, its label as the equipment set. Returns
-- the labels of setups for this spec that have no profile yet.
function ns:LinkProfilesToAmr()
    local setups = self:AmrSetups()
    if #setups == 0 then return {} end
    local covered = {}
    for _, scale in ipairs(self:GetStatProfiles()) do
        local setup = self:AmrSetupFor(scale)
        if setup then
            scale.gear = SnapshotFromSetup(setup)
            scale.setName = setup.label
            scale.amrSetup = setup.label
            covered[setup.label] = true
        end
    end
    local missing = {}
    local specSlot = GetSpecialization and GetSpecialization() or nil
    for _, setup in ipairs(setups) do
        if not covered[setup.label] and (not specSlot or not setup.specSlot or setup.specSlot == specSlot) then
            missing[#missing + 1] = setup.label
        end
    end
    return missing
end

-- AMR's windows are AmrUi frames with global names; the main one is the
-- big one on screen.
local function FindAmrFrame()
    for i = 1, 40 do
        local f = _G["AmrUiFrame" .. i]
        if f and f.IsShown and f:IsShown() and (f:GetWidth() or 0) >= 500 then return f end
    end
    return nil
end
ns.FindAmrFrame = FindAmrFrame

local function Build()
    local Style = ns.Style
    box = CreateFrame("Frame", "SlotFillerAmrBox", UIParent)
    box:SetHeight(48)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    Style.Panel(box)
    local label = Style.Text(box, 11, 1, 1, 1, 0.85)
    label:SetPoint("TOPLEFT", 12, -7)
    label:SetText("|cff4fc3f7Slot Filler|r  Pawn string from the optimizer (next to the import code):")
    local import = ns.UI.TextButton(box, "Import", 60, 20)
    import:SetPoint("BOTTOMRIGHT", -10, 7)
    local edit = CreateFrame("EditBox", nil, box, "InputBoxTemplate")
    edit:SetAutoFocus(false)
    edit:SetHeight(20)
    edit:SetPoint("BOTTOMLEFT", 16, 7)
    edit:SetPoint("RIGHT", import, "LEFT", -8, 0)
    Style.EditBox(edit)
    local result = Style.Text(box, 10, 1, 1, 1, 0.6)
    result:SetPoint("LEFT", label, "RIGHT", 10, 0)
    result:SetPoint("RIGHT", -10, 0)
    result:SetJustifyH("RIGHT")
    result:SetWordWrap(false)
    local function Import()
        local scale, err = ns:ImportPawnString(edit:GetText() or "")
        if scale then
            edit:SetText("")
            edit:ClearFocus()
            local missing = ns:LinkProfilesToAmr()
            local setup = ns:AmrSetupFor(scale)
            local set = setup and setup.label or ns:StatProfileSet(scale)
            local text = string.format("Saved as %s%s.", tostring(scale.name), set and (", for the " .. set .. " setup") or "")
            if #missing > 0 then text = text .. "  Still without weights: " .. table.concat(missing, ", ") end
            result:SetText(text)
            ns:Fire("SETTINGS_CHANGED")
        else
            result:SetText("|cffff5555" .. tostring(err) .. "|r")
        end
    end
    import:SetScript("OnClick", Import)
    edit:SetScript("OnEnterPressed", Import)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ns.UI.Tip(import, "ANCHOR_TOP", "Import weights", "Saves the Pawn string as a weight profile for this spec, remembering the gear you wear now. It follows the equipment set of the same name.")
    box.Edit, box.Result, box.Import = edit, result, import
    return box
end

-- Shows the box under `frame` (AMR's main window, found when nil).
function ns:ShowAmrBox(frame)
    frame = frame or FindAmrFrame()
    if not frame then return nil end
    box = box or Build()
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -4)
    box:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4)
    box:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)
    if not frame.slotFillerHooked then
        frame.slotFillerHooked = true
        frame:HookScript("OnHide", function() if box then box:Hide() end end)
    end
    local missing = ns:LinkProfilesToAmr()
    box.Result:SetText(#missing > 0 and ("Setups without weights: " .. table.concat(missing, ", ")) or "")
    box:Show()
    return box
end

-- AMR builds its window a moment after Show; look for it a few times.
local function AfterShow()
    local tries = 0
    local function Try()
        tries = tries + 1
        if ns:ShowAmrBox() or tries > 20 then return end
        C_Timer.After(0.25, Try)
    end
    Try()
end

local function Hook()
    local amr = AskMrRobot
    if ns.amrHooked or type(amr) ~= "table" or type(amr.Show) ~= "function" or not hooksecurefunc then return end
    ns.amrHooked = true
    hooksecurefunc(amr, "Show", AfterShow)
    hooksecurefunc(amr, "Hide", function() if box then box:Hide() end end)
    -- a fresh import: setups (and their gear) may have changed
    if type(amr.ImportCharacter) == "function" then
        hooksecurefunc(amr, "ImportCharacter", function()
            ns:Schedule("amrImport", 1, function()
                local missing = ns:LinkProfilesToAmr()
                if box and box:IsShown() then box.Result:SetText(#missing > 0 and ("Setups without weights: " .. table.concat(missing, ", ")) or "") end
                ns:Fire("SETTINGS_CHANGED")
            end)
        end)
    end
end

ns:On("LOGIN", function()
    Hook()
    ns:RegisterEvent("ADDON_LOADED", function(name) if name == "AskMrRobot" then Hook() end end)
end)
