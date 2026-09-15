# zInspect

A sleek, modern inspection suite for Vanilla World of Warcraft (1.12.1 / Turtle WoW).

Part of the **zSuite** collection of addons.

---

## Features

- **Interactive 3D Model Viewport**:
  - **Left-Click Drag**: Rotate character/creature model.
  - **Right-Click Drag**: Pan/move model (X/Y).
  - **Mouse Wheel**: Smooth zoom toward cursor position.
  - **Reset Button**: One-click camera reset.
- **Universal Target Inspection**:
  - **Friendly Players**: Standard inspection with item links and stats.
  - **Out-of-Range Streaming**: Window opens immediately with 3D model; gear automatically streams in the instant the player enters interaction range. Session caching displays last-known gear while waiting.
  - **Enemy / Cross-Faction Players**: Extracts visible equipped items (including via `zAPI.dll`), resolves item links/qualities, and avoids red texture artifacts.
  - **NPCs & Creatures**: Displays 3D model, level, creature type/family, current/max HP and Mana/Rage/Energy, and target-of-target info.
- **Integrated Tabs**:
  - **Character Tab**: 19 sleek, border-colored equipment slots (32x32) with item count, quality coloring, and average item level calculation.
    - **Shift-Click Slot**: Links item into chat.
    - **Ctrl-Click Slot**: Previews item in Dressing Room.
  - **Honor Tab**: Fully embedded Vanilla PvP honor summary (Session, Yesterday, This Week, Last Week, Lifetime stats, and Rank Progress Bar) cleanly scaled with non-blocking mouse interaction.
  - **Talents Tab**: Embedded talent tree with custom tree tabs (e.g. Beast Mastery, Marksmanship, Survival), crash-safe Turtle WoW talent data mapping, and proportional scaling fitting all 7 tiers comfortably without clipping or window bleed.
- **Sleek & Discrete Design**:
  - Matches standard Blizzard `CharacterFrame` and pfUI dimensions (338 x 424 px).
  - Flat, borderless dark aesthetic with subtle branding.
  - Movable window with saved position across sessions.

---

## Keybindings & Slash Commands

- Default hotkeys: `[` and `]` to inspect current target.
- Slash commands:
  - `/zinspect`
  - `/zi`

---

## Installation

1. Download or clone this repository into your WoW AddOns folder:
   ```
   World of Warcraft\Interface\AddOns\z_Inspect
   ```
2. Make sure the folder is named **`z_Inspect`** (not `z_Inspect-main`).
3. Launch World of Warcraft and enable **zInspect** in the AddOns menu.

---

## Author

- **Zab** / **Samer**
