# OctoWoW inspected appearances

Verified against the installed `Data/patch-4.mpq` on 2026-10-17. This archive
overrides the older inspect implementation in `patch.MPQ`. The older source
alone does not explain OctoWoW's pink appearance line.

## Native behavior

- `Interface/AddOns/Blizzard_InspectUI/InspectPaperDollFrame.lua:32` sends
  `INSShowTransmogs` with prefix `TW_CHAT_MSG_WHISPER<player name>` and channel
  `GUILD`. Opening the native paper doll requests it, and an inventory change
  schedules another request after 1.5 seconds.
- `Interface/FrameXML/Turtle_TransmogUI/Turtle_TransmogUI.lua:376` answers that
  request on the inspected player's client. It sends `INSTransmogs;start;0;0`,
  followed by `INSTransmogs;slot;appearanceID;equippedItemID` for equipped
  transmogged items. This implementation sends no end marker.
- `Interface/AddOns/Turtle_General/Turtle_General.lua:21` routes incoming
  `TW_CHAT_MSG_WHISPER` messages to the native inspect message handler.
- `InspectPaperDollFrame.lua:165` adds the text to tooltip line 2. It requires
  the native inspect paper doll to be visible and the tooltip to belong to one
  of its named gear buttons. Calling `SetInventoryItem` on a custom button
  therefore does not add that line.
- `Turtle_TransmogUI.lua:1510` handles the player's own gear using the global
  `TransmogStatus[equippedItemID]` table and similarly checks native character
  slot ownership.

The inspected appearance is separate from the base item hyperlink and the
standard inventory inspection response. It requires the other player's client
to answer the same protocol used by the default inspect window.

## zInspect integration

zInspect loads the native inspect module, assigns its hidden `InspectFrame.unit`,
then sends the native request on player inspection. This unit assignment is
required by OctoWoW's reply validator even though zInspect does not display the
native inspect window. zInspect accepts replies only from the inspected player
and scopes every reply to that player and equipment slot. The equipped item ID
is retained for diagnostics but is not used as a display gate: OctoWoW can
expose the visible appearance ID through its remote inventory API while the
packet carries the underlying equipped item ID, and the native tooltip likewise
trusts the target-scoped slot. zInspect can read both its own packet cache and OctoWoW's
`INSPECT_TRANSMOG_DATA` cache, covering either event-handler order. A start
packet clears previous slot data. Changing players clears all appearance data
and pending tooltip work. The player's own appearance comes from
`TransmogStatus`.

The tooltip first attempts `SetInventoryItem`, then uses its existing link
fallback when live data is unavailable. zInspect prepends the native localized
`TRANSMOG_CHANGED_TO` label and appearance name in the same pink color. A reply
or a newly cached appearance name can refresh an already hovered slot. Missing
item names are fetched through the hidden scanner tooltip.

An unanswered request is retried at most twice at 1.5-second intervals. The
first valid reply stops retries. Inventory refresh requests use the native
1.5-second debounce. Appearance polling runs only while an unresolved tooltip
is hovered; regular gear and talent query cadence is unchanged.

`/zi tmog` prints the current target, request and packet counts, populated local
and native slot counts, and the last packet sender for live diagnosis.

## Validation

Run `python -m unittest discover -s tests -v` with Lupa installed. The transmog
tests load the complete addon under Lua 5.1 and cover protocol routing, sender
validation, remote visible/equipped ID differences, target changes, reset packets, self inspection,
asynchronous item names, live tooltip preference, hyperlink fallback, retry
limits, and inventory debounce. Existing gear polling regressions also run.

In-game verification: reload the UI, inspect a player whose transmog is visible
through the default inspect route, and hover the same slot in zInspect. Check
self inspection and switching to a different target while hovering gear.

## Source fingerprints

SHA-256 of the unmodified archive members:

| Archive member | SHA-256 |
| --- | --- |
| `InspectPaperDollFrame.lua` | `250ac4458b92ad48f4438241157156b7c83d8aa0f829ed2fb8a65a6437abe6ef` |
| `InspectPaperDollFrame.xml` | `64609c5aadbe2238840111625de3ab7654c6d2e05e95be2e4db32494f5b814b7` |
| `Turtle_TransmogUI.lua` | `11f42e4e078d315039a411066cb278ddcf6e85cb5416cbb76c5345a66b8005b4` |
| `Turtle_General.lua` | `d2fccd22db2a4db004cec95f21c7e7935ae24f4930b0e29c689fd4a4558070fd` |
