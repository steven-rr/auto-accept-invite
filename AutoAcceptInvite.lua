-- AutoAcceptInvite: accepts every incoming party/raid invite.
--
-- Options panel: Esc > Options > AddOns > AutoAcceptInvite
-- /aai            toggle on/off
-- /aai on|off     enable / disable
-- /aai options    open the options panel

local ADDON_TITLE = "AutoAcceptInvite"
local PREFIX = "|cff33ff99AutoAcceptInvite|r: "

------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------
-- Saved account-wide. Both are "on" while unset, so a fresh install needs
-- no setup.
--   AutoAcceptInviteDB.disabled   true = do not auto-accept
--   AutoAcceptInviteDB.quiet      true = no chat line when accepting

local function GetDB()
	AutoAcceptInviteDB = AutoAcceptInviteDB or {}
	return AutoAcceptInviteDB
end

local function IsEnabled()
	return not GetDB().disabled
end

local function IsChatty()
	return not GetDB().quiet
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

local function AddCheckbox(anchor, label, getValue, setValue)
	local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	checkbox:SetSize(26, 26)
	checkbox:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)

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

local enableBox = AddCheckbox(subtitle, "Auto-accept invites", IsEnabled, function(checked)
	GetDB().disabled = not checked
end)

AddCheckbox(enableBox, "Print a chat message when an invite is accepted", IsChatty, function(checked)
	GetDB().quiet = not checked
end)

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
-- Accepting invites
------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PARTY_INVITE_REQUEST")

frame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_LOGIN" then
		RegisterPanel()
	elseif event == "PARTY_INVITE_REQUEST" then
		if not IsEnabled() then return end

		local inviter = ...
		AcceptGroup()

		-- Don't hide the invite popup yet: the default UI may not have shown it
		-- at this point, and closing it before we are in the group sends a
		-- decline. Wait until the roster actually changes.
		self:RegisterEvent("GROUP_ROSTER_UPDATE")

		if IsChatty() then
			-- On retail the inviter's name can be a "secret" value that addons
			-- may not read; only print it when it is a normal string.
			if type(inviter) == "string" and not (issecretvalue and issecretvalue(inviter)) then
				print(PREFIX .. "accepted invite from " .. inviter .. ".")
			else
				print(PREFIX .. "accepted invite.")
			end
		end
	elseif event == "GROUP_ROSTER_UPDATE" then
		self:UnregisterEvent("GROUP_ROSTER_UPDATE")
		StaticPopup_Hide("PARTY_INVITE")
		-- Retail shows a separate popup for invites that carry a role choice.
		if LFGInvitePopup and StaticPopupSpecial_Hide then
			StaticPopupSpecial_Hide(LFGInvitePopup)
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
	if msg == "" then
		db.disabled = not db.disabled
	elseif msg == "on" then
		db.disabled = false
	elseif msg == "off" then
		db.disabled = true
	else
		print(PREFIX .. "usage: /aai (toggle), /aai on, /aai off, /aai options")
		return
	end

	RefreshPanel()

	if IsEnabled() then
		print(PREFIX .. "|cff00ff00ON|r - accepting all party invites.")
	else
		print(PREFIX .. "|cffff0000OFF|r - invites will show the normal popup.")
	end
end
