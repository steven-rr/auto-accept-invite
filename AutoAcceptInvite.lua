-- AutoAcceptInvite: accepts incoming party/raid invites, from everyone or only
-- from friends and guild members, and queues for you: it answers the window
-- that asks for your role when your group's leader queues or you sign up for a
-- group.
--
-- Options panel: Esc > Options > AddOns > AutoAcceptInvite
-- /aai            toggle invites on/off
-- /aai on|off     enable / disable invites
-- /aai queue      toggle queueing for you on/off
-- /aai options    open the options panel, where whose invites and which role
--                 are picked

local ADDON_TITLE = "AutoAcceptInvite"
local PREFIX = "|cff33ff99AutoAcceptInvite|r: "

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
-- Everything is "on" while unset, so a fresh install needs no setup.
--
-- Shared by every character on the account:
--   AutoAcceptInviteDB.disabled     true = do not auto-accept invites
--   AutoAcceptInviteDB.from         whose invites to accept: "FRIENDS_GUILD",
--                                   "FRIENDS" or "GUILD"; unset = everyone's
--   AutoAcceptInviteDB.evenInQueue  true = accept invites while in a queue too;
--                                   unset = leave those for the player
--   AutoAcceptInviteDB.noAutoQueue  true = do not queue for me: leave the
--                                   game's role windows for the player
--   AutoAcceptInviteDB.quiet        true = no chat line when it does something
--
-- Kept per character, because a tank and a mage do not queue as the same role:
--   AutoAcceptInviteCharDB.role     the role to queue as: "TANK", "HEALER" or
--                                   "DAMAGER"; unset = the current
--                                   specialization's role

local function GetDB()
	AutoAcceptInviteDB = AutoAcceptInviteDB or {}
	return AutoAcceptInviteDB
end

local function GetCharDB()
	AutoAcceptInviteCharDB = AutoAcceptInviteCharDB or {}
	return AutoAcceptInviteCharDB
end

local function IsEnabled()
	return not GetDB().disabled
end

local function IsChatty()
	return not GetDB().quiet
end

-- Says in chat what the addon just did. The first line of each kind after
-- logging in also says how to change it, for a player who did not expect it.
local hinted = {}

local function Announce(kind, message, hint)
	if not IsChatty() then return end
	if not hinted[kind] then
		hinted[kind] = true
		message = message .. " " .. hint
	end
	print(PREFIX .. message)
end

-- Whose invites are accepted: "FRIENDS_GUILD", "FRIENDS", "GUILD", or nil for
-- everyone's.
local function AcceptsFrom()
	local from = GetDB().from
	if from == "FRIENDS_GUILD" or from == "FRIENDS" or from == "GUILD" then
		return from
	end
end

local function AcceptsWhileQueued()
	return GetDB().evenInQueue == true
end

local function QueuesForMe()
	return not GetDB().noAutoQueue
end

-- The role picked in the options for this character, or nil for "my current
-- specialization's role".
local function ChosenRole()
	local role = GetCharDB().role
	if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
		return role
	end
end

------------------------------------------------------------------------
-- Whose invites
------------------------------------------------------------------------
-- The game names the inviter by a GUID, which the friends list and the guild
-- can be asked about. The checks are the ones the game's own invite popup
-- makes to colour the inviter's name.

-- On the friends list, through Battle.net or as a character.
local function IsFriend(guid)
	local account = C_BattleNet and C_BattleNet.GetAccountInfoByGUID and C_BattleNet.GetAccountInfoByGUID(guid)
	if account and account.isFriend then
		return true
	end

	-- Retail can have character friends switched off; the game asks before it
	-- looks one up, and so does this. Older game versions always have them.
	local list = C_FriendList
	if list and list.IsFriend and (not list.IsLegacyFriendSystemEnabled or list.IsLegacyFriendSystemEnabled()) then
		return list.IsFriend(guid) and true or false
	end
	return false
end

local function IsGuildMate(guid)
	return IsGuildMember ~= nil and IsGuildMember(guid) and true or false
end

-- Whether an invite from this player is one to accept. When the game gives no
-- GUID, or one that addons may not read, only "everyone" accepts.
local function IsWelcome(guid)
	local from = AcceptsFrom()
	if not from then
		return true
	end
	if (issecretvalue and issecretvalue(guid)) or type(guid) ~= "string" then
		return false
	end
	return (from ~= "GUILD" and IsFriend(guid)) or (from ~= "FRIENDS" and IsGuildMate(guid)) or false
end

------------------------------------------------------------------------
-- Invites while in a queue
------------------------------------------------------------------------
-- Joining a group takes the player out of a queue they may have waited in for
-- a long time, so an invite that arrives then is left for them to answer.

-- Whether accepting an invite now would take the player out of a queue: the
-- dungeon or raid finder, a battleground, or sign-ups to premade groups. The
-- game has its own check for this, which its invite popup uses to add a
-- warning; asking the same one means the two always agree.
local function WouldLeaveQueue()
	return WillAcceptInviteRemoveQueues ~= nil and WillAcceptInviteRemoveQueues() and true or false
end

------------------------------------------------------------------------
-- Role windows
------------------------------------------------------------------------
-- Two windows of the game ask for your role, and one option answers both:
--   the role check, when your group's leader queues for a dungeon or
--     battleground, or signs the group up for a premade group;
--   the sign-up window, when you sign up for a premade group yourself.
-- Game versions without a dungeon finder have the functions below but neither
-- window. Known at login, once the game's own interface is loaded.

local hasRoleWindows = false

-- The role of the specialization being played, as the game spells it: "TANK",
-- "HEALER" or "DAMAGER". Nil when it cannot be told, for example before a
-- specialization is chosen.
local function SpecRole()
	-- The plain GetSpecialization is only there when the game loads its old
	-- function names; the game's own code asks C_SpecializationInfo.
	local getSpec = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
	local spec = getSpec and getSpec()
	local role = spec and GetSpecializationRole and GetSpecializationRole(spec)
	if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
		return role
	end
end

-- The role ticks the game holds for this character: tank, healer, damage. They
-- are the same ticks as in its Group Finder window. Battlegrounds have their own.
local function GetTicks(isBattleground)
	if isBattleground and GetPVPRoles then
		return GetPVPRoles()
	end
	return select(2, GetLFGRoles())
end

local function SetTicks(isBattleground, tank, healer, damage)
	if isBattleground and SetPVPRoles then
		SetPVPRoles(tank, healer, damage)
	else
		SetLFGRoles((GetLFGRoles()), tank, healer, damage)
	end
end

-- The roles as words for a chat line: "Tank", or "Tank, Damage".
local function RoleNames(tank, healer, damage)
	local names = {}
	if tank then names[#names + 1] = TANK or "Tank" end
	if healer then names[#names + 1] = HEALER or "Healer" end
	if damage then names[#names + 1] = DAMAGER or "Damage" end
	return table.concat(names, ", ")
end

local function RoleName(role)
	return RoleNames(role == "TANK", role == "HEALER", role == "DAMAGER")
end

-- The role to answer a role window with: the one picked in the options, or
-- else the current specialization's. With neither to go by it is nil, and the
-- ticks the game already holds are used as they are.
local function RoleToAnswerWith()
	return ChosenRole() or SpecRole()
end

-- Whether that role, and no other, is what is ticked. When it is not, the game
-- did not take the role, for example one this character's class cannot fill.
-- Answering would then send whatever was ticked before, so the window is left
-- to the player.
local function TookRole(role, tank, healer, damage, window)
	local onlyRoleTicked = (not tank) == (role ~= "TANK")
		and (not healer) == (role ~= "HEALER")
		and (not damage) == (role ~= "DAMAGER")
	if not onlyRoleTicked and IsChatty() then
		print(PREFIX .. "could not set your role to " .. RoleName(role) .. ", so the " .. window .. " is left for you.")
	end
	return onlyRoleTicked
end

-- Answers the role check the way the window's own Accept button does: store
-- which roles are ticked, then accept. Returns the roles as words for the chat
-- line, or nil when the role check is left to the player.
local function AcceptRoleCheck()
	local isBattleground = select(6, GetLFGRoleUpdate())

	local role = RoleToAnswerWith()
	if role then
		SetTicks(isBattleground, role == "TANK", role == "HEALER", role == "DAMAGER")
	end

	-- Read the ticks back instead of trusting them: what is ticked now is what
	-- the game sends, and all the chat line may claim.
	local tank, healer, damage = GetTicks(isBattleground)
	if role and not TookRole(role, tank, healer, damage, "role check") then
		return
	end

	-- Without a role the game's own Accept button stays greyed out. When the
	-- game refuses the answer, the window stays for the player too.
	if not (tank or healer or damage) or not CompleteLFGRoleCheck(true) then
		return
	end

	return RoleNames(tank, healer, damage)
end

-- The game's own Accept button closes the window once the game has taken the
-- answer. Closing it does not decline.
local function HideRoleCheckWindow()
	if LFDRoleCheckPopup and StaticPopupSpecial_Hide then
		StaticPopupSpecial_Hide(LFDRoleCheckPopup)
	end
end

-- Presses Sign Up in the window the game opens when you sign up for a premade
-- group yourself. Signing up needs a real click; the click that opened the
-- window still counts while it opens, so this runs as the window shows.
-- Holding Shift leaves the window alone, to change role or write a note.
local function AnswerSignUpWindow(window)
	if not QueuesForMe() or IsShiftKeyDown() then return end

	local role = RoleToAnswerWith()
	if role then
		SetTicks(false, role == "TANK", role == "HEALER", role == "DAMAGER")
		-- Have the window show the new ticks: they are what Sign Up sends.
		if LFGListApplicationDialog_UpdateRoles then
			LFGListApplicationDialog_UpdateRoles(window)
		end
	end

	-- A role this character cannot fill has no button in the window.
	local function IsTicked(button)
		return button:IsShown() and button.CheckButton:GetChecked() and true or false
	end
	local tank, healer, damage = IsTicked(window.TankButton), IsTicked(window.HealerButton), IsTicked(window.DamagerButton)
	if role and not TookRole(role, tank, healer, damage, "sign-up window") then
		return
	end

	-- The game greys Sign Up out while no role is ticked.
	if not window.SignUpButton:IsEnabled() then return end

	window.SignUpButton:Click()
	Announce("sign-up", "signed up as " .. RoleNames(tank, healer, damage) .. ".",
		"Hold Shift as you sign up to choose the role or write a note yourself. /aai options to change this.")
end

------------------------------------------------------------------------
-- Options panel
------------------------------------------------------------------------

local panel = CreateFrame("Frame")
panel.name = ADDON_TITLE
panel:Hide()

local checkboxes = {}

local function RefreshPanel()
	for _, checkbox in ipairs(checkboxes) do
		checkbox:SetChecked(checkbox.getValue())
	end
end

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ADDON_TITLE)

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Automatically accepts incoming party and raid invites.")

-- How far the choices under a checkbox sit to its right.
local INDENT = 28

-- x, y: where the box starts relative to the bottom left of what is above it.
-- Left out, it sits straight below with a small gap.
local function AddCheckbox(anchor, label, getValue, setValue, x, y, size)
	local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	checkbox:SetSize(size or 26, size or 26)
	checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -8)

	-- Own label rather than the template's, whose field name differs
	-- between game versions.
	local text = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
	text:SetText(label)
	-- Let a click on the label toggle the box too.
	checkbox:SetHitRectInsets(0, -(text:GetStringWidth() + 4), 0, 0)

	checkbox.getValue = getValue
	checkbox:SetScript("OnClick", function(self)
		setValue(self:GetChecked() and true or false)
	end)

	checkboxes[#checkboxes + 1] = checkbox
	return checkbox
end

-- A heading with a list of choices under it, indented below a checkbox. One
-- choice is always ticked: clicking one picks it, and the refresh unticks the
-- others. choices: { value, label } each; a nil value is the choice in force
-- while nothing is saved. x: left out when straight under a checkbox, 0 when
-- under something already indented. Returns the last row, to place what comes
-- below.
local function AddChoices(anchor, heading, choices, getChoice, setChoice, x)
	local text = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or INDENT, -4)
	text:SetText(heading)

	local last = text
	for _, choice in ipairs(choices) do
		local value, label = choice[1], choice[2]
		last = AddCheckbox(last, label, function()
			return getChoice() == value
		end, function()
			setChoice(value)
			RefreshPanel()
		end, 0, -2, 22)
	end
	return last
end

-- Called at login, when it is known whether this game version has role windows.
local function AddCheckboxes()
	local last = AddCheckbox(subtitle, "Auto-accept invites", IsEnabled, function(checked)
		GetDB().disabled = not checked
	end)

	last = AddCheckbox(last, "Not while I'm in a queue (accepting takes me out of it)", function()
		return not AcceptsWhileQueued()
	end, function(checked)
		GetDB().evenInQueue = not checked
	end, INDENT, 0, 22)

	last = AddChoices(last, "From:", {
		{ nil, "Everyone" },
		{ "FRIENDS_GUILD", "Friends and guild members" },
		{ "FRIENDS", "Friends only" },
		{ "GUILD", "Guild members only" },
	}, AcceptsFrom, function(from)
		GetDB().from = from
	end, 0)

	if hasRoleWindows then
		last = AddCheckbox(last, "Automatically queue for me", QueuesForMe, function(checked)
			GetDB().noAutoQueue = not checked
		end, -INDENT)

		local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		note:SetPoint("TOPLEFT", last, "BOTTOMLEFT", INDENT, 0)
		note:SetJustifyH("LEFT")
		note:SetText("Answers the role window when your group's leader queues, and when you sign up for a group yourself.\n"
			.. "Hold Shift as you sign up to choose the role or write a note yourself.")

		last = AddChoices(note, "Queue as:", {
			{ nil, "My current specialization's role" },
			{ "TANK", RoleName("TANK") },
			{ "HEALER", RoleName("HEALER") },
			{ "DAMAGER", RoleName("DAMAGER") },
		}, ChosenRole, function(role)
			GetCharDB().role = role
		end, 0)
	end

	AddCheckbox(last, "Print a chat message when something is accepted", IsChatty, function(checked)
		GetDB().quiet = not checked
	end, -INDENT)
end

panel:SetScript("OnShow", RefreshPanel)

-- Hooks the game's Settings window looks for. Changes apply the moment a box
-- is clicked, so there is nothing to commit or reset.
panel.OnCommit = function() end
panel.OnDefault = function() end
panel.OnRefresh = RefreshPanel

local category

local function RegisterPanel()
	if Settings and Settings.RegisterCanvasLayoutCategory then
		category = Settings.RegisterCanvasLayoutCategory(panel, ADDON_TITLE)
		Settings.RegisterAddOnCategory(category)
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

local function OpenOptions()
	if InCombatLockdown() then
		print(PREFIX .. "the options can't be opened in combat.")
		return
	end

	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice on purpose: the old options window only scrolls to the
		-- right entry on the second call.
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end

------------------------------------------------------------------------
-- Accepting invites and answering role windows
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PARTY_INVITE_REQUEST")

frame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		local hasRoleCheck = CompleteLFGRoleCheck ~= nil and LFDRoleCheckPopup ~= nil
		if hasRoleCheck then
			self:RegisterEvent("LFG_ROLE_CHECK_SHOW")
		end
		if LFGListApplicationDialog then
			LFGListApplicationDialog:HookScript("OnShow", AnswerSignUpWindow)
		end
		hasRoleWindows = hasRoleCheck or LFGListApplicationDialog ~= nil
		AddCheckboxes()
		RegisterPanel()
	elseif event == "PARTY_INVITE_REQUEST" then
		if not IsEnabled() then return end

		local inviter, _, _, _, _, _, inviterGUID = ...
		-- An invite from someone the options leave out gets the normal popup.
		if not IsWelcome(inviterGUID) then return end

		-- On retail the inviter's name can be a "secret" value that addons may
		-- not read; only print it when it is a normal string.
		local who = ""
		if type(inviter) == "string" and not (issecretvalue and issecretvalue(inviter)) then
			who = " from " .. inviter
		end

		if not AcceptsWhileQueued() and WouldLeaveQueue() then
			Announce("queued", "left the invite" .. who .. " for you: accepting it takes you out of your queue.",
				"/aai options to change this.")
			return
		end

		AcceptGroup()

		-- Don't hide the invite popup yet: the default UI may not have shown it
		-- at this point, and closing it before we are in the group sends a
		-- decline. Wait until we have joined.
		self:RegisterEvent("GROUP_ROSTER_UPDATE")

		Announce("invite", "accepted invite" .. who .. ".", "/aai options to change this.")
	elseif event == "GROUP_ROSTER_UPDATE" then
		-- The roster also changes for other reasons, such as leaving the group
		-- we were in just before. Only being in a group means the invite is done.
		if not IsInGroup() then return end

		self:UnregisterEvent("GROUP_ROSTER_UPDATE")
		StaticPopup_Hide("PARTY_INVITE")
		-- Retail shows a separate popup for invites that carry a role choice.
		if LFGInvitePopup and StaticPopupSpecial_Hide then
			StaticPopupSpecial_Hide(LFGInvitePopup)
		end
	elseif event == "LFG_ROLE_CHECK_SHOW" then
		local roles = QueuesForMe() and AcceptRoleCheck()
		if roles then
			-- On the next frame, because the game may not have opened the
			-- window yet when this runs.
			C_Timer.After(0, HideRoleCheckWindow)
			Announce("role check", "accepted the role check as " .. roles .. ".", "/aai options to change this.")
		end
	end
end)

------------------------------------------------------------------------
-- Slash command
------------------------------------------------------------------------

SLASH_AUTOACCEPTINVITE1 = "/aai"
SlashCmdList["AUTOACCEPTINVITE"] = function(msg)
	msg = (msg or ""):lower():match("^%s*(.-)%s*$")

	if msg == "options" or msg == "config" or msg == "menu" then
		OpenOptions()
		return
	end

	local db = GetDB()

	-- Commands only switch things on and off. Whose invites and which role are
	-- picked in the options panel.
	if msg == "queue" then
		if not hasRoleWindows then
			print(PREFIX .. "this game version has no group finder to queue in.")
			return
		end

		db.noAutoQueue = QueuesForMe()
		RefreshPanel()

		local as = ChosenRole() and RoleName(ChosenRole()) or "your current specialization's role"
		if QueuesForMe() then
			print(PREFIX .. "queueing for you |cff00ff00ON|r - as " .. as .. ".")
		else
			print(PREFIX .. "queueing for you |cffff0000OFF|r - role windows are left for you to answer. When on: as " .. as .. ".")
		end
		return
	end

	if msg == "" then
		db.disabled = not db.disabled
	elseif msg == "on" then
		db.disabled = false
	elseif msg == "off" then
		db.disabled = true
	else
		print(PREFIX .. "usage: /aai (toggle), /aai on, /aai off, /aai queue, /aai options")
		return
	end

	RefreshPanel()

	local whose = ({ FRIENDS_GUILD = "friends and guild members", FRIENDS = "friends", GUILD = "guild members" })[AcceptsFrom()]
		or "everyone"
	if IsEnabled() then
		print(PREFIX .. "|cff00ff00ON|r - accepting party invites from " .. whose .. ".")
	else
		print(PREFIX .. "|cffff0000OFF|r - invites will show the normal popup. When on: from " .. whose .. ".")
	end
end
