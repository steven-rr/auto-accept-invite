# AutoAcceptInvite

A tiny World of Warcraft addon that automatically accepts every incoming party or raid invite.

---

## What it does

- Accepts a group invite the moment it arrives, and closes the invite popup once you have joined.
- Prints a line in chat saying whose invite was accepted. This can be turned off.
- Can be switched off at any time to get the normal invite popup back.

It accepts **every** invite. That includes invites from players you don't know, and invites that arrive while you are queued for a dungeon, which takes you out of the queue. Switch it off when you don't want that.

## Options

Open **Esc > Options > AddOns > AutoAcceptInvite**, or type `/aai options`.

- **Auto-accept invites**: on by default.
- **Print a chat message when an invite is accepted**: on by default.

Changes apply as soon as you click, and the settings are shared by every character on the account.

## Commands

- `/aai`: turn auto-accept on or off
- `/aai on`: turn it on
- `/aai off`: turn it off
- `/aai options`: open the options panel

## Installation

1. Download the latest release from the [Releases page](https://github.com/steven-rr/auto-accept-invite/releases)
2. Extract the `AutoAcceptInvite` folder into your `World of Warcraft/_retail_/Interface/AddOns/` directory
3. Restart WoW or type `/reload` if you're already logged in

## License

MIT
