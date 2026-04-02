# AlphaUI

Our official UI enhancement addon pack for the 0.5.3 client.

## Layout

- `Interface/` is the runtime overlay normal users can install.
- `src/` contains the split `AlphaUI` sources and build helpers for developers.

## For Users

Use the files under `Interface/`. That tree contains only what the client needs to load `AlphaUI`.

## Features

### Modules

- `Buff Durations`: Shows time remaining on player buffs and debuffs.
- `Instant Quest Text`: Removes quest text fades and displays quest text immediately.
- `Unit Frames`: Repositions player and target frames, applies the alternative frame style, and controls portraits/status text.
- `Action Bars`: Applies the custom stock-bar layout and bag/microbutton tweaks.
- `Clock`: Shows a movable in-game clock window.
- `Always Track`: Keeps Find Minerals, Find Herbs, and Find Treasure active when learned.
- `Bagnon`: Replaces the stock inventory bags with one merged frame.
- `Talents Button`: Adds a talents micro button beside the main menu icons.
- `Target Auras`: Shows tracked target aura icons from the shared addon API.
- `Target Distance`: Shows distance to your current target with local map math and server fallback.
- `Tutorial Extend`: Shows the stock tutorial prompts again for brand new characters.
- `Extended Stats`: Shows an expanded stats panel beside the character sheet.
- `Reload Button`: Adds a Reload UI button to the escape menu.
- `Chat Copy`: Adds a chat log copy window and button for the default chat frame.
- `Client Settings`: Applies small client-side behavior toggles.
- `Class Portraits`: Replaces player and target 3D portraits with class icon circles.
- `Guild Frame`: Adds a guild roster tab to the Social frame.
- `AtlasLoot`: Adds a basic Atlas browser with dungeon maps and loot buttons.

### Extra Options

- `Show warning timers in white`
- `Show target auras`
- `Show aura timer numbers`
- `Show unit status text`
- `Use 24-hour time`
- `Show talents button`
- `Auto-loot`

### Adjustments

- `Unit Frames Vertical Offset`
- `Unit Frames Horizontal Offset`
- `Clock Time Offset`
- `Action Bar Horizontal Offset`

## For Developers

Edit the split sources under `src/Interface/FrameXML/AlphaUI/`, then run:

```bash
./src/publish_runtime.sh
```

That rebuilds `AlphaUI_Bundle.lua` from the split sources and publishes the runtime files back into this repo's `Interface/` tree.

It does not sync anything into a local WoW install. It only updates the files that ship in this repository.

More detail is in `src/README.md`.

## Thanks

- `Es` for the original EsUI addon.
- `ᴇʏᴇᴠᴏᴜ` for Always Track.
- `Davir` for AtlasLoot.
