"""Run AutoAcceptInvite.lua outside the game and check what it does.

The addon is loaded into a Lua 5.1 runtime where a small stand-in replaces the
game's API. Each check starts from a fresh load, fires the events the game
would fire, and looks at which game functions the addon called.

This checks the addon's own logic. It cannot show that the real game behaves
the way the stand-in does, so it does not replace a test in game.

Needs the `lupa` package:  pip install lupa
Usage:                     python tests/run.py
"""
import os
import sys

from lupa import lua51

ADDON = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "AutoAcceptInvite.lua")

# The stand-in for the game. `game` holds what a check sets up and what the addon did.
STAND_IN = r"""
game = { calls = {}, printed = {}, frames = {}, in_group = false, in_combat = false,
         role_check_result = true, registered_panels = {} }

local function called(name, ...) table.insert(game.calls, { name = name, args = { ... } }) end

function print(...) table.insert(game.printed, table.concat({ ... }, " ")) end

local methods = {}
function methods:SetScript(name, fn) self.scripts[name] = fn end
function methods:GetScript(name) return self.scripts[name] end
function methods:RegisterEvent(event)
    if not game.known_events[event] then error('Attempt to register unknown event "' .. event .. '"') end
    self.events[event] = true
end
function methods:UnregisterEvent(event) self.events[event] = nil end
function methods:CreateFontString()
    local text = game.widget()
    text.parent = self
    return text
end
function methods:SetText(text) self.text = text end
function methods:GetStringWidth() return 100 end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function methods:Hide() self.shown = false end

function game.widget()
    local w = { scripts = {}, events = {} }
    table.insert(game.frames, w)
    -- Any method the stand-in does not model (SetPoint, SetSize, ...) does nothing.
    return setmetatable(w, { __index = function(_, key) return methods[key] or function() end end })
end

function CreateFrame(kind, name, parent, template)
    local w = game.widget()
    w.kind, w.template = kind, template
    return w
end

function game.fire(event, ...)
    for _, frame in ipairs(game.frames) do
        if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
end

function game.count(name)
    local n = 0
    for _, call in ipairs(game.calls) do if call.name == name then n = n + 1 end end
    return n
end

function game.last(name)
    for i = #game.calls, 1, -1 do if game.calls[i].name == name then return game.calls[i].args end end
end

-- The checkbox whose label starts with the given words, or nil.
function game.checkbox(label)
    for _, text in ipairs(game.frames) do
        -- rawget, because a widget answers any unknown field with a do-nothing function.
        local parent, words = rawget(text, "parent"), rawget(text, "text")
        if parent and rawget(parent, "kind") == "CheckButton" and type(words) == "string"
            and words:sub(1, #label) == label then
            return parent
        end
    end
end

-- What a player's click on a checkbox does: flip it, then run the addon's handler.
function game.click(checkbox)
    checkbox.checked = not checkbox.checked
    checkbox.scripts.OnClick(checkbox)
end

-- Functions every game version has.
SlashCmdList = {}
C_Timer = { After = function(seconds, fn) table.insert(game.timers, fn) end }
game.timers = {}

-- Let the game reach its next frame: timers that were waiting now run.
function game.next_frame()
    local due = game.timers
    game.timers = {}
    for _, fn in ipairs(due) do fn() end
end
function InCombatLockdown() return game.in_combat end
function IsInGroup() return game.in_group end
function AcceptGroup() called("AcceptGroup") end
function StaticPopup_Hide(which) called("StaticPopup_Hide", which) end

-- Friends and guild, asked about by GUID. A check fills these tables.
game.friends, game.battle_net_friends, game.guild = {}, {}, {}
C_FriendList = { IsFriend = function(guid) called("C_FriendList.IsFriend", guid); return game.friends[guid] == true end }
C_BattleNet = { GetAccountInfoByGUID = function(guid)
    if game.battle_net_friends[guid] then return { isFriend = true } end
end }
function IsGuildMember(guid) return game.guild[guid] == true end

-- The role check functions and event exist in every game version, as Blizzard's
-- own lists say. Only versions with a dungeon finder have the window.
function GetLFGRoles() return game.roles[1], game.roles[2], game.roles[3], game.roles[4] end
function GetPVPRoles() return game.pvp_roles[1], game.pvp_roles[2], game.pvp_roles[3] end
function GetLFGRoleUpdate() return true, 1, {}, 1, 1, game.battleground_role_check end
function CompleteLFGRoleCheck(accept) called("CompleteLFGRoleCheck", accept); return game.role_check_result end
-- game.ignores_set_roles: the game silently does not take roles an addon sets.
function SetLFGRoles(leader, tank, healer, damage)
    called("SetLFGRoles", leader, tank, healer, damage)
    if not game.ignores_set_roles then game.roles = { leader, tank, healer, damage } end
end
function SetPVPRoles(tank, healer, damage)
    called("SetPVPRoles", tank, healer, damage)
    if not game.ignores_set_roles then game.pvp_roles = { tank, healer, damage } end
end
TANK, HEALER, DAMAGER = "Tank", "Healer", "Damage"

function game.setup(flavor)
    game.known_events = { PLAYER_LOGIN = true, PARTY_INVITE_REQUEST = true, GROUP_ROSTER_UPDATE = true,
                          LFG_ROLE_CHECK_SHOW = true }
    game.roles = { false, false, false, true }       -- leader, tank, healer, damage
    game.pvp_roles = { false, false, false }         -- tank, healer, damage
    game.battleground_role_check = false
    if flavor == "retail" or flavor == "mists" then
        LFDRoleCheckPopup = { name = "LFDRoleCheckPopup" }
        function StaticPopupSpecial_Hide(frame) called("StaticPopupSpecial_Hide", frame) end
        -- Specializations: game.spec_role is the role of the one being played, nil for none chosen.
        -- As in the game, the index comes from C_SpecializationInfo; there is no plain GetSpecialization.
        game.spec_role = "DAMAGER"
        C_SpecializationInfo = { GetSpecialization = function() return game.spec_role and 2 or nil end }
        function GetSpecializationRole(index) return game.spec_role end
    end
    if flavor == "retail" then
        Settings = {
            RegisterCanvasLayoutCategory = function(panel, name) return { ID = 7, panel = panel, name = name } end,
            RegisterAddOnCategory = function(category) table.insert(game.registered_panels, category.name) end,
            OpenToCategory = function(id) called("Settings.OpenToCategory", id) end,
        }
        LFGInvitePopup = { name = "LFGInvitePopup" }
        function issecretvalue(value) return value == game.secret end
        -- Retail can have character friends switched off, and says so.
        game.character_friends_enabled = true
        C_FriendList.IsLegacyFriendSystemEnabled = function() return game.character_friends_enabled end
    else
        function InterfaceOptions_AddCategory(panel) table.insert(game.registered_panels, panel.name) end
        function InterfaceOptionsFrame_OpenToCategory(panel) called("InterfaceOptionsFrame_OpenToCategory", panel) end
    end
end
"""

FLAVORS = ("retail", "mists", "era")


def load(flavor, saved=None):
    """A fresh game of the given flavor with the addon loaded and the player logged in."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STAND_IN)
    game = lua.globals().game
    game.setup(flavor)
    if saved is not None:
        lua.globals().AutoAcceptInviteDB = lua.table_from(saved)
    with open(ADDON, encoding="utf-8") as source:
        lua.execute(source.read())
    game.fire("PLAYER_LOGIN")
    return lua, game


def printed(game):
    return [game.printed[i] for i in range(1, len(game.printed) + 1)]


def invite(game, inviter="Bob", guid="Player-1-BOB"):
    # The game's arguments: name, three role flags, same realm, several roles allowed, the inviter's GUID.
    game.fire("PARTY_INVITE_REQUEST", inviter, False, False, False, True, False, guid)


def join(game):
    game.in_group = True
    game.fire("GROUP_ROSTER_UPDATE")


CHECKS = []


def check(function):
    CHECKS.append(function)
    return function


@check
def loads_and_registers_its_options_panel_on_every_flavor():
    for flavor in FLAVORS:
        lua, game = load(flavor)
        assert game.registered_panels[1] == "AutoAcceptInvite", flavor
        assert lua.globals().SLASH_AUTOACCEPTINVITE1 == "/aai", flavor
        assert printed(game) == [], flavor


@check
def accepts_an_invite_and_says_whose():
    for flavor in FLAVORS:
        lua, game = load(flavor)
        invite(game, "Bob")
        assert game.count("AcceptGroup") == 1, flavor
        assert printed(game)[-1].endswith("accepted invite from Bob."), flavor


@check
def closes_the_invite_popup_only_after_joining():
    lua, game = load("retail")
    invite(game)
    assert game.count("StaticPopup_Hide") == 0, "closing the popup before joining declines the invite"
    game.fire("GROUP_ROSTER_UPDATE")  # the roster changed, but we are not in the group yet
    assert game.count("StaticPopup_Hide") == 0
    join(game)
    assert game.last("StaticPopup_Hide")[1] == "PARTY_INVITE"
    assert game.count("StaticPopupSpecial_Hide") == 1
    join(game)  # later roster changes close nothing
    assert game.count("StaticPopup_Hide") == 1


@check
def does_nothing_when_switched_off():
    lua, game = load("retail", {"disabled": True})
    invite(game)
    join(game)
    assert game.count("AcceptGroup") == 0
    assert game.count("StaticPopup_Hide") == 0
    assert printed(game) == []


@check
def stays_quiet_when_chat_messages_are_off():
    lua, game = load("retail", {"quiet": True})
    invite(game)
    assert game.count("AcceptGroup") == 1
    assert printed(game) == []


@check
def does_not_read_a_secret_inviter_name():
    lua, game = load("retail")
    game.secret = "Bob"
    invite(game, "Bob")
    assert game.count("AcceptGroup") == 1
    assert printed(game)[-1].endswith("accepted invite.")


@check
def slash_command_toggles_and_reports():
    lua, game = load("retail")
    slash = lua.globals().SlashCmdList["AUTOACCEPTINVITE"]
    slash("")
    assert "OFF" in printed(game)[-1]
    invite(game)
    assert game.count("AcceptGroup") == 0
    slash(" ON ")
    assert "ON" in printed(game)[-1]
    invite(game)
    assert game.count("AcceptGroup") == 1
    slash("off")
    assert lua.globals().AutoAcceptInviteDB.disabled is True
    slash("nonsense")
    assert "usage" in printed(game)[-1]


@check
def slash_options_opens_the_panel_but_not_in_combat():
    lua, game = load("retail")
    slash = lua.globals().SlashCmdList["AUTOACCEPTINVITE"]
    slash("options")
    assert game.last("Settings.OpenToCategory")[1] == 7
    game.in_combat = True
    slash("options")
    assert game.count("Settings.OpenToCategory") == 1
    assert "combat" in printed(game)[-1]
    lua, game = load("era")
    lua.globals().SlashCmdList["AUTOACCEPTINVITE"]("options")
    assert game.count("InterfaceOptionsFrame_OpenToCategory") == 2


FRIEND, BATTLE_NET_FRIEND, GUILD_MATE, STRANGER = "Player-1-FRIEND", "Player-1-BNET", "Player-1-GUILD", "Player-1-STRANGER"


def load_with_people(flavor, saved):
    """A fresh game where the player has a friend, a Battle.net friend and a guild mate."""
    lua, game = load(flavor, saved)
    game.friends[FRIEND] = True
    game.battle_net_friends[BATTLE_NET_FRIEND] = True
    game.guild[GUILD_MATE] = True
    return lua, game


@check
def accepts_only_from_the_people_picked_in_the_options():
    wanted = {  # accepted from: friend, Battle.net friend, guild mate, stranger
        None: (True, True, True, True),
        "FRIENDS_GUILD": (True, True, True, False),
        "FRIENDS": (True, True, False, False),
        "GUILD": (False, False, True, False),
    }
    for flavor in FLAVORS:
        for whose, expected in wanted.items():
            got = []
            for guid in (FRIEND, BATTLE_NET_FRIEND, GUILD_MATE, STRANGER):
                lua, game = load_with_people(flavor, {"from": whose} if whose else {})
                invite(game, "Someone", guid)
                got.append(game.count("AcceptGroup") == 1)
            assert tuple(got) == expected, "%s, from %s: %s" % (flavor, whose or "everyone", got)


@check
def does_not_look_up_character_friends_while_retail_has_them_switched_off():
    lua, game = load_with_people("retail", {"from": "FRIENDS"})
    game.character_friends_enabled = False
    invite(game, "Someone", FRIEND)
    assert game.count("C_FriendList.IsFriend") == 0, "the game's own code asks first, and so must the addon"
    assert game.count("AcceptGroup") == 0
    invite(game, "Someone", BATTLE_NET_FRIEND)
    assert game.count("AcceptGroup") == 1, "Battle.net friends still count"


@check
def an_invite_from_someone_left_out_gets_the_normal_popup():
    lua, game = load_with_people("retail", {"from": "GUILD"})
    invite(game, "Stranger", STRANGER)
    join(game)
    assert game.count("AcceptGroup") == 0
    assert game.count("StaticPopup_Hide") == 0, "the popup is the player's to answer"
    assert printed(game) == []


@check
def when_the_game_does_not_say_who_invites_only_everyone_accepts():
    for guid in (None, "a GUID addons may not read"):
        lua, game = load_with_people("retail", {"from": "FRIENDS_GUILD"})
        game.secret = "a GUID addons may not read"
        invite(game, "Someone", guid)
        assert game.count("AcceptGroup") == 0
        assert game.count("C_FriendList.IsFriend") == 0, "such a GUID must not be passed on to the game"

        lua, game = load_with_people("retail", {})
        game.secret = "a GUID addons may not read"
        invite(game, "Someone", guid)
        assert game.count("AcceptGroup") == 1


@check
def commands_only_switch_things_on_and_off():
    # Whose invites and which role are picked in the options panel, not typed.
    lua, game = load_with_people("retail", {"from": "GUILD", "role": "TANK"})
    slash = lua.globals().SlashCmdList["AUTOACCEPTINVITE"]
    db = lua.globals().AutoAcceptInviteDB
    for typed in ("from everyone", "from friends", "role healer", "role spec"):
        slash(typed)
        assert "usage" in printed(game)[-1], typed
        assert (db["from"], db.role, db.disabled, db.roleChecks) == ("GUILD", "TANK", None, None), typed
    slash("on")
    assert printed(game)[-1].endswith("accepting party invites from guild members."), "the switch says whose"
    slash("role")
    assert printed(game)[-1].endswith("accepting them as Tank."), "the switch says which role"


@check
def options_panel_lets_the_player_pick_whose_invites():
    lua, game = load_with_people("retail", {})
    panel = [f for f in (game.frames[i] for i in range(1, len(game.frames) + 1)) if f.name == "AutoAcceptInvite"][0]
    panel.Show(panel)
    everyone, both, friends, guild = (game.checkbox(label) for label in
                                      ("Everyone", "Friends and guild members", "Friends only", "Guild members only"))
    db = lua.globals().AutoAcceptInviteDB

    def ticked():
        return (everyone.checked, both.checked, friends.checked, guild.checked)

    assert ticked() == (True, False, False, False), "everyone until a choice is made"
    game.click(guild)
    assert db["from"] == "GUILD" and ticked() == (False, False, False, True)
    invite(game, "Stranger", STRANGER)
    assert game.count("AcceptGroup") == 0
    invite(game, "Guildie", GUILD_MATE)
    assert game.count("AcceptGroup") == 1
    game.click(everyone)
    assert db["from"] is None and ticked() == (True, False, False, False)


def role_check(game):
    game.fire("LFG_ROLE_CHECK_SHOW")


@check
def leaves_role_checks_alone_until_switched_on():
    lua, game = load("retail")
    role_check(game)
    assert game.count("CompleteLFGRoleCheck") == 0
    assert printed(game) == []


def args(game, name):
    """The arguments of the last call to a game function, as a tuple."""
    last = game.last(name)
    return tuple(last[i] for i in range(1, 5) if last[i] is not None)


@check
def accepts_a_role_check_as_the_current_specializations_role():
    for flavor in ("retail", "mists"):
        lua, game = load(flavor, {"roleChecks": True})
        game.spec_role = "HEALER"
        game.roles = lua.table_from([True, True, False, False])  # group leader, and a tank tick left from last time
        role_check(game)
        assert args(game, "SetLFGRoles") == (True, False, True, False), "healer only, leader tick untouched"
        assert game.count("SetPVPRoles") == 0, flavor
        assert game.last("CompleteLFGRoleCheck")[1] is True, flavor
        assert printed(game)[-1].endswith("accepted the role check as Healer."), flavor
        assert game.count("StaticPopupSpecial_Hide") == 0, "the game may not have opened the window yet"
        game.next_frame()
        assert game.last("StaticPopupSpecial_Hide")[1].name == "LFDRoleCheckPopup", flavor


@check
def accepts_as_the_role_picked_in_the_options():
    for role, sent, name in (("TANK", (False, True, False, False), "Tank"),
                             ("HEALER", (False, False, True, False), "Healer"),
                             ("DAMAGER", (False, False, False, True), "Damage")):
        lua, game = load("retail", {"roleChecks": True, "role": role})
        game.spec_role = "HEALER" if role != "HEALER" else "TANK"
        role_check(game)
        assert args(game, "SetLFGRoles") == sent, "the picked role, not the specialization's"
        assert printed(game)[-1].endswith("accepted the role check as %s." % name)


@check
def never_accepts_with_a_role_the_game_did_not_take():
    lua, game = load("retail", {"roleChecks": True, "role": "TANK"})
    game.ignores_set_roles = True  # say, a class that cannot tank: the damage tick from last time stays
    role_check(game)
    game.next_frame()
    assert game.count("SetLFGRoles") == 1
    assert game.count("CompleteLFGRoleCheck") == 0, "accepting would queue as damage, not as the picked role"
    assert game.count("StaticPopupSpecial_Hide") == 0
    assert "could not set your role to Tank" in printed(game)[-1]


@check
def with_no_role_picked_and_no_specialization_it_goes_by_the_ticked_roles():
    lua, game = load("retail", {"roleChecks": True})
    game.spec_role = None
    game.roles = lua.table_from([False, True, False, True])
    role_check(game)
    assert game.count("SetLFGRoles") == 0
    assert printed(game)[-1].endswith("accepted the role check as Tank, Damage.")


@check
def leaves_the_window_open_when_the_game_refuses_the_role_check():
    lua, game = load("retail", {"roleChecks": True})
    game.role_check_result = False
    role_check(game)
    game.next_frame()
    assert game.count("CompleteLFGRoleCheck") == 1
    assert game.count("StaticPopupSpecial_Hide") == 0
    assert printed(game) == []


@check
def leaves_the_role_check_alone_when_no_role_is_ticked():
    lua, game = load("retail", {"roleChecks": True})
    game.spec_role = None
    game.roles = lua.table_from([False, False, False, False])
    role_check(game)
    game.next_frame()
    assert game.count("CompleteLFGRoleCheck") == 0, "the game's own Accept button is greyed out with no role"
    assert game.count("StaticPopupSpecial_Hide") == 0
    assert printed(game) == []


@check
def a_battleground_role_check_uses_the_battleground_roles():
    lua, game = load("retail", {"roleChecks": True})
    game.battleground_role_check = True
    game.spec_role = "TANK"
    role_check(game)
    assert args(game, "SetPVPRoles") == (True, False, False)
    assert game.count("SetLFGRoles") == 0
    assert printed(game)[-1].endswith("accepted the role check as Tank.")

    lua, game = load("retail", {"roleChecks": True})
    game.battleground_role_check = True
    game.spec_role = None
    role_check(game)  # a dungeon role is ticked, but no battleground role
    assert game.count("CompleteLFGRoleCheck") == 0
    game.pvp_roles = lua.table_from([False, True, False])
    role_check(game)
    assert game.count("CompleteLFGRoleCheck") == 1
    assert printed(game)[-1].endswith("accepted the role check as Healer.")


@check
def role_checks_and_invites_are_switched_separately():
    lua, game = load("retail", {"roleChecks": True, "disabled": True})
    invite(game)
    role_check(game)
    assert game.count("AcceptGroup") == 0
    assert game.count("CompleteLFGRoleCheck") == 1
    lua, game = load("retail", {"roleChecks": True, "quiet": True})
    role_check(game)
    assert game.count("CompleteLFGRoleCheck") == 1
    assert printed(game) == []


@check
def slash_role_toggles_role_checks():
    lua, game = load("retail")
    slash = lua.globals().SlashCmdList["AUTOACCEPTINVITE"]
    slash("role")
    assert lua.globals().AutoAcceptInviteDB.roleChecks is True
    assert "role checks" in printed(game)[-1] and "ON" in printed(game)[-1]
    assert "specialization" in printed(game)[-1], "it says which role it will accept with"
    role_check(game)
    assert game.count("CompleteLFGRoleCheck") == 1
    slash("role")
    assert lua.globals().AutoAcceptInviteDB.roleChecks is False
    assert "OFF" in printed(game)[-1]
    assert lua.globals().AutoAcceptInviteDB.disabled is None, "/aai role must not touch the invite switch"


@check
def game_versions_without_role_checks_show_no_role_option():
    lua, game = load("era", {"roleChecks": True})
    assert game.checkbox("Auto-accept role checks") is None
    assert game.checkbox("Auto-accept invites") is not None
    assert game.checkbox("Print a chat message") is not None
    lua.globals().SlashCmdList["AUTOACCEPTINVITE"]("role")
    assert "no role checks" in printed(game)[-1]
    role_check(game)  # the event exists there, but the addon does not listen for it
    assert game.count("CompleteLFGRoleCheck") == 0
    invite(game)
    assert game.count("AcceptGroup") == 1


@check
def options_panel_shows_and_changes_the_settings():
    lua, game = load("retail", {"quiet": True})
    panel = [f for f in (game.frames[i] for i in range(1, len(game.frames) + 1)) if f.name == "AutoAcceptInvite"][0]
    panel.Show(panel)
    invites = game.checkbox("Auto-accept invites")
    roles = game.checkbox("Auto-accept role checks")
    chat = game.checkbox("Print a chat message")
    assert (invites.checked, roles.checked, chat.checked) == (True, False, False)
    game.click(roles)
    game.click(chat)
    game.click(invites)
    db = lua.globals().AutoAcceptInviteDB
    assert (db.disabled, db.roleChecks, db.quiet) == (True, True, False)
    role_check(game)
    assert printed(game)[-1].endswith("accepted the role check as Damage.")


@check
def options_panel_lets_the_player_pick_one_role_to_queue_as():
    lua, game = load("retail", {"roleChecks": True})
    panel = [f for f in (game.frames[i] for i in range(1, len(game.frames) + 1)) if f.name == "AutoAcceptInvite"][0]
    panel.Show(panel)
    spec, tank, healer, damage = (game.checkbox(label) for label in
                                  ("My current specialization", "Tank", "Healer", "Damage"))
    db = lua.globals().AutoAcceptInviteDB

    def ticked():
        return (spec.checked, tank.checked, healer.checked, damage.checked)

    assert ticked() == (True, False, False, False), "the specialization's role until one is picked"
    game.click(healer)
    assert db.role == "HEALER" and ticked() == (False, False, True, False)
    game.click(healer)  # clicking the ticked one again leaves it ticked
    assert db.role == "HEALER" and ticked() == (False, False, True, False)
    role_check(game)
    assert printed(game)[-1].endswith("accepted the role check as Healer.")
    game.click(spec)
    assert db.role is None and ticked() == (True, False, False, False)


def main():
    failed = 0
    for function in CHECKS:
        name = function.__name__.replace("_", " ")
        try:
            function()
            print("ok    " + name)
        except Exception as problem:  # a failed check or a Lua error
            failed += 1
            print("FAIL  " + name + "\n      " + (str(problem) or type(problem).__name__).replace("\n", "\n      "))
    print("\n%d of %d checks passed" % (len(CHECKS) - failed, len(CHECKS)))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
