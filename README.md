# Hangout

A Discord-style chat window for WoW Forever. Whispers, Battle.net, guild, group and channels in one place, with saved history.

![Hangout open in the game world](Media/screenshot-Main%20window-ingame.png)

## Features

| Area | What you get |
|---|---|
| **Chats** | Whispers, Battle.net whispers, guild, officer, party, raid, instance and channels. Say, yell and emotes in a read-only Nearby chat. |
| **Messages** | Replies, emoji picker, `:shortcode:` autocomplete, link tooltips, copy message or chat. |
| **Contacts** | Class crests and colors, online/AFK/DND status, nicknames, notes, pinned chats, contact cards, member list for guild and group. |
| **Alerts** | Sounds, popups, taskbar flash, mentions of your name or custom keywords, online alerts for chosen contacts. |
| **Quiet time** | Do Not Disturb, timed mute, notification level per chat, optional auto-quiet in instances and raid combat. |
| **Spam control** | Strangers land in Requests. Block players and words, filter channels by word, drop channel repeats. |
| **History** | Search with filters, saved messages, reminders. |
| **Combat** | Window fades, hides or stays visible. |
| **Look** | 17 themes, custom colors, theme sharing by string, text size, opacity. |
| **Language** | English and German. |

**With other Hangout users:** typing indicator, read receipts and reactions. Players without Hangout see none of this.

![Hangout window with the emoji picker open](Media/screenshot-Main%20window-emoji.png)

## Install

1. [Download the ZIP](https://github.com/bhuaysan/Hangout/archive/refs/heads/main.zip).
2. Extract it to `World of Warcraft/_forever_/Interface/AddOns/`.
3. Rename the folder from `Hangout-main` to `Hangout`.
4. Restart the game.

## Open it

- Click the minimap button. Right-click it for options.
- Type `/hangout`.
- Bind a key: Key Bindings > Hangout.

Settings are in the minimap menu and under Options > AddOns > Hangout.

## Shortcuts

No keys are bound by default.

| Key binding | Action |
|---|---|
| Open or close Hangout | Toggles the window |
| Reply to the newest message | Jumps to the latest chat |
| Open the next unread chat | Steps through unread chats |
| Quick switch to a chat | Opens the chat finder |

While typing in the message box:

| Key | Action |
|---|---|
| `Alt+Up` / `Alt+Down` | Previous or next chat |
| `Alt+Shift+Up` / `Alt+Shift+Down` | Previous or next unread chat |
| `Ctrl+K` | Quick switch |
| `Up` / `Down` | Sent message history |
| `Tab` | Complete a name |

## Commands

| In the game's chat | Action |
|---|---|
| `/hangout` | Open or close |
| `/hangout read` | Mark all as read |
| `/hangout dnd` | Toggle Do Not Disturb |
| `/hangout keyword add <word>` | Add a mention keyword (`remove` deletes one) |
| `/hangout combat fade` | Combat behavior: `fade`, `hide` or `off` |
| `/hangout list` | List chats |
| `/hangout show <number>` | Print a chat |
| `/hangout test` | List test situations, such as a fake whisper |

| In the Hangout message box | Action |
|---|---|
| `/mute`, `/unmute` | Mute the chat. Timed: `/mute 30m`, `/mute 2h`, `/mute tomorrow` |
| `/pin`, `/unpin` | Pin the chat |
| `/unread` | Mark as unread |
| `/nick <name>`, `/note <text>`, `/card` | Nickname, note, contact card (whispers only) |
| `/saved` | Show saved messages |
| `/search <text>` | Search |

## Search filters

| Filter | Finds |
|---|---|
| `from:Name` | Messages by that player |
| `in:this` | Only the open chat |
| `has:link` | Messages with links |
| `is:saved` | Saved messages |
| `before:2026-11-09`, `after:2026-11-09` | Messages by date |

## Chat restrictions

WoW sometimes blocks addons from chat, for example in dungeons. Normal chat keeps working.

- **Incoming:** messages appear as restricted rows. Hangout fills in the text when the restriction ends.
- **Outgoing:** up to 20 messages wait in an outbox. Open Hangout and press Enter to send them once it ends.

## Good to know

- Whispers are kept 90 days, guild and group 14 days. You can change both.
- Channels are saved only if you right-click one and choose to.
- Nearby chat is never saved.
- The outbox is lost on logout or `/reload`.
- Filters and blocks only affect Hangout. Normal chat still shows everything.

## Bugs and ideas

[Open an issue](https://github.com/bhuaysan/Hangout/issues).

## Credits

Emoji by Twemoji, CC-BY 4.0. Font: Lato. License texts are in `Media/`.

## License

Code is under the [MIT License](LICENSE).
