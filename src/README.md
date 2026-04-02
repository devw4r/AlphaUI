# Source Layout

This folder exists for maintainers.

## Source Of Truth

Edit files in:

- `src/Interface/FrameXML/AlphaUI/`

That tree contains:

- split module sources such as `ActionBars.lua`, `GuildFrame.lua`, `MergedBags.lua`, and `AtlasLoot.lua`
- the bundle script `build_bundle.sh`
- `AlphaUI.xml` and the bootstrap files that load the bundled code
- `Media/` assets used by `AlphaUI`

## Build

To rebuild just the bundle:

```bash
cd src/Interface/FrameXML/AlphaUI
./build_bundle.sh
```

That updates:

- `src/Interface/FrameXML/AlphaUI/AlphaUI_Bundle.lua`

## Publish Runtime Overlay

To rebuild and publish the runtime overlay used by normal users:

```bash
./src/publish_runtime.sh
```

That copies the runtime set into this repo's installable tree:

- `Interface/FrameXML/FrameXML.toc`
- `Interface/FrameXML/AlphaUI/`

Only the runtime files are copied there, not the entire source tree.

This step does not touch a local game client. It only refreshes the runtime files that are meant to be committed or packaged for users.
