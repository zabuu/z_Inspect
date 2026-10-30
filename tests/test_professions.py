import unittest

from lupa.lua51 import LuaRuntime

from test_update_slots import ADDON_FILE, WOW_MOCK


PROFESSION_MOCK = r'''
TEST_UNITS.player = { name = "Me", items = {} }
function UnitIsPlayer(unit) return UnitExists(unit) end
function UnitIsUnit(first, second)
    return UnitName(first) ~= nil and UnitName(first) == UnitName(second)
end

LOCAL_SKILLS = {}
SKILL_NAMES = { [164] = "Blacksmithing", [186] = "Mining" }
C_SpellBook = {}
function C_SpellBook.GetSkillLineName(id) return SKILL_NAMES[id] end
function C_SpellBook.GetSkillLineRank(id)
    local value = LOCAL_SKILLS[id]
    if value then return value[1], value[2], 0 end
end

RECIPE_LISTS = {}
C_TradeSkillUI = {}
function C_TradeSkillUI.GetTradeSkillListRecipes(id, bits)
    return RECIPE_LISTS[id] or {}
end
KNOWN_SPELLS = {}
function IsPlayerSpell(id) return KNOWN_SPELLS[id] == true end

SENT_MESSAGES, ADDON_MESSAGES, VISIBLE_CHAT = {}, {}, {}
function SendChatMessage(message, channel, language, target)
    table.insert(SENT_MESSAGES, { message = message, channel = channel, target = target })
end
function SendAddonMessage(prefix, message, channel)
    -- Server inspect RPCs do not deliver arbitrary addon messages to a peer.
    table.insert(ADDON_MESSAGES, { prefix = prefix, message = message, channel = channel })
end
function ChatFrame_OnEvent(chatEvent)
    table.insert(VISIBLE_CHAT, { event = chatEvent, message = arg1 })
    return "forwarded"
end

OPENED_LINK = nil
function SetItemRef(payload, link, button)
    OPENED_LINK = { payload = payload, link = link, button = button }
end

zInspectFrame:Show()
'''


class ProfessionTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(WOW_MOCK)
        self.lua.execute(ADDON_FILE.read_text(encoding="utf-8"))
        self.lua.execute(PROFESSION_MOCK)
        self.lua.execute("zInspect:InstallProfessionChatFilter()")
        self.g = self.lua.globals()
        self.addon = self.g.zInspect

    def prepare_local_skills(self):
        self.lua.execute('''
            LOCAL_SKILLS[164] = { 275, 300 }
            LOCAL_SKILLS[186] = { 300, 300 }
            RECIPE_LISTS[164] = {
                { spellID=101 }, { spellID=102 }, { spellID=103 },
                { spellID=104 }, { spellID=105 }, { spellID=106 },
                { spellID=107 },
            }
            KNOWN_SPELLS[101] = true
            KNOWN_SPELLS[107] = true
        ''')

    def start_remote(self):
        self.lua.execute('''
            zInspect.currentUnit = "target"
            zInspect.currentUnitName = "Alpha"
            zInspect.currentTab = "professions"
            zInspect:StartProfessionInspect("target")
            zInspect:UpdateProfessionsTab()
        ''')

    def tick(self, elapsed=0.5):
        self.g.arg1 = elapsed
        self.g.zInspectEventFrame._scripts.OnUpdate()
        if self.g.zInspectFrame.IsShown(self.g.zInspectFrame):
            self.g.arg1 = elapsed
            self.g.zInspectFrame._scripts.OnUpdate()

    def receive(self, message, sender="Alpha", client=None):
        g = (client or self.lua).globals()
        g.event, g.arg1, g.arg2 = "CHAT_MSG_WHISPER", message, sender
        g.zInspectEventFrame._scripts.OnEvent()

    def test_self_lists_skills_encodes_recipes_and_opens_viewer(self):
        self.prepare_local_skills()
        self.addon.StartProfessionInspect(self.addon, "player")
        self.assertEqual(self.lua.eval("table.getn(zInspect.professionData)"), 2)
        self.assertEqual(self.addon.professionData[1].bits, "BB")
        self.assertEqual(self.addon.professionData[2].bits, "")

        self.addon.OpenProfession(self.addon, self.addon.professionData[1])
        self.assertEqual(self.g.OPENED_LINK.payload, "trade:164:275:300:Me:BB")
        self.assertIn("[Blacksmithing]", self.g.OPENED_LINK.link)

    def test_request_sends_compact_profession_reply(self):
        self.prepare_local_skills()
        self.addon.HandleProfessionMessage(
            self.addon, "ZINSProf", "ZINSProf;request;1", "Alpha"
        )
        for _ in range(4):
            self.tick()
        self.assertEqual(self.g.SENT_MESSAGES[1].message, "/ZINSProf;start;1;2")
        messages = [self.g.SENT_MESSAGES[i].message for i in range(1, 5)]
        self.assertIn("/ZINSProf;skill;164;275;300;1;1;BB", messages)
        self.assertIn("/ZINSProf;skill;186;300;300;1;1;-", messages)
        self.assertEqual(messages[-1], "/ZINSProf;end;1")
        self.assertTrue(all(self.g.SENT_MESSAGES[i].target == "Alpha" for i in range(1, 5)))
        self.assertTrue(all(self.g.SENT_MESSAGES[i].channel == "WHISPER" for i in range(1, 5)))
        self.assertEqual(len(self.g.ADDON_MESSAGES), 0)

    def test_remote_reply_is_assembled_and_wrong_sender_is_ignored(self):
        self.start_remote()
        self.receive("/ZINSProf;start;1;1")
        self.receive("/ZINSProf;skill;164;300;300;1;2;abc", "Stranger")
        self.receive("/ZINSProf;skill;164;300;300;1;2;abc")
        self.receive("/ZINSProf;skill;164;300;300;2;2;def")
        self.receive("/ZINSProf;end;1")
        self.assertEqual(self.lua.eval("table.getn(zInspect.professionData)"), 1)
        self.assertEqual(self.addon.professionData[1].bits, "abcdef")
        self.assertTrue(self.addon.professionReplyComplete)

    def test_remote_requests_are_bounded(self):
        self.start_remote()
        for _ in range(20):
            self.tick()
        self.assertEqual(self.lua.eval("table.getn(SENT_MESSAGES)"), 3)
        status = self.g.zInspectProfessionStatusText._text
        self.assertIn("No reply after 3 requests", status)
        self.assertNotIn("The player needs", status)
        self.addon.UpdateProfessionsTab(self.addon)
        self.tick()
        self.assertEqual(len(self.g.SENT_MESSAGES), 4)

    def test_two_clients_exchange_recipes_with_recipient_window_closed(self):
        peer = LuaRuntime(unpack_returned_tuples=True)
        peer.execute(WOW_MOCK)
        peer.execute(ADDON_FILE.read_text(encoding="utf-8"))
        peer.execute(PROFESSION_MOCK)
        peer.execute('''
            TEST_UNITS.player.name = "Alpha"
            LOCAL_SKILLS[164] = { 275, 300 }
            LOCAL_SKILLS[186] = { 300, 300 }
            RECIPE_LISTS[164] = { {spellID=101} }
            KNOWN_SPELLS[101] = true
            zInspectFrame:Hide()
        ''')
        self.start_remote()
        request_cursor, response_cursor = 1, 1
        pg = peer.globals()
        for _ in range(20):
            self.tick()
            while request_cursor <= len(self.g.SENT_MESSAGES):
                packet = self.g.SENT_MESSAGES[request_cursor]
                self.assertEqual(packet.target, "Alpha")
                self.receive(packet.message, "Me", peer)
                request_cursor += 1
            pg.arg1 = 0.5
            pg.zInspectEventFrame._scripts.OnUpdate()
            while response_cursor <= len(pg.SENT_MESSAGES):
                packet = pg.SENT_MESSAGES[response_cursor]
                self.assertEqual(packet.target, "Me")
                self.receive(packet.message)
                response_cursor += 1
        self.assertTrue(self.addon.professionReplyComplete)
        self.assertEqual(len(self.addon.professionData), 2)
        self.assertEqual(self.addon.professionData[1].bits, "B")
        self.assertEqual(len(self.g.SENT_MESSAGES), 1)
        self.assertEqual(len(self.g.ADDON_MESSAGES) + len(pg.ADDON_MESSAGES), 0)
        self.addon.OpenProfession(self.addon, self.addon.professionData[1])
        self.assertEqual(self.g.OPENED_LINK.payload, "trade:164:275:300:Alpha:B")

    def test_protocol_is_hidden_but_normal_whispers_are_unchanged(self):
        for chat_event in ("CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM"):
            self.g.arg1 = "/ZINSProf;request;1"
            self.g.ChatFrame_OnEvent(chat_event)
        self.assertEqual(len(self.g.VISIBLE_CHAT), 0)
        self.g.arg1 = "hello there"
        self.assertEqual(self.g.ChatFrame_OnEvent("CHAT_MSG_WHISPER"), "forwarded")
        self.assertEqual(len(self.g.VISIBLE_CHAT), 1)
        self.receive("hello there", "Stranger")
        self.assertEqual(len(self.addon.professionSendQueue), 0)

    def test_incomplete_or_duplicate_packets_do_not_mark_transfer_complete(self):
        self.start_remote()
        self.receive("/ZINSProf;start;1;2")
        self.receive("/ZINSProf;skill;164;300;300;1;1;abc")
        self.receive("/ZINSProf;skill;164;300;300;1;1;abc")
        self.receive("/ZINSProf;end;1")
        self.assertEqual(len(self.addon.professionData), 1)
        self.assertFalse(self.addon.professionReplyComplete)
        self.assertIn("Incomplete", self.g.zInspectProfessionStatusText._text)

    def test_switching_target_cancels_queued_request_and_rejects_late_reply(self):
        self.start_remote()
        self.lua.execute('''
            zInspect.currentUnit = "other"
            zInspect.currentUnitName = "Beta"
            zInspect:StartProfessionInspect("other")
        ''')
        self.tick()
        self.assertEqual(len(self.g.SENT_MESSAGES), 0)
        self.receive("/ZINSProf;start;1;1")
        self.receive("/ZINSProf;skill;164;300;300;1;1;B")
        self.receive("/ZINSProf;end;1")
        self.assertEqual(len(self.addon.professionData), 0)

    def test_missing_skill_api_is_reported_separately(self):
        self.lua.execute("C_SpellBook=nil")
        self.receive("/ZINSProf;request;1", "Stranger")
        self.tick()
        self.assertEqual(self.g.SENT_MESSAGES[1].message, "/ZINSProf;unavailable;1")
        self.start_remote()
        self.receive("/ZINSProf;unavailable;1")
        self.assertTrue(self.addon.professionReplyComplete)
        self.addon.UpdateProfessionsTab(self.addon)
        self.assertIn("cannot read", self.g.zInspectProfessionStatusText._text)

    def test_reply_pacing_has_no_catch_up_burst_and_deduplicates_requests(self):
        self.prepare_local_skills()
        for _ in range(4):
            self.receive("/ZINSProf;request;1", "Stranger")
        self.assertEqual(len(self.addon.professionSendQueue), 4)
        self.tick(30)
        self.assertEqual(len(self.g.SENT_MESSAGES), 1)
        self.tick(0.01)
        self.assertEqual(len(self.g.SENT_MESSAGES), 1)


if __name__ == "__main__":
    unittest.main()
