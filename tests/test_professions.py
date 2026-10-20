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

SENT_MESSAGES = {}
function SendAddonMessage(prefix, message, channel)
    table.insert(SENT_MESSAGES, { prefix = prefix, message = message, channel = channel })
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
            self.addon, "TW_CHAT_MSG_WHISPER", "ZINSProf;request;1", "Alpha"
        )
        self.assertEqual(self.g.SENT_MESSAGES[1].message, "ZINSProf;start;1")
        messages = [self.g.SENT_MESSAGES[i].message for i in range(1, 5)]
        self.assertIn("ZINSProf;skill;164;275;300;1;1;BB", messages)
        self.assertIn("ZINSProf;skill;186;300;300;1;1;-", messages)
        self.assertEqual(messages[-1], "ZINSProf;end;1")
        self.assertTrue(all(self.g.SENT_MESSAGES[i].prefix == "TW_CHAT_MSG_WHISPER<Alpha>" for i in range(1, 5)))

    def test_remote_reply_is_assembled_and_wrong_sender_is_ignored(self):
        self.lua.execute('''
            zInspect.currentUnit = "target"
            zInspect.currentUnitName = "Alpha"
            zInspect.currentTab = "professions"
            zInspect:StartProfessionInspect("target")
        ''')
        handle = self.addon.HandleProfessionMessage
        handle(self.addon, "TW_CHAT_MSG_WHISPER", "ZINSProf;start;1", "Alpha")
        handle(self.addon, "TW_CHAT_MSG_WHISPER", "ZINSProf;skill;164;300;300;1;2;abc", "Stranger")
        handle(self.addon, "TW_CHAT_MSG_WHISPER", "ZINSProf;skill;164;300;300;1;2;abc", "Alpha")
        handle(self.addon, "TW_CHAT_MSG_WHISPER", "ZINSProf;skill;164;300;300;2;2;def", "Alpha")
        handle(self.addon, "TW_CHAT_MSG_WHISPER", "ZINSProf;end;1", "Alpha")
        self.assertEqual(self.lua.eval("table.getn(zInspect.professionData)"), 1)
        self.assertEqual(self.addon.professionData[1].bits, "abcdef")
        self.assertTrue(self.addon.professionReplyComplete)

    def test_remote_requests_are_bounded(self):
        self.lua.execute('''
            zInspect.currentUnit = "target"
            zInspect.currentUnitName = "Alpha"
            zInspect.currentTab = "professions"
            zInspect:StartProfessionInspect("target")
            zInspect:RequestProfessions()
        ''')
        for _ in range(8):
            self.lua.execute("arg1=1.5; zInspectFrame._scripts.OnUpdate()")
        self.assertEqual(self.lua.eval("table.getn(SENT_MESSAGES)"), 3)


if __name__ == "__main__":
    unittest.main()
