--[[
    zInspect
    Vanilla WoW 1.12 Addon (zSuite)
    Sleek, scaled inspection suite with 3D model viewport,
    smooth mouse controls, gear slots, Honor tab, and custom Talents frame.
    Supports Shift-Click linking, Ctrl-Click dressing room try-on,
    and cross-faction gear extraction via GetInventoryItemID / zAPI.
--]]

local _G = _G or getfenv(0)

-- Global addon table
zInspect = {
    TITLE = "|cff33ffccz|rInspect",
    VERSION = "1.4.4",
    currentUnit = nil,
    currentUnitName = nil,
    currentTab = "character",
    currentTalentSpec = 1,
    isTargetPlayer = false,
    isTargetEnemy = false,
    isTargetNPC = false,
    isWaitingForRange = false,
    pollTimer = 0,
    inspectRequested = false,
    cache = {},
    tabs = {},
    specTabs = {},
}

-- Keybinding localization text
BINDING_HEADER_ZSUITE = BINDING_HEADER_ZSUITE or "zSuite"
BINDING_NAME_ZINSPECT_TARGET = "Inspect Target"

-- Equipment slots definition (19 slots)
local EQUIPMENT_SLOTS = {
    -- Left column
    { id = 1,  name = "HeadSlot",          label = "Head",       side = "LEFT",   index = 1 },
    { id = 2,  name = "NeckSlot",          label = "Neck",       side = "LEFT",   index = 2 },
    { id = 3,  name = "ShoulderSlot",      label = "Shoulder",   side = "LEFT",   index = 3 },
    { id = 15, name = "BackSlot",          label = "Back",       side = "LEFT",   index = 4 },
    { id = 5,  name = "ChestSlot",         label = "Chest",      side = "LEFT",   index = 5 },
    { id = 4,  name = "ShirtSlot",         label = "Shirt",      side = "LEFT",   index = 6 },
    { id = 19, name = "TabardSlot",        label = "Tabard",     side = "LEFT",   index = 7 },
    { id = 9,  name = "WristSlot",         label = "Wrist",      side = "LEFT",   index = 8 },
    -- Right column
    { id = 10, name = "HandsSlot",         label = "Hands",      side = "RIGHT",  index = 1 },
    { id = 6,  name = "WaistSlot",         label = "Waist",      side = "RIGHT",  index = 2 },
    { id = 7,  name = "LegsSlot",          label = "Legs",       side = "RIGHT",  index = 3 },
    { id = 8,  name = "FeetSlot",          label = "Feet",       side = "RIGHT",  index = 4 },
    { id = 11, name = "Finger0Slot",       label = "Finger 1",   side = "RIGHT",  index = 5 },
    { id = 12, name = "Finger1Slot",       label = "Finger 2",   side = "RIGHT",  index = 6 },
    { id = 13, name = "Trinket0Slot",      label = "Trinket 1",  side = "RIGHT",  index = 7 },
    { id = 14, name = "Trinket1Slot",      label = "Trinket 2",  side = "RIGHT",  index = 8 },
    -- Bottom weapons row
    { id = 16, name = "MainHandSlot",      label = "Main Hand",  side = "BOTTOM", index = 1 },
    { id = 17, name = "SecondaryHandSlot", label = "Off Hand",   side = "BOTTOM", index = 2 },
    { id = 18, name = "RangedSlot",        label = "Ranged",     side = "BOTTOM", index = 3 },
}

-- Class color palette fallback
local CLASS_COLORS = {
    ["WARRIOR"]     = { r = 0.78, g = 0.61, b = 0.43, hex = "|cffc79c6e" },
    ["MAGE"]        = { r = 0.41, g = 0.80, b = 0.94, hex = "|cff69ccf0" },
    ["ROGUE"]       = { r = 1.00, g = 0.96, b = 0.41, hex = "|cfffff569" },
    ["DRUID"]       = { r = 1.00, g = 0.49, b = 0.04, hex = "|cffff7d0a" },
    ["HUNTER"]      = { r = 0.67, g = 0.83, b = 0.45, hex = "|cffabd473" },
    ["SHAMAN"]      = { r = 0.00, g = 0.44, b = 0.87, hex = "|cff0070de" },
    ["PRIEST"]      = { r = 1.00, g = 1.00, b = 1.00, hex = "|cffffffff" },
    ["WARLOCK"]     = { r = 0.58, g = 0.51, b = 0.79, hex = "|cff9482c9" },
    ["PALADIN"]     = { r = 0.96, g = 0.55, b = 0.73, hex = "|cfff58cba" },
}

-- Flat backdrop styling consistent with zSuite
local flatBackdrop = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
    tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
}

local slotBackdrop = {
    bgFile = "Interface\\BUTTONS\\WHITE8X8",
    edgeFile = "Interface\\BUTTONS\\WHITE8X8",
    tile = false, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
}

-- Hidden scanner tooltip for caching item links into client memory
local scannerTooltip = CreateFrame("GameTooltip", "zInspectScannerTooltip", UIParent, "GameTooltipTemplate")
scannerTooltip:SetOwner(UIParent, "ANCHOR_NONE")

-- Create Main Window (Scaled down to 338 x 424 to match standard CharacterFrame)
local f = CreateFrame("Frame", "zInspectFrame", UIParent)
f:SetWidth(338)
f:SetHeight(424)
f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
f:SetBackdrop(flatBackdrop)
f:SetBackdropColor(0.07, 0.07, 0.07, 0.96)
f:SetBackdropBorderColor(0, 0, 0, 1)
f:EnableMouse(true)
f:SetMovable(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() this:StartMoving() end)
f:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    if zInspectDB then
        local point, _, _, x, y = this:GetPoint()
        zInspectDB.pos = { point = point, x = x, y = y }
    end
end)
f:SetFrameStrata("DIALOG")
f:Hide()

-- Allow closing via ESC key
tinsert(UISpecialFrames, "zInspectFrame")

-- Window Header Controls (Top Right, in FULLSCREEN_DIALOG so never obscured)
local closeBtn = CreateFrame("Button", "zInspectCloseButton", f)
closeBtn:SetWidth(16)
closeBtn:SetHeight(16)
closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
closeBtn:SetBackdrop(flatBackdrop)
closeBtn:SetBackdropColor(0.18, 0.18, 0.18, 1)
closeBtn:SetBackdropBorderColor(0, 0, 0, 1)
closeBtn:SetFrameStrata("FULLSCREEN_DIALOG")
closeBtn:SetFrameLevel(60)

local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
closeBtnText:SetPoint("CENTER", closeBtn, "CENTER", 0, 0)
closeBtnText:SetText("X")
closeBtn:SetScript("OnClick", function() zInspect:Hide() end)
closeBtn:SetScript("OnEnter", function() this:SetBackdropColor(0.8, 0.2, 0.2, 1) end)
closeBtn:SetScript("OnLeave", function() this:SetBackdropColor(0.18, 0.18, 0.18, 1) end)

local resetBtn = CreateFrame("Button", "zInspectResetButton", f)
resetBtn:SetWidth(38)
resetBtn:SetHeight(16)
resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
resetBtn:SetBackdrop(flatBackdrop)
resetBtn:SetBackdropColor(0.18, 0.18, 0.18, 1)
resetBtn:SetBackdropBorderColor(0, 0, 0, 1)
resetBtn:SetFrameStrata("FULLSCREEN_DIALOG")
resetBtn:SetFrameLevel(60)

local resetBtnText = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
resetBtnText:SetPoint("CENTER", resetBtn, "CENTER", 0, 0)
resetBtnText:SetText("Reset")
resetBtn:SetScript("OnClick", function() zInspect:ResetModelView() end)
resetBtn:SetScript("OnEnter", function() this:SetBackdropColor(0.28, 0.28, 0.28, 1) end)
resetBtn:SetScript("OnLeave", function() this:SetBackdropColor(0.18, 0.18, 0.18, 1) end)

-- Status Badge (Under Reset/Close buttons on Top Right)
local statusBadge = f:CreateFontString("zInspectStatusBadge", "OVERLAY", "GameFontHighlightSmall")
statusBadge:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -25)
statusBadge:SetJustifyH("RIGHT")
statusBadge:SetText("")

-- Unit Identity Text (Top Left, strictly bounded so text NEVER overlaps)
local nameText = f:CreateFontString("zInspectNameText", "OVERLAY", "GameFontHighlightLarge")
nameText:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -6)
nameText:SetWidth(230)
nameText:SetJustifyH("LEFT")
nameText:SetShadowColor(0, 0, 0, 1)
nameText:SetShadowOffset(1, -1)
nameText:SetText("")

local infoText = f:CreateFontString("zInspectInfoText", "OVERLAY", "GameFontNormalSmall")
infoText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
infoText:SetWidth(230)
infoText:SetJustifyH("LEFT")
infoText:SetTextColor(0.85, 0.85, 0.85)
infoText:SetShadowColor(0, 0, 0, 1)
infoText:SetShadowOffset(1, -1)
infoText:SetText("")

local guildText = f:CreateFontString("zInspectGuildText", "OVERLAY", "GameFontHighlightSmall")
guildText:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -1)
guildText:SetWidth(230)
guildText:SetJustifyH("LEFT")
guildText:SetTextColor(0.4, 0.8, 1.0)
guildText:SetShadowColor(0, 0, 0, 1)
guildText:SetShadowOffset(1, -1)
guildText:SetText("")

statusBadge:SetShadowColor(0, 0, 0, 1)
statusBadge:SetShadowOffset(1, -1)

-- Discrete, subtle branding at bottom right
local brandText = f:CreateFontString("zInspectBrandText", "OVERLAY", "GameFontDisableSmall")
brandText:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
brandText:SetJustifyH("RIGHT")
brandText:SetText("|cff444444z|r|cff333333Inspect|r")

-- 3D Model Viewport (Snugly sized to 254 x 298 px between slot columns)
local modelContainer = CreateFrame("Frame", "zInspectModelContainer", f)
modelContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -46)
modelContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -42, 76)
modelContainer:SetBackdrop(flatBackdrop)
modelContainer:SetBackdropColor(0.04, 0.04, 0.04, 0.85)
modelContainer:SetBackdropBorderColor(0.12, 0.12, 0.12, 1)

local model = CreateFrame("PlayerModel", "zInspectPlayerModel", modelContainer)
model:SetAllPoints(modelContainer)
model:EnableMouse(true)
model:EnableMouseWheel(true)

-- Default camera presets
local DEFAULT_FACING = 0.2
local DEFAULT_POS_Z = 0
local DEFAULT_POS_X = 0
local DEFAULT_POS_Y = 0

function zInspect:ResetModelView()
    model:SetFacing(DEFAULT_FACING)
    model:SetPosition(DEFAULT_POS_Z, DEFAULT_POS_X, DEFAULT_POS_Y)
end

-- 3D Model Mouse Interaction Handlers
model:SetScript("OnMouseDown", function()
    local StartX, StartY = GetCursorPosition()
    local btn = arg1

    if btn == "LeftButton" then
        this:SetScript("OnUpdate", function()
            local EndX, EndY = GetCursorPosition()
            local scale = this:GetEffectiveScale() or 1
            local diffX = (EndX - StartX) / scale
            this:SetFacing(diffX / 34 + this:GetFacing())
            StartX, StartY = EndX, EndY
        end)
    elseif btn == "RightButton" then
        this:SetScript("OnUpdate", function()
            local EndX, EndY = GetCursorPosition()
            local scale = this:GetEffectiveScale() or 1
            local Z, X, Y = this:GetPosition()
            local diffX = (EndX - StartX) / scale
            local diffY = (EndY - StartY) / scale
            X = diffX / 45 + X
            Y = diffY / 45 + Y
            this:SetPosition(Z, X, Y)
            StartX, StartY = EndX, EndY
        end)
    end
end)

model:SetScript("OnMouseUp", function()
    this:SetScript("OnUpdate", nil)
end)

model:SetScript("OnHide", function()
    this:SetScript("OnUpdate", nil)
end)

-- Mouse Wheel: Zoom towards cursor position
model:SetScript("OnMouseWheel", function()
    local delta = arg1
    local curX, curY = GetCursorPosition()
    local scale = this:GetEffectiveScale() or 1
    local mx, my = curX / scale, curY / scale
    local cx, cy = this:GetCenter()
    
    local Z, X, Y = this:GetPosition()
    local zoomStep = (delta > 0 and 0.40 or -0.40)
    Z = Z + zoomStep

    if cx and cy then
        local offX = (mx - cx) * 0.0020 * delta
        local offY = (my - cy) * 0.0020 * delta
        X = X - offX
        Y = Y - offY
    end

    this:SetPosition(Z, X, Y)
end)

-- Creature / NPC Info Overlay Panel
local npcPanel = CreateFrame("Frame", "zInspectNPCPanel", f)
npcPanel:SetPoint("TOPLEFT", modelContainer, "BOTTOMLEFT", 0, -4)
npcPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 30)
npcPanel:SetBackdrop(flatBackdrop)
npcPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.92)
npcPanel:SetBackdropBorderColor(0.18, 0.18, 0.18, 1)
npcPanel:Hide()

local npcDetails = npcPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
npcDetails:SetPoint("TOPLEFT", npcPanel, "TOPLEFT", 8, -6)
npcDetails:SetJustifyH("LEFT")
npcDetails:SetText("")

local npcTargetText = npcPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
npcTargetText:SetPoint("TOPLEFT", npcDetails, "BOTTOMLEFT", 0, -3)
npcTargetText:SetJustifyH("LEFT")
npcTargetText:SetText("")

-- Gear Item count / avg iLvl text
local statsText = f:CreateFontString("zInspectStatsText", "OVERLAY", "GameFontHighlightSmall")
statsText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 30)
statsText:SetJustifyH("LEFT")
statsText:SetText("")

-- Create Sleek Equipment Slot Buttons (32 x 32 px with 36 px vertical step)
local slotButtons = {}
local offHandBtnRef = nil

local function CreateSlotButton(slotDef)
    local btn = CreateFrame("Button", "zInspectSlot_" .. slotDef.name, f)
    btn:SetWidth(32)
    btn:SetHeight(32)
    btn:SetBackdrop(slotBackdrop)
    btn:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
    btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Anchor slot based on side and index
    if slotDef.side == "LEFT" then
        btn:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -46 - (slotDef.index - 1) * 36)
    elseif slotDef.side == "RIGHT" then
        btn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -46 - (slotDef.index - 1) * 36)
    elseif slotDef.side == "BOTTOM" then
        if slotDef.index == 2 then
            btn:SetPoint("BOTTOM", modelContainer, "BOTTOM", 0, -38)
            offHandBtnRef = btn
        elseif slotDef.index == 1 then
            btn:SetPoint("RIGHT", offHandBtnRef or modelContainer, "LEFT", -4, 0)
        elseif slotDef.index == 3 then
            btn:SetPoint("LEFT", offHandBtnRef or modelContainer, "RIGHT", 4, 0)
        end
    end

    -- Icon texture
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Stack count text
    local count = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    btn.count = count

    -- Highlight texture
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn)
    hl:SetTexture(1, 1, 1, 0.2)
    btn.highlight = hl

    btn.slotDef = slotDef
    btn.slotId = slotDef.id

    -- Tooltip Handlers
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local hasItem = false
        if zInspect.currentUnit and not zInspect.isWaitingForRange and not zInspect.isTargetEnemy then
            hasItem = GameTooltip:SetInventoryItem(zInspect.currentUnit, this.slotId)
        end
        if not hasItem and this.itemLink then
            GameTooltip:SetHyperlink(this.itemLink)
            hasItem = true
        end
        if not hasItem then
            GameTooltip:SetText(this.slotDef.label, 1, 1, 1)
            GameTooltip:AddLine("Empty slot", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- OnClick: Shift-Click to Link into chat, Ctrl-Click to Try-On (DressUp)
    btn:SetScript("OnClick", function()
        local itemLink = this.itemLink
        if not itemLink and zInspect.currentUnit then
            itemLink = GetInventoryItemLink(zInspect.currentUnit, this.slotId)
        end
        if not itemLink then return end

        if IsControlKeyDown() then
            -- Try-on in Dressing Room
            DressUpItemLink(itemLink)
        elseif IsShiftKeyDown() then
            -- Insert link into active chat editbox
            local editBox = ChatFrameEditBox or (DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.editBox)
            if editBox then
                if editBox:IsVisible() then
                    editBox:Insert(itemLink)
                else
                    editBox:Show()
                    editBox:SetText(itemLink)
                    editBox:SetFocus()
                end
            end
        end
    end)

    slotButtons[slotDef.id] = btn
    return btn
end

for _, slotDef in ipairs(EQUIPMENT_SLOTS) do
    CreateSlotButton(slotDef)
end

-- Fix bottom weapon slot anchors cleanly
if slotButtons[16] and slotButtons[17] and slotButtons[18] then
    slotButtons[17]:ClearAllPoints()
    slotButtons[17]:SetPoint("BOTTOM", modelContainer, "BOTTOM", 0, -38)
    slotButtons[16]:ClearAllPoints()
    slotButtons[16]:SetPoint("RIGHT", slotButtons[17], "LEFT", -4, 0)
    slotButtons[18]:ClearAllPoints()
    slotButtons[18]:SetPoint("LEFT", slotButtons[17], "RIGHT", 4, 0)
end

-- =========================================================================
-- CUSTOM TOP SPEC TABS (Beast Mastery, Marksmanship, Survival, etc.)
-- Elevated to FULLSCREEN_DIALOG strata so nothing can ever draw over them
-- =========================================================================
local function CreateSpecTab(index)
    local tab = CreateFrame("Button", "zInspectSpecTab_" .. index, f)
    tab:SetWidth(102)
    tab:SetHeight(22)
    tab:SetBackdrop(flatBackdrop)
    tab:SetBackdropColor(0.10, 0.10, 0.10, 1)
    tab:SetBackdropBorderColor(0.20, 0.20, 0.20, 1)
    tab:SetFrameStrata("FULLSCREEN_DIALOG")
    tab:SetFrameLevel(50)
    tab:Hide()

    local txt = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER", tab, "CENTER", 0, 0)
    txt:SetText("Tree " .. index)
    txt:SetTextColor(0.6, 0.6, 0.6)
    tab.text = txt
    tab.specIndex = index

    tab:SetScript("OnClick", function()
        zInspect:SelectTalentSpec(this.specIndex)
    end)
    tab:SetScript("OnEnter", function()
        if zInspect.currentTalentSpec ~= this.specIndex then
            this:SetBackdropColor(0.18, 0.18, 0.18, 1)
        end
    end)
    tab:SetScript("OnLeave", function()
        if zInspect.currentTalentSpec ~= this.specIndex then
            this:SetBackdropColor(0.10, 0.10, 0.10, 1)
        end
    end)

    zInspect.specTabs[index] = tab
    return tab
end

local specTab1 = CreateSpecTab(1)
local specTab2 = CreateSpecTab(2)
local specTab3 = CreateSpecTab(3)

specTab1:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -37)
specTab2:SetPoint("LEFT", specTab1, "RIGHT", 4, 0)
specTab3:SetPoint("LEFT", specTab2, "RIGHT", 4, 0)

-- Guard against Turtle_TalentsData indexing errors via metatable fallback
local function EnsureTalentsClass()
    local unit = zInspect.currentUnit or "target"
    local _, class = UnitClass(unit)
    if not class or class == "" then
        class = "HUNTER"
    end

    if Turtle_TalentsData then
        Turtle_TalentsData[""] = Turtle_TalentsData[class] or Turtle_TalentsData["HUNTER"]
        setmetatable(Turtle_TalentsData, {
            __index = function(t, k)
                return t[class] or t["HUNTER"]
            end
        })
    end
    return class
end

function zInspect:SelectTalentSpec(specIndex)
    self.currentTalentSpec = specIndex
    local class = EnsureTalentsClass()

    -- Highlight our custom spec tabs
    for i = 1, 3 do
        local tab = self.specTabs[i]
        if tab then
            if i == specIndex then
                tab:SetBackdropColor(0.20, 0.20, 0.20, 1)
                tab:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
                tab.text:SetTextColor(1.0, 0.82, 0.0)
            else
                tab:SetBackdropColor(0.10, 0.10, 0.10, 1)
                tab:SetBackdropBorderColor(0.20, 0.20, 0.20, 1)
                tab.text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end

    -- Switch the tab inside Turtle WoW safely without throwing network errors
    if TWTalentFrame then
        if PanelTemplates_SetTab then
            PanelTemplates_SetTab(TWTalentFrame, specIndex)
        end
        if TWTalentFrame_Update then
            pcall(TWTalentFrame_Update)
        end
    end

    self:FormatTalentsFrame()
end

-- Sync tab names from Turtle WoW's database
function zInspect:SyncSpecTabLabels()
    local class = EnsureTalentsClass()
    for i = 1, 3 do
        local customTab = self.specTabs[i]
        if customTab then
            local title
            if Turtle_TalentsData and Turtle_TalentsData[class] and Turtle_TalentsData[class][i] then
                title = Turtle_TalentsData[class][i].name
            end
            if not title or title == "" then
                local bTab = _G["TWTalentFrameTab" .. i]
                if bTab then title = bTab:GetText() end
            end
            if title and title ~= "" then
                customTab.text:SetText(title)
            end
        end
    end
end

-- Post-format the talent tree so it fits cleanly inside zInspectFrame and never blocks UI clicks
function zInspect:FormatTalentsFrame()
    local tw = TWTalentFrame
    if not tw then return end

    EnsureTalentsClass()

    -- Disable toplevel auto-raise so clicking talents or bg NEVER rises above tabs
    tw:SetParent(f)
    if tw.SetToplevel then
        tw:SetToplevel(false)
    end
    tw:EnableMouse(false)
    tw:SetFrameStrata("DIALOG")
    tw:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Match zInspectFrame window dimensions (338 x 424)
    tw:SetScale(1.0)
    tw:ClearAllPoints()
    tw:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tw:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    tw:SetWidth(338)
    tw:SetHeight(424)

    -- Center talent background art cleanly inside the frame
    -- Native Blizzard talent art is 320 x 354 (Top: 256x256 + 64x256, Bottom: 256x98 + 64x98 visible)
    -- Centered horizontally: (338 - 320) / 2 = 9 px left and right margins
    -- Centered vertically:   (424 - 354) / 2 = 35 px top and bottom margins
    local tl = TWTalentFrameBackgroundTopLeft
    local tr = TWTalentFrameBackgroundTopRight
    local bl = TWTalentFrameBackgroundBottomLeft
    local br = TWTalentFrameBackgroundBottomRight

    if tl and tr and bl and br then
        local originX = 9
        local originY = -35
        local leftW = 256
        local rightW = 64
        local topH = 256
        local bottomH = 128

        -- In WoW 1.12, Textures MUST be anchored to a Frame (tw), NOT to other Textures!
        tl:ClearAllPoints()
        tl:SetPoint("TOPLEFT", tw, "TOPLEFT", originX, originY)
        tl:SetWidth(leftW)
        tl:SetHeight(topH)
        tl:SetTexCoord(0, 1, 0, 1)

        tr:ClearAllPoints()
        tr:SetPoint("TOPLEFT", tw, "TOPLEFT", originX + leftW, originY)
        tr:SetWidth(rightW)
        tr:SetHeight(topH)
        tr:SetTexCoord(0, 1, 0, 1)

        bl:ClearAllPoints()
        bl:SetPoint("TOPLEFT", tw, "TOPLEFT", originX, originY - topH)
        bl:SetWidth(leftW)
        bl:SetHeight(bottomH)
        bl:SetTexCoord(0, 1, 0, 1)

        br:ClearAllPoints()
        br:SetPoint("TOPLEFT", tw, "TOPLEFT", originX + leftW, originY - topH)
        br:SetWidth(rightW)
        br:SetHeight(bottomH)
        br:SetTexCoord(0, 1, 0, 1)
    end

    -- Scale and center the talent buttons (0.75 scale) cleanly over the background art
    local sf = TWTalentFrameScrollFrame
    if sf then
        sf:SetScale(0.75)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", tw, "TOPLEFT", 76, -68)
        sf:SetWidth(296)
        sf:SetHeight(440)
        -- Hide all texture regions on the scroll frame itself (the Blizzard scrollbar track graphics)
        local regions = { sf:GetRegions() }
        for _, reg in ipairs(regions) do
            if reg and reg.GetObjectType and reg:GetObjectType() == "Texture" then
                reg:SetTexture(nil)
                reg:Hide()
                reg:SetAlpha(0)
            end
        end
        if sf.backdrop then
            sf.backdrop:Hide()
            sf.backdrop:SetAlpha(0)
        end
        if sf.bg then
            sf.bg:Hide()
            sf.bg:SetAlpha(0)
        end
    end

    local sb = TWTalentFrameScrollFrameScrollBar
    if sb then
        sb:Hide()
        sb:SetAlpha(0)
        sb:EnableMouse(false)
        sb:ClearAllPoints()
        sb:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 2000, -2000)

        if sb.bg then
            sb.bg:Hide()
            sb.bg:SetAlpha(0)
            sb.bg:ClearAllPoints()
            sb.bg:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 2000, -2000)
            if sb.bg.backdrop then
                sb.bg.backdrop:Hide()
                sb.bg.backdrop:SetAlpha(0)
                sb.bg.backdrop:ClearAllPoints()
                sb.bg.backdrop:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 2000, -2000)
            end
        end
        if sb.backdrop then
            sb.backdrop:Hide()
            sb.backdrop:SetAlpha(0)
            sb.backdrop:ClearAllPoints()
            sb.backdrop:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 2000, -2000)
        end
        if sb.thumb then
            sb.thumb:Hide()
            sb.thumb:SetAlpha(0)
        end

        local up = _G["TWTalentFrameScrollFrameScrollBarScrollUpButton"]
        local down = _G["TWTalentFrameScrollFrameScrollBarScrollDownButton"]
        if up then
            up:Hide()
            up:SetAlpha(0)
            up:ClearAllPoints()
            up:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 2000, -2000)
            if up.backdrop then up.backdrop:Hide(); up.backdrop:SetAlpha(0) end
        end
        if down then
            down:Hide()
            down:SetAlpha(0)
            down:ClearAllPoints()
            down:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 2000, -2000)
            if down.backdrop then down.backdrop:Hide(); down.backdrop:SetAlpha(0) end
        end
    end

    -- Keep Blizzard's default tabs hidden
    for i = 1, 3 do
        local bTab = _G["TWTalentFrameTab" .. i]
        if bTab then
            bTab:SetAlpha(0)
            bTab:EnableMouse(false)
        end
    end

    self:SyncSpecTabLabels()
    tw:Show()
end

-- =========================================================================
-- BOTTOM TABS ([Character] [Honor] [Talents])
-- Elevated to FULLSCREEN_DIALOG strata so nothing can ever draw over them
-- =========================================================================
local function CreateBottomTab(id, name, width, label)
    local tab = CreateFrame("Button", "zInspectTab_" .. id, f)
    tab:SetWidth(width)
    tab:SetHeight(20)
    tab:SetBackdrop(flatBackdrop)
    tab:SetBackdropColor(0.10, 0.10, 0.10, 1)
    tab:SetBackdropBorderColor(0.20, 0.20, 0.20, 1)
    tab:SetFrameStrata("FULLSCREEN_DIALOG")
    tab:SetFrameLevel(50)

    local txt = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    txt:SetPoint("CENTER", tab, "CENTER", 0, 0)
    txt:SetText(label)
    txt:SetTextColor(0.6, 0.6, 0.6)
    tab.text = txt
    tab.tabId = id

    tab:SetScript("OnClick", function()
        zInspect:SetTab(this.tabId)
    end)
    tab:SetScript("OnEnter", function()
        if zInspect.currentTab ~= this.tabId then
            this:SetBackdropColor(0.18, 0.18, 0.18, 1)
        end
    end)
    tab:SetScript("OnLeave", function()
        if zInspect.currentTab ~= this.tabId then
            this:SetBackdropColor(0.10, 0.10, 0.10, 1)
        end
    end)

    zInspect.tabs[id] = tab
    return tab
end

local tabChar   = CreateBottomTab("character", "Character", 68, "Character")
local tabHonor  = CreateBottomTab("honor",     "Honor",     52, "Honor")
local tabTalent = CreateBottomTab("talents",   "Talents",   56, "Talents")

tabChar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 7)
tabHonor:SetPoint("LEFT", tabChar, "RIGHT", 3, 0)
tabTalent:SetPoint("LEFT", tabHonor, "RIGHT", 3, 0)

-- Switch Tab Implementation
function zInspect:SetTab(tabId)
    self.currentTab = tabId

    -- Highlight active tab
    for id, btn in pairs(self.tabs) do
        if id == tabId then
            btn:SetBackdropColor(0.20, 0.20, 0.20, 1)
            btn:SetBackdropBorderColor(0.40, 0.40, 0.40, 1)
            btn.text:SetTextColor(1.0, 0.82, 0.0)
        else
            btn:SetBackdropColor(0.10, 0.10, 0.10, 1)
            btn:SetBackdropBorderColor(0.20, 0.20, 0.20, 1)
            btn.text:SetTextColor(0.6, 0.6, 0.6)
        end
    end

    if tabId == "character" then
        f:SetBackdropColor(0.07, 0.07, 0.07, 0.96)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        for i = 1, 3 do self.specTabs[i]:Hide() end
        if InspectHonorFrame then InspectHonorFrame:Hide() end
        if TWTalentFrame then TWTalentFrame:Hide() end

        if self.isTargetNPC then
            modelContainer:Show()
            self:SetGearSlotsVisible(false)
            npcPanel:Show()
            statsText:SetText("")
        else
            modelContainer:Show()
            self:SetGearSlotsVisible(true)
            npcPanel:Hide()
            self:UpdateSlots(self.currentUnit or "target")
        end
        if guildText:GetText() and guildText:GetText() ~= "" then
            guildText:Show()
        end

    elseif tabId == "honor" then
        f:SetBackdropColor(0.07, 0.07, 0.07, 0.96)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        for i = 1, 3 do self.specTabs[i]:Hide() end
        modelContainer:Hide()
        self:SetGearSlotsVisible(false)
        npcPanel:Hide()
        if TWTalentFrame then TWTalentFrame:Hide() end
        statsText:SetText("")
        self:UpdateHonorTab()

    elseif tabId == "talents" then
        f:SetBackdropColor(0.07, 0.07, 0.07, 0.96)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        modelContainer:Hide()
        self:SetGearSlotsVisible(false)
        npcPanel:Hide()
        if InspectHonorFrame then InspectHonorFrame:Hide() end
        statsText:SetText("")
        guildText:Hide()
        for i = 1, 3 do self.specTabs[i]:Show() end
        self:UpdateTalentsTab()
    end
end

-- Format Honor Frame cleanly inside zInspectFrame and prevent it from blocking tabs
function zInspect:FormatHonorFrame()
    local hf = InspectHonorFrame
    if not hf then return end

    hf:SetParent(f)
    if hf.SetToplevel then
        hf:SetToplevel(false)
    end
    hf:EnableMouse(false)
    hf:SetFrameStrata("DIALOG")
    hf:SetFrameLevel(f:GetFrameLevel() + 1)

    -- In XML InspectHonorFrame used setAllPoints="true" without explicit size.
    -- We must assign 384x480 canvas size so centered text and bars calculate geometry correctly.
    hf:SetWidth(384)
    hf:SetHeight(480)
    hf:SetScale(0.85)
    hf:ClearAllPoints()
    hf:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -20)

    hf:Show()
end

-- Update Honor Tab (Cleanly mounts InspectHonorFrame inside zInspectFrame)
function zInspect:UpdateHonorTab()
    if not IsAddOnLoaded("Blizzard_InspectUI") then
        UIParentLoadAddOn("Blizzard_InspectUI")
    end

    local unit = self.currentUnit or "target"
    if InspectFrame then
        InspectFrame.unit = unit
        InspectFrame:Hide()
    end

    self:FormatHonorFrame()

    -- Request data from server if not already cached
    if RequestInspectHonorData then
        RequestInspectHonorData()
    end

    if InspectHonorFrame_Update then
        pcall(InspectHonorFrame_Update)
    end
end

-- Update Talents Tab
function zInspect:UpdateTalentsTab()
    if not IsAddOnLoaded("Blizzard_TalentUI") then
        LoadAddOn("Blizzard_TalentUI")
    end
    if not IsAddOnLoaded("Blizzard_InspectUI") then
        UIParentLoadAddOn("Blizzard_InspectUI")
    end

    if InspectFrame then
        InspectFrame.unit = self.currentUnit or "target"
        InspectFrame:Hide()
    end

    EnsureTalentsClass()

    -- Only send network inspect request if target is a valid player and not self
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("player", "target") and UnitName("target") then
        zInspect.suppressInspectFrame = true
        if InspectTalentsFrame_OnShow then
            pcall(InspectTalentsFrame_OnShow)
        elseif InspectFrameTalentsTab_OnClick then
            pcall(InspectFrameTalentsTab_OnClick)
        end
        if InspectFrame then InspectFrame:Hide() end
        zInspect.suppressInspectFrame = false
    end

    -- Format geometry and select the spec
    self:FormatTalentsFrame()
    self:SelectTalentSpec(self.currentTalentSpec or 1)
end

-- Clear / Reset all gear slot displays
function zInspect:ClearSlots()
    for id, btn in pairs(slotButtons) do
        btn.itemLink = nil
        btn.count:SetText("")
        local _, emptyTexture = GetInventorySlotInfo(btn.slotDef.name)
        if emptyTexture then
            btn.icon:SetTexture(emptyTexture)
            btn.icon:SetAlpha(0.28)
            btn.icon:SetVertexColor(1, 1, 1)
        else
            btn.icon:SetTexture(nil)
        end
        btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 0.9)
    end
    statsText:SetText("")
end

-- Parse item quality from link
local function GetQualityFromLink(link)
    if not link then return nil end
    local _, _, color = string.find(link, "|c(%x+)|H")
    if not color then return nil end
    color = string.lower(color)
    if color == "ff9d9d9d" then return 0 -- Poor
    elseif color == "ffffffff" then return 1 -- Common
    elseif color == "ff1eff00" then return 2 -- Uncommon
    elseif color == "ff0070dd" then return 3 -- Rare
    elseif color == "ffa335ee" then return 4 -- Epic
    elseif color == "ffff8000" then return 5 -- Legendary
    elseif color == "ffe6cc80" then return 6 -- Artifact
    end
    return 1
end

-- Robust item resolver that cleanly extracts texture, link, quality, and iLevel
local function ResolveItemData(unit, slotId)
    local texture, link, count, quality, itemLevel
    count = 1

    -- 1. Friendly / live target: try standard inspection API
    if unit and not zInspect.isTargetEnemy and not zInspect.isWaitingForRange then
        texture = GetInventoryItemTexture(unit, slotId)
        link = GetInventoryItemLink(unit, slotId)
        count = GetInventoryItemCount(unit, slotId) or 1
    end

    -- 2. If missing or enemy target: check GetInventoryItemID or zAPI visible items
    local itemID = nil
    if (not texture or not link) and unit then
        if GetInventoryItemID then
            itemID = GetInventoryItemID(unit, slotId)
        end
        if (not itemID or itemID == 0) and zAPI then
            local ok, res = pcall(zAPI, "unitVisibleItem", unit, slotId)
            if ok and res and res > 0 then itemID = res end
        end
    end

    -- 3. Resolve item info from itemID
    if itemID and itemID > 0 then
        local rawInfo = { GetItemInfo(itemID) }
        if rawInfo and table.getn(rawInfo) > 0 then
            link = rawInfo[2] or ("item:" .. itemID .. ":0:0:0")
            quality = rawInfo[3]
            itemLevel = rawInfo[4]

            -- In Vanilla 1.12, texture is index 9 (or scan for Interface\ path)
            for idx = 1, table.getn(rawInfo) do
                local val = rawInfo[idx]
                if type(val) == "string" and string.find(val, "^Interface\\") then
                    texture = val
                    break
                end
            end
        end

        -- If item is not in local client cache yet, query tooltip to force cache fetch
        if not texture or not link then
            scannerTooltip:SetHyperlink("item:" .. itemID .. ":0:0:0")
            link = link or ("item:" .. itemID .. ":0:0:0")
        end
    end

    -- Safety check: texture MUST be a valid string to prevent solid red textures
    if type(texture) ~= "string" or texture == "" or not string.find(texture, "^Interface\\") then
        texture = nil
    end

    return texture, link, count, quality, itemLevel
end

-- Update Gear Slots from live unit, cache, or cross-faction visible items
function zInspect:UpdateSlots(unit)
    if not unit or not UnitExists(unit) then return 0, false end
    local hasCachedData = false
    local unitName = UnitName(unit)
    local cachedUnit = unitName and self.cache[unitName]
    local itemsFound = 0
    local totalItemLevel = 0
    local itemsWithLevel = 0

    for id, btn in pairs(slotButtons) do
        local texture, link, count, quality, itemLevel = ResolveItemData(unit, id)

        -- If live info is missing, try session cache
        if not texture and cachedUnit and cachedUnit.items and cachedUnit.items[id] then
            texture = cachedUnit.items[id].texture
            link = cachedUnit.items[id].link
            count = cachedUnit.items[id].count or 1
            quality = cachedUnit.items[id].quality
            itemLevel = cachedUnit.items[id].itemLevel
            hasCachedData = true
        end

        if texture or link then
            itemsFound = itemsFound + 1
            btn.itemLink = link

            -- Set icon texture safely (only valid Interface\ string)
            if type(texture) == "string" and texture ~= "" then
                btn.icon:SetTexture(texture)
                btn.icon:SetAlpha(1.0)
                btn.icon:SetVertexColor(1, 1, 1)
            else
                -- Fallback icon if texture still loading into client cache
                btn.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                btn.icon:SetAlpha(0.8)
                btn.icon:SetVertexColor(0.9, 0.9, 0.9)
            end

            if count and count > 1 then
                btn.count:SetText(count)
            else
                btn.count:SetText("")
            end

            -- Determine quality
            if not quality and link then
                quality = GetQualityFromLink(link)
            end

            -- Border color by item quality
            if quality and GetItemQualityColor then
                local r, g, b = GetItemQualityColor(quality)
                btn:SetBackdropBorderColor(r, g, b, 1)
            else
                btn:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
            end

            -- Average Item Level calculation if available
            if not itemLevel and link and GetItemInfo then
                local _, _, _, ilvl = GetItemInfo(link)
                itemLevel = ilvl
            end
            if itemLevel and itemLevel > 0 then
                totalItemLevel = totalItemLevel + itemLevel
                itemsWithLevel = itemsWithLevel + 1
            end

            -- Save to session cache
            if unitName and link then
                self.cache[unitName] = self.cache[unitName] or { items = {} }
                self.cache[unitName].items[id] = {
                    texture = texture,
                    link = link,
                    count = count,
                    quality = quality,
                    itemLevel = itemLevel,
                }
            end
        else
            btn.itemLink = nil
            btn.count:SetText("")
            local _, emptyTexture = GetInventorySlotInfo(btn.slotDef.name)
            if emptyTexture then
                btn.icon:SetTexture(emptyTexture)
                btn.icon:SetAlpha(0.28)
                btn.icon:SetVertexColor(1, 1, 1)
            else
                btn.icon:SetTexture(nil)
            end
            btn:SetBackdropBorderColor(0.22, 0.22, 0.22, 0.9)
        end
    end

    if self.currentTab == "character" and not self.isTargetNPC then
        if itemsWithLevel > 0 then
            local avgIlvl = math.floor((totalItemLevel / itemsWithLevel) * 10) / 10
            statsText:SetText(string.format("|cff33ffccAvg iLvl:|r %.1f (%d items)", avgIlvl, itemsFound))
        elseif itemsFound > 0 then
            statsText:SetText(string.format("|cff33ffccGear:|r %d items", itemsFound))
        else
            statsText:SetText("")
        end
    else
        statsText:SetText("")
    end

    return itemsFound, hasCachedData
end

-- Show / Hide Gear Slots (used when inspecting NPCs/creatures)
function zInspect:SetGearSlotsVisible(visible)
    for _, btn in pairs(slotButtons) do
        if visible then
            btn:Show()
        else
            btn:Hide()
        end
    end
end

-- Refresh Unit Identity, Model, and Metadata
function zInspect:InspectUnit(unit)
    if not UnitExists(unit) then return end

    self.currentUnit = unit
    self.currentUnitName = UnitName(unit)
    self.isTargetPlayer = UnitIsPlayer(unit)
    self.isTargetEnemy = UnitIsEnemy("player", unit)
    self.isTargetNPC = not self.isTargetPlayer

    f:Show()

    -- Reset to Character tab on fresh inspect
    self:SetTab("character")

    -- Render 3D Model immediately for any target
    model:ClearModel()
    model:SetUnit(unit)
    self:ResetModelView()

    -- Basic unit identity
    local name = UnitName(unit) or "Unknown"
    local level = UnitLevel(unit) or 0
    local race = UnitRace(unit) or ""
    local class, classFileName = UnitClass(unit)
    local guild, guildRank = GetGuildInfo(unit)

    -- Color name by Class or Reaction
    local nameColor = "|cffffffff"
    if self.isTargetPlayer and classFileName and CLASS_COLORS[classFileName] then
        nameColor = CLASS_COLORS[classFileName].hex
    else
        local reaction = UnitReaction("player", unit)
        if reaction then
            if reaction <= 2 then nameColor = "|cffff3333"      -- Hostile
            elseif reaction <= 4 then nameColor = "|cffffff33"  -- Neutral
            else nameColor = "|cff33ff33"                       -- Friendly
            end
        end
    end
    nameText:SetText(nameColor .. name .. "|r")

    -- Format Level & Subtitle
    local levelStr = (level < 0 or level == 0) and "|cffff0000??|r" or tostring(level)
    local classification = UnitClassification(unit)
    if classification == "worldboss" then
        levelStr = levelStr .. " |cffff0000(Boss)|r"
    elseif classification == "rareelite" then
        levelStr = levelStr .. " |cffffaa00(Rare Elite)|r"
    elseif classification == "elite" then
        levelStr = levelStr .. " |cffffcc00(Elite)|r"
    elseif classification == "rare" then
        levelStr = levelStr .. " |cffffaa00(Rare)|r"
    end

    -- Branch between Player vs NPC / Creature
    if self.isTargetPlayer then
        tabHonor:Show()
        tabTalent:Show()
        npcPanel:Hide()
        self:SetGearSlotsVisible(true)

        local line2 = string.format("Level %s %s %s", levelStr, race or "", class or "")
        infoText:SetText(line2)

        if guild and guild ~= "" then
            guildText:SetText(string.format("<%s> %s", guild, guildRank or ""))
            if self.currentTab == "character" then
                guildText:Show()
            else
                guildText:Hide()
            end
        else
            guildText:SetText("")
            guildText:Hide()
        end

        local isSelf = UnitIsUnit("player", unit)
        local inRange = isSelf or CheckInteractDistance(unit, 1)

        if inRange then
            self.isWaitingForRange = false
            statusBadge:SetText("|cff00ff00Inspected|r")
            if not isSelf and (not self.isTargetEnemy or CanInspect(unit)) then
                NotifyInspect(unit)
                if RequestInspectHonorData then RequestInspectHonorData() end
                self.inspectRequested = true
            end
            self:UpdateSlots(unit)
        else
            -- Out of range! Still show model + bring in info as it comes in
            self.isWaitingForRange = true
            self.inspectRequested = false
            statusBadge:SetText("|cffffaa00Out of Range - Waiting...|r")
            
            -- Display cached gear immediately if we have it
            local itemsFound, hasCached = self:UpdateSlots(unit)
            if hasCached and itemsFound > 0 then
                statusBadge:SetText("|cffffd200Cached (Out of Range)|r")
            end
        end

        if self.isTargetEnemy then
            statusBadge:SetText("|cffff4444Enemy Player|r")
            -- Attempt cross-faction visible items extraction immediately
            self:UpdateSlots(unit)
        end

    else
        -- NPC / Creature / Monster / Boss
        tabHonor:Hide()
        tabTalent:Hide()
        self:SetGearSlotsVisible(false)
        guildText:Hide()
        self.isWaitingForRange = false

        local creatureType = UnitCreatureType(unit) or "Creature"
        local creatureFamily = UnitCreatureFamily(unit)
        local typeDesc = creatureFamily and (creatureType .. " (" .. creatureFamily .. ")") or creatureType

        infoText:SetText(string.format("Level %s %s", levelStr, typeDesc))

        local curHP = UnitHealth(unit)
        local maxHP = UnitHealthMax(unit)
        local curPow = UnitMana(unit)
        local maxPow = UnitManaMax(unit)
        local powerType = UnitPowerType(unit)
        local powName = "Mana"
        if powerType == 1 then powName = "Rage"
        elseif powerType == 2 then powName = "Focus"
        elseif powerType == 3 then powName = "Energy"
        end

        local hpPct = (maxHP and maxHP > 0) and math.floor((curHP / maxHP) * 100) or 0
        npcDetails:SetText(string.format("HP: %d / %d (%d%%)    %s: %d / %d", curHP, maxHP, hpPct, powName, curPow, maxPow))

        local targetOfTarget = UnitName(unit .. "target")
        if targetOfTarget then
            npcTargetText:SetText("|cffffcc00Targeting:|r " .. targetOfTarget)
        else
            npcTargetText:SetText("|cff888888Targeting: None|r")
        end

        npcPanel:Show()
        statusBadge:SetText("|cffff8800Creature / NPC|r")
        statsText:SetText("")
    end
end

-- Toggle Window
function zInspect:Toggle()
    if f:IsShown() and UnitIsUnit("target", self.currentUnit or "") then
        self:Hide()
    else
        if UnitExists("target") then
            self:InspectUnit("target")
        else
            -- Self-inspect if no target is selected
            self:InspectUnit("player")
        end
    end
end

function zInspect:Hide()
    f:Hide()
    f:SetBackdropColor(0.07, 0.07, 0.07, 0.96)
    self.isWaitingForRange = false
    self.currentUnit = nil
    for i = 1, 3 do self.specTabs[i]:Hide() end
    if InspectHonorFrame then InspectHonorFrame:Hide() end
    if TWTalentFrame then TWTalentFrame:Hide() end
end

-- Suppress Blizzard's InspectFrame from popping up while zInspect is active
if InspectFrame then
    InspectFrame:HookScript("OnShow", function()
        if zInspectFrame:IsShown() and not zInspect.allowInspectFrameShow then
            this:Hide()
        end
    end)
end

-- Event Handling Frame
local eventFrame = CreateFrame("Frame", "zInspectEventFrame", UIParent)
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("INSPECT_HONOR_UPDATE")
eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" or event == "PLAYER_ENTERING_WORLD" then
        zInspectDB = zInspectDB or {}
        
        -- Restore saved position
        if zInspectDB.pos then
            f:ClearAllPoints()
            f:SetPoint(zInspectDB.pos.point, UIParent, zInspectDB.pos.point, zInspectDB.pos.x, zInspectDB.pos.y)
        end

        -- Initialize default keybindings to [ and ] if unbound
        if not zInspectDB.initializedBindings then
            local k1, k2 = GetBindingKey("ZINSPECT_TARGET")
            if not k1 and not k2 then
                SetBinding("[", "ZINSPECT_TARGET")
                SetBinding("]", "ZINSPECT_TARGET")
                SaveBindings(GetCurrentBindingSet())
            end
            zInspectDB.initializedBindings = true
        end

        -- Make sure InspectFrame doesn't pop up over zInspect
        if InspectFrame and not zInspect.inspectFrameHooked then
            InspectFrame:HookScript("OnShow", function()
                if zInspectFrame:IsShown() and not zInspect.allowInspectFrameShow then
                    this:Hide()
                end
            end)
            zInspect.inspectFrameHooked = true
        end

    elseif event == "INSPECT_HONOR_UPDATE" then
        if f:IsShown() and zInspect.currentTab == "honor" then
            if InspectHonorFrame_Update then
                pcall(InspectHonorFrame_Update)
            end
        end

    elseif event == "UNIT_INVENTORY_CHANGED" then
        if f:IsShown() and zInspect.currentUnit and UnitExists(zInspect.currentUnit) then
            if zInspect.isTargetPlayer and zInspect.currentTab == "character" then
                local itemsFound = zInspect:UpdateSlots(zInspect.currentUnit)
                if itemsFound and itemsFound > 0 then
                    statusBadge:SetText("|cff00ff00Inspected|r")
                end
            end
        end

    elseif event == "PLAYER_TARGET_CHANGED" then
        -- If window is open and target changes, refresh automatically
        if f:IsShown() and UnitExists("target") then
            zInspect:InspectUnit("target")
        end
    end
end)

-- Polling Watcher: Streams gear the moment an out-of-range player enters range,
-- and periodically refreshes uncached items on enemy targets
f:SetScript("OnUpdate", function()
    if not f:IsShown() then return end

    zInspect.pollTimer = zInspect.pollTimer + arg1
    if zInspect.pollTimer >= 0.25 then
        zInspect.pollTimer = 0

        if zInspect.isWaitingForRange and zInspect.currentUnit and UnitExists(zInspect.currentUnit) then
            if CheckInteractDistance(zInspect.currentUnit, 1) then
                -- Target stepped into range!
                zInspect.isWaitingForRange = false
                statusBadge:SetText("|cff33ffccStreaming gear...|r")
                NotifyInspect(zInspect.currentUnit)
                if RequestInspectHonorData then RequestInspectHonorData() end
                zInspect.inspectRequested = true
                zInspect:UpdateSlots(zInspect.currentUnit)
            end
        elseif zInspect.isTargetEnemy and zInspect.currentTab == "character" then
            -- Refresh uncached items that have now resolved from server/tooltip
            zInspect:UpdateSlots(zInspect.currentUnit)
        end
    end
end)

-- Slash Commands
SLASH_ZINSPECT1 = "/zinspect"
SLASH_ZINSPECT2 = "/zi"
SlashCmdList["ZINSPECT"] = function(msg)
    zInspect:Toggle()
end

-- Welcome message after greeting delay
local greetTimer = CreateFrame("Frame")
greetTimer.elapsed = 0
greetTimer:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed >= 3 then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccz|rInspect loaded. Press |cff33ffcc[|r or |cff33ffcc]|r or type |cff33ffcc/zi|r to inspect.")
        end
        this:Hide()
        this:SetScript("OnUpdate", nil)
    end
end)
