import unittest

from lupa.lua51 import LuaRuntime

from test_update_slots import ADDON_FILE, WOW_MOCK


TRANSMOG_MOCK = r'''
TEST_UNITS.player = { name = "Me", items = {} }
function UnitIsPlayer(unit) return UnitExists(unit) end
function UnitIsUnit(first, second)
    return UnitName(first) ~= nil and UnitName(first) == UnitName(second)
end
SENT_MESSAGES = {}
function SendAddonMessage(prefix, message, channel)
    table.insert(SENT_MESSAGES, { prefix = prefix, message = message, channel = channel })
end
LOADED_ADDONS = {}
function IsAddOnLoaded(name) return LOADED_ADDONS[name] == true end
function UIParentLoadAddOn(name) LOADED_ADDONS[name] = true end
InspectFrame = CreateFrame("Frame", "InspectFrame", UIParent)
INSPECT_TRANSMOG_DATA = {
    [16] = { frame = "InspectMainHandSlot", transmogID = nil, equipID = nil },
}
TRANSMOG_CHANGED_TO = "Transmogrified to:"
ADDON_MSG_FIELD_DELIMITER = ";"
GameTooltip:CreateFontString("GameTooltipTextLeft2")
LIVE_CALLS, LINK_CALLS = 0, 0
function GameTooltip:SetOwner(owner) self.owner = owner end
function GameTooltip:IsOwned(owner) return self.owner == owner end
function GameTooltip:SetInventoryItem(unit, slot)
    LIVE_CALLS = LIVE_CALLS + 1
    local item = TEST_UNITS[unit] and TEST_UNITS[unit].items[slot]
    if FORCE_LIVE_UNAVAILABLE or not item or not item.link then return false end
    self.itemLink = item.link
    GameTooltipTextLeft2:SetText("Binds when picked up")
    return true
end
function GameTooltip:SetHyperlink(link)
    LINK_CALLS = LINK_CALLS + 1
    self.itemLink = link
    GameTooltipTextLeft2:SetText("Binds when picked up")
end
zInspectFrame:Show()
zInspect.currentUnit = "target"
zInspect.currentUnitName = "Alpha"
zInspect.currentTab = "character"
zInspect.isTargetPlayer = true
TEST_ITEM_INFO[100] = { name = "Base Sword", link = "item:100:0:0:0", texture = "Interface\\Icons\\Sword", quality = 3, itemLevel = 60 }
TEST_ITEM_INFO[200] = { name = "Hatchet Appearance", link = "item:200:0:0:0", texture = "Interface\\Icons\\Axe", quality = 3 }
TEST_UNITS.target.items[16] = TEST_ITEM_INFO[100]
zInspect:UpdateSlots("target")
'''


class TransmogTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(WOW_MOCK)
        self.lua.execute(ADDON_FILE.read_text(encoding="utf-8"))
        self.lua.execute(TRANSMOG_MOCK)
        self.g = self.lua.globals()
        self.addon = self.g.zInspect
        self.button = self.g.zInspectSlot_MainHandSlot

    def start(self):
        self.addon.StartTransmogInspect(self.addon, "target")

    def reply(self, message, sender="Alpha", prefix="TW_CHAT_MSG_WHISPER"):
        self.addon.HandleTransmogMessage(self.addon, prefix, message, sender)

    def show(self):
        self.addon.ShowSlotTooltip(self.addon, self.button)
        return self.g.GameTooltipTextLeft2.GetText(self.g.GameTooltipTextLeft2)

    def test_native_request_and_reply_draw_on_custom_slot(self):
        self.start()
        sent = self.g.SENT_MESSAGES[1]
        self.assertTrue(self.g.LOADED_ADDONS["Blizzard_InspectUI"])
        self.assertEqual(self.g.InspectFrame.unit, "target")
        self.assertFalse(self.g.InspectFrame.IsShown(self.g.InspectFrame))
        self.assertEqual(sent.prefix, "TW_CHAT_MSG_WHISPER<Alpha>")
        self.assertEqual(sent.message, "INSShowTransmogs")
        self.assertEqual(sent.channel, "GUILD")
        self.reply("INSTransmogs;start;0;0")
        self.reply("INSTransmogs;16;200;100")
        text = self.show()
        self.assertEqual(text, "|cfff471f5Transmogrified to:\nHatchet Appearance|r\nBinds when picked up")
        self.assertEqual(self.g.LIVE_CALLS, 1)
        self.assertEqual(self.g.LINK_CALLS, 0)
        self.assertEqual(self.show().count("Transmogrified to:"), 1)

    def test_native_reply_cache_is_used_when_addon_event_order_skips_local_handler(self):
        self.start()
        self.assertNotIn("Transmogrified", self.show())
        self.assertTrue(self.lua.eval("zInspect.transmogTooltipPending == zInspectSlot_MainHandSlot"))
        self.lua.execute("INSPECT_TRANSMOG_DATA[16].transmogID=200; INSPECT_TRANSMOG_DATA[16].equipID=100")
        self.addon.UpdateTransmogInspect(self.addon, 0.25)
        self.assertIn("Hatchet Appearance", self.g.GameTooltipTextLeft2._text)
        self.assertIsNone(self.addon.transmogTooltipPending)

    def test_other_senders_malformed_messages_and_target_switch_do_not_leak(self):
        self.start()
        self.reply("INSTransmogs;16;200;100")
        self.reply("INSTransmogs;start;0;0", "Stranger")
        self.assertIn("Hatchet Appearance", self.show())
        self.reply("INSTransmogs;16;200;100", prefix="UNRELATED")
        self.reply("INSTransmogs;16;garbage;100")
        self.assertIn("Hatchet Appearance", self.show())
        self.lua.execute('zInspect.currentUnit="other"; zInspect.currentUnitName="Beta"; TEST_UNITS.other.items[16]=TEST_ITEM_INFO[100]')
        self.addon.StartTransmogInspect(self.addon, "other")
        self.reply("INSTransmogs;16;200;100", "Alpha")
        self.assertNotIn("Transmogrified", self.show())
        self.reply("INSTransmogs;16;200;100", "Beta")
        self.assertIn("Hatchet Appearance", self.show())

    def test_remote_visible_id_mismatch_start_and_zero_clear_appearance(self):
        self.start()
        self.reply("INSTransmogs;16;200;999")
        # OctoWoW may expose the visible appearance ID in the remote item link;
        # its native tooltip therefore trusts the target-scoped slot packet.
        self.assertIn("Hatchet Appearance", self.show())
        self.reply("INSTransmogs;16;200;100")
        self.assertIn("Hatchet Appearance", self.show())
        self.reply("INSTransmogs;start;0;0")
        self.assertNotIn("Transmogrified", self.show())
        self.reply("INSTransmogs;16;200;100")
        self.reply("INSTransmogs;16;0;100")
        self.assertNotIn("Transmogrified", self.show())

    def test_async_reply_and_late_item_name_refresh_hovered_tooltip(self):
        self.start()
        self.assertNotIn("Transmogrified", self.show())
        self.lua.execute("TEST_ITEM_INFO[200]=nil")
        self.reply("INSTransmogs;16;200;100")
        self.assertEqual(self.g.zInspectScannerTooltip.writes.texture, 0)
        self.assertTrue(self.lua.eval("zInspect.transmogTooltipPending == zInspectSlot_MainHandSlot"))
        self.lua.execute('TEST_ITEM_INFO[200]={name="Hatchet Appearance"}')
        self.addon.UpdateTransmogInspect(self.addon, 0.25)
        self.assertIn("Hatchet Appearance", self.g.GameTooltipTextLeft2._text)
        self.assertIsNone(self.addon.transmogTooltipPending)

    def test_live_inventory_is_authoritative_and_link_fallback_keeps_transmog(self):
        self.start()
        self.reply("INSTransmogs;16;200;100")
        self.lua.execute('zInspectSlot_MainHandSlot.itemLink="item:999:0:0:0"; zInspect.isTargetEnemy=true; zInspect.isWaitingForRange=true')
        self.assertIn("Hatchet Appearance", self.show())
        self.assertEqual(self.g.LINK_CALLS, 0)
        self.lua.execute('FORCE_LIVE_UNAVAILABLE=true; zInspectSlot_MainHandSlot.itemLink="item:100:0:0:0"')
        self.assertIn("Hatchet Appearance", self.show())
        self.assertEqual(self.g.LINK_CALLS, 1)

    def test_self_uses_native_status_without_peer_request(self):
        self.lua.execute('zInspect.currentUnit="player"; zInspect.currentUnitName="Me"; TEST_UNITS.player.items[16]=TEST_ITEM_INFO[100]; TransmogStatus={[100]=200}')
        self.addon.StartTransmogInspect(self.addon, "player")
        self.assertEqual(self.lua.eval("#SENT_MESSAGES"), 0)
        self.assertIn("Hatchet Appearance", self.show())
        self.lua.execute("TransmogStatus[100]=nil")
        self.assertNotIn("Transmogrified", self.show())

    def test_bounded_retries_and_inventory_debounce(self):
        self.start()
        for _ in range(20):
            self.addon.UpdateTransmogInspect(self.addon, 1.5)
        self.assertEqual(self.lua.eval("#SENT_MESSAGES"), 3)
        self.reply("INSTransmogs;start;0;0")
        self.addon.ScheduleTransmogRefresh(self.addon)
        self.addon.UpdateTransmogInspect(self.addon, 1)
        self.assertEqual(self.lua.eval("#SENT_MESSAGES"), 3)
        self.addon.UpdateTransmogInspect(self.addon, 0.5)
        self.assertEqual(self.lua.eval("#SENT_MESSAGES"), 4)
        self.reply("INSTransmogs;start;0;0")
        self.addon.UpdateTransmogInspect(self.addon, 10)
        self.assertEqual(self.lua.eval("#SENT_MESSAGES"), 4)

    def test_main_addon_event_routes_reply(self):
        self.start()
        self.show()
        self.lua.execute('event="CHAT_MSG_ADDON"; arg1="TW_CHAT_MSG_WHISPER"; arg2="INSTransmogs;16;200;100"; arg4="Alpha"; zInspectEventFrame._scripts.OnEvent()')
        self.assertIn("Hatchet Appearance", self.g.GameTooltipTextLeft2._text)

    def test_opening_inspect_requests_appearance_without_default_window(self):
        self.lua.execute('''
            function UnitIsEnemy() return false end
            function UnitLevel() return 60 end
            function UnitRace() return "Human" end
            function UnitClass() return "Warrior", "WARRIOR" end
            function GetGuildInfo() return nil end
            function UnitClassification() return "normal" end
            function CheckInteractDistance() return true end
            function NotifyInspect() NOTIFIED_INSPECT=true end
        ''')
        self.addon.InspectUnit(self.addon, "target")
        self.assertEqual(self.g.SENT_MESSAGES[1].message, "INSShowTransmogs")
        self.assertTrue(self.g.NOTIFIED_INSPECT)
        self.reply("INSTransmogs;16;200;100")
        self.assertIn("Hatchet Appearance", self.show())

    def test_hidden_view_rejects_packets_and_abandoned_hover_stops_name_polling(self):
        self.start()
        self.show()
        self.lua.execute("TEST_ITEM_INFO[200]=nil")
        self.reply("INSTransmogs;16;200;100")
        self.assertIsNotNone(self.addon.transmogTooltipPending)
        self.lua.execute("GameTooltip.owner=UIParent")
        self.addon.UpdateTransmogInspect(self.addon, 0.25)
        self.assertIsNone(self.addon.transmogTooltipPending)
        self.g.zInspectFrame.Hide(self.g.zInspectFrame)
        self.reply("INSTransmogs;start;0;0")
        self.assertTrue(self.lua.eval("zInspect.transmogItems[16] ~= nil"))


if __name__ == "__main__":
    unittest.main()
