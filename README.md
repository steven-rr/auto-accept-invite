# AutoAcceptInvite

A tiny World of Warcraft addon that automatically accepts every incoming party or raid invite.

---

## What it does

- Accepts a group invite the moment it arrives, and closes the invite popup once you have joined.
- Can also answer the window that asks for your role, when your group's leader queues and when you sign up for a group yourself. This is off until you switch it on.
- Prints a line in chat saying what was accepted. This can be turned off.
- Can be switched off at any time to get the normal invite popup back.

Out of the box it accepts **every** invite. That includes invites from players you don't know, and invites that arrive while you are queued for a dungeon, which takes you out of the queue. Switch it off when you don't want that.

### Whose invites

Under **From** in the options you choose whose invites it accepts:

- **Everyone** (the default)
- **Friends and guild members**
- **Friends only**: your friends list and your Battle.net friends
- **Guild members only**

An invite from anyone else gets the normal popup, for you to answer.

### Role windows

The game asks for your role in two windows. With **Answer the role window for me** on, the addon answers both, and the chat line names the role it answered with:

- **The role check**, when your group's leader queues for a dungeon or battleground, or signs the group up for a premade group.
- **The sign-up window**, when you sign up for a premade group yourself. Hold Shift as you sign up to see the window and answer it yourself, for example to write a note.

You choose which role it queues you as, under **Queue as** in the options:

- **My current specialization's role** (the default). On a healing specialization you queue as healer, whatever you ticked the last time.
- **Tank**, **Healer** or **Damage**. Always that role, whatever specialization you are on.

If the game does not take the role, for example Tank on a class that cannot tank, the addon does not answer: the window stays open for you and chat says so.

It does not change anything when you queue from the Dungeon Finder yourself: there you tick your role and click, as always. And it does not press **Enter Dungeon** when the queue pops. The game only lets a player do that.

## Options

Open **Esc > Options > AddOns > AutoAcceptInvite**, or type `/aai options`.

- **Auto-accept invites**: on by default.
- **From**: everyone (the default), friends and guild members, friends only, or guild members only.
- **Answer the role window for me**: off by default. Only shown in game versions that have a dungeon finder.
- **Queue as**: my current specialization's role (the default), Tank, Healer or Damage.
- **Print a chat message when something is accepted**: on by default.

Changes apply as soon as you click, and the settings are shared by every character on the account.

## Commands

- `/aai`: turn auto-accepting invites on or off
- `/aai on`: turn it on
- `/aai off`: turn it off
- `/aai role`: turn answering role windows on or off
- `/aai options`: open the options panel

## Installation

1. Download the latest release from the [Releases page](https://github.com/steven-rr/auto-accept-invite/releases)
2. Extract the `AutoAcceptInvite` folder into your `World of Warcraft/_retail_/Interface/AddOns/` directory
3. Restart WoW or type `/reload` if you're already logged in

## License

MIT
