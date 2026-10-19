import unittest
from pathlib import Path

from lupa import LuaRuntime


ADDON_FILE = Path(__file__).resolve().parents[1] / "zInspect.lua"
SLOT_NAMES = (
    "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot",
    "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
    "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot",
    "SecondaryHandSlot", "RangedSlot",
)


WOW_MOCK = r'''
table.getn = table.getn or function(value) return #value end
tinsert = table.insert
SlashCmdList = {}
UISpecialFrames = {}
UIParent = {}
WorldFrame = {}

local function NewWidget(name)
    local widget = {
        _name = name,
        _text = "",
        _shown = true,
        _scripts = {},
        writes = { texture = 0, alpha = 0, vertex = 0, border = 0, text = 0 },
    }

    function widget:SetTexture(value)
        self.texture = value
        self.writes.texture = self.writes.texture + 1
    end
    function widget:SetAlpha(value)
        self.alpha = value
        self.writes.alpha = self.writes.alpha + 1
    end
    function widget:SetVertexColor(r, g, b)
        self.vertexR, self.vertexG, self.vertexB = r, g, b
        self.writes.vertex = self.writes.vertex + 1
    end
    function widget:SetBackdropBorderColor(r, g, b, a)
        self.borderR, self.borderG, self.borderB, self.borderA = r, g, b, a
        self.writes.border = self.writes.border + 1
    end
    function widget:SetText(value)
        self._text = value
        self.writes.text = self.writes.text + 1
    end
    function widget:GetText() return self._text end
    function widget:SetScript(event, handler) self._scripts[event] = handler end
    function widget:CreateTexture(childName) return NewWidget(childName) end
    function widget:CreateFontString(childName)
        local child = NewWidget(childName)
        if childName then _G[childName] = child end
        return child
    end
    function widget:GetFrameLevel() return 1 end
    function widget:GetEffectiveScale() return 1 end
    function widget:GetScale() return 1 end
    function widget:GetWidth() return 300 end
    function widget:GetHeight() return 300 end
    function widget:GetName() return self._name end
    function widget:IsShown() return self._shown end
    function widget:IsVisible() return self._shown end
    function widget:Show() self._shown = true end
    function widget:Hide() self._shown = false end

    setmetatable(widget, { __index = function() return function() end end })
    return widget
end

function CreateFrame(_, name)
    local frame = NewWidget(name)
    if name then _G[name] = frame end
    return frame
end

local slotIDs = {
    HeadSlot=1, NeckSlot=2, ShoulderSlot=3, ShirtSlot=4, ChestSlot=5, WaistSlot=6,
    LegsSlot=7, FeetSlot=8, WristSlot=9, HandsSlot=10, Finger0Slot=11, Finger1Slot=12,
    Trinket0Slot=13, Trinket1Slot=14, BackSlot=15, MainHandSlot=16,
    SecondaryHandSlot=17, RangedSlot=18, TabardSlot=19,
}
function GetInventorySlotInfo(name)
    return slotIDs[name], "Interface\\PaperDoll\\Empty-" .. name
end

TEST_UNITS = {
    target = { name = "Alpha", items = {} },
    other = { name = "Beta", items = {} },
}
TEST_ITEM_INFO = {}
QUERY_COUNTS = { texture = 0, link = 0, count = 0, id = 0 }

function UnitExists(unit) return TEST_UNITS[unit] ~= nil end
function UnitName(unit) return TEST_UNITS[unit] and TEST_UNITS[unit].name end
function GetInventoryItemTexture(unit, slot)
    QUERY_COUNTS.texture = QUERY_COUNTS.texture + 1
    local item = TEST_UNITS[unit] and TEST_UNITS[unit].items[slot]
    return item and item.texture
end
function GetInventoryItemLink(unit, slot)
    QUERY_COUNTS.link = QUERY_COUNTS.link + 1
    local item = TEST_UNITS[unit] and TEST_UNITS[unit].items[slot]
    return item and item.link
end
function GetInventoryItemCount(unit, slot)
    QUERY_COUNTS.count = QUERY_COUNTS.count + 1
    local item = TEST_UNITS[unit] and TEST_UNITS[unit].items[slot]
    return item and item.count
end
function GetInventoryItemID(unit, slot)
    QUERY_COUNTS.id = QUERY_COUNTS.id + 1
    local item = TEST_UNITS[unit] and TEST_UNITS[unit].items[slot]
    return item and item.id
end
function GetItemInfo(value)
    local id = tonumber(value) or tonumber(string.match(value or "", "item:(%d+)"))
    local item = TEST_ITEM_INFO[id]
    if not item then return nil end
    return item.name, item.link, item.quality, item.itemLevel, nil, nil, nil, nil, item.texture
end
function GetItemQualityColor(quality)
    return quality / 10, quality / 20, quality / 30
end

GameTooltip = NewWidget("GameTooltip")
DEFAULT_CHAT_FRAME = NewWidget("DEFAULT_CHAT_FRAME")

function ResetQueryCounts()
    for key in pairs(QUERY_COUNTS) do QUERY_COUNTS[key] = 0 end
end
function ResetWidgetWrites(widget)
    for key in pairs(widget.writes) do widget.writes[key] = 0 end
end
function ResetGearWrites()
    local names = {
        "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "ShirtSlot",
        "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot",
        "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot", "MainHandSlot",
        "SecondaryHandSlot", "RangedSlot",
    }
    for _, name in ipairs(names) do
        local button = _G["zInspectSlot_" .. name]
        ResetWidgetWrites(button)
        ResetWidgetWrites(button.icon)
        ResetWidgetWrites(button.count)
    end
    ResetWidgetWrites(zInspectStatsText)
end
function TotalGearWrites()
    local total = zInspectStatsText.writes.text
    for name, id in pairs(slotIDs) do
        if id >= 1 and id <= 19 then
            local button = _G["zInspectSlot_" .. name]
            total = total + button.writes.border + button.icon.writes.texture
                + button.icon.writes.alpha + button.icon.writes.vertex + button.count.writes.text
        end
    end
    return total
end
'''


def lua_item(item_id, name, texture, quality=3, item_level=60, count=1):
    color = {0: "ff9d9d9d", 1: "ffffffff", 2: "ff1eff00", 3: "ff0070dd", 4: "ffa335ee"}[quality]
    link = f"|c{color}|Hitem:{item_id}:0:0:0|h[{name}]|h|r"
    return {
        "id": item_id,
        "name": name,
        "texture": texture,
        "quality": quality,
        "itemLevel": item_level,
        "count": count,
        "link": link,
    }


class UpdateSlotsTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(WOW_MOCK)
        self.lua.execute(ADDON_FILE.read_text(encoding="utf-8"))
        self.g = self.lua.globals()
        self.addon = self.g.zInspect
        self.addon.currentTab = "character"
        self.addon.isTargetNPC = False
        self.addon.isTargetEnemy = False
        self.addon.isWaitingForRange = False

    def install_item(self, unit, slot, item):
        fields = ",".join(
            f"{key}={value!r}" if isinstance(value, (int, float)) else f"{key}={value!r}"
            for key, value in item.items()
        )
        # repr() uses compatible quoted strings for these controlled fixtures.
        self.lua.execute(f"TEST_ITEM_INFO[{item['id']}]={{{fields}}}")
        self.lua.execute(f"TEST_UNITS.{unit}.items[{slot}]={{{fields}}}")

    def slot(self, name="MainHandSlot"):
        return self.g[f"zInspectSlot_{name}"]

    def update(self, unit="target", live_update_confirmed=False):
        return self.addon.UpdateSlots(self.addon, unit, live_update_confirmed)

    def reset_writes(self):
        self.g.ResetGearWrites()

    def test_unchanged_polls_skip_writes_reuse_records_and_keep_queries_fresh(self):
        item = lua_item(100, "First Blade", "Interface\\Icons\\INV_Sword_01", count=2)
        self.install_item("target", 16, item)
        self.update()
        self.lua.execute("FIRST_RECORD = zInspect.cache.Alpha.items[16]")

        self.reset_writes()
        self.g.ResetQueryCounts()
        self.update()

        self.assertEqual(self.g.TotalGearWrites(), 0)
        self.assertEqual(self.g.QUERY_COUNTS.texture, 19)
        self.assertEqual(self.g.QUERY_COUNTS.link, 19)
        self.assertEqual(self.g.QUERY_COUNTS.count, 19)
        self.assertTrue(self.lua.eval("FIRST_RECORD == zInspect.cache.Alpha.items[16]"))

    def test_item_swap_removal_and_quality_count_changes(self):
        first = lua_item(100, "First Blade", "Interface\\Icons\\INV_Sword_01", quality=3, count=1)
        second = lua_item(101, "Second Blade", "Interface\\Icons\\INV_Sword_02", quality=4, count=4)
        self.install_item("target", 16, first)
        self.update()

        self.reset_writes()
        self.install_item("target", 16, second)
        self.update()
        button = self.slot()
        self.assertEqual(button.icon.texture, second["texture"])
        self.assertEqual(button.count._text, 4)
        self.assertGreater(button.icon.writes.texture, 0)
        self.assertGreater(button.count.writes.text, 0)
        self.assertGreater(button.writes.border, 0)

        self.reset_writes()
        self.lua.execute("TEST_UNITS.target.items[16] = nil")
        self.update(live_update_confirmed=True)
        self.assertEqual(button.icon.texture, "Interface\\PaperDoll\\Empty-MainHandSlot")
        self.assertEqual(button.count._text, "")
        self.assertIsNone(self.lua.eval("rawget(zInspectSlot_MainHandSlot, 'itemLink')"))
        self.assertTrue(self.lua.eval("zInspect.cache.Alpha.items[16].link == nil"))

    def test_cache_only_and_incomplete_data_becoming_live(self):
        cached = lua_item(102, "Cached Blade", "Interface\\Icons\\INV_Sword_03")
        self.install_item("target", 16, cached)
        self.update()

        self.addon.isWaitingForRange = True
        self.lua.execute("TEST_UNITS.target.items[16] = nil")
        self.reset_writes()
        items_found, has_cached = self.update()
        self.assertEqual(items_found, 1)
        self.assertTrue(has_cached)
        self.assertEqual(self.slot().icon.texture, cached["texture"])
        self.assertEqual(self.g.TotalGearWrites(), 0)

        self.addon.isWaitingForRange = False
        self.addon.ClearSlots(self.addon)
        incomplete = lua_item(103, "Loading Blade", "Interface\\Icons\\INV_Sword_04")
        self.install_item("target", 16, incomplete)
        self.lua.execute("TEST_UNITS.target.items[16].texture=nil; TEST_UNITS.target.items[16].id=nil")
        self.update()
        self.assertEqual(self.slot().icon.texture, "Interface\\Icons\\INV_Misc_QuestionMark")

        self.lua.execute("TEST_UNITS.target.items[16].texture='Interface\\\\Icons\\\\INV_Sword_04'")
        self.reset_writes()
        self.update()
        self.assertEqual(self.slot().icon.texture, incomplete["texture"])
        self.assertGreater(self.slot().icon.writes.texture, 0)

    def test_clear_then_identical_gear_and_target_switching(self):
        alpha = lua_item(104, "Alpha Blade", "Interface\\Icons\\INV_Sword_05")
        beta = lua_item(105, "Beta Blade", "Interface\\Icons\\INV_Sword_06", quality=2)
        self.install_item("target", 16, alpha)
        self.install_item("other", 16, beta)
        self.update("target")

        self.addon.ClearSlots(self.addon)
        self.reset_writes()
        self.update("target")
        self.assertEqual(self.slot().icon.texture, alpha["texture"])
        self.assertGreater(self.g.TotalGearWrites(), 0)

        self.reset_writes()
        self.update("other")
        self.assertEqual(self.slot().icon.texture, beta["texture"])
        self.assertGreater(self.slot().icon.writes.texture, 0)
        self.assertTrue(self.lua.eval("zInspect.cache.Alpha.items[16] ~= zInspect.cache.Beta.items[16]"))


if __name__ == "__main__":
    unittest.main()
