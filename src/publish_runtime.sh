#!/usr/bin/env bash
set -euo pipefail

# Rebuild the bundled AlphaUI addon from src/ and publish the runtime files
# into this repository's Interface/ tree.

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src_framexml_dir="$repo_root/src/Interface/FrameXML"
src_main_dir="$src_framexml_dir/AlphaUI"
runtime_framexml_dir="$repo_root/Interface/FrameXML"
runtime_main_dir="$runtime_framexml_dir/AlphaUI"

"$src_main_dir/build_bundle.sh"

mkdir -p "$runtime_main_dir/Media"

cp "$src_framexml_dir/FrameXML.toc" "$runtime_framexml_dir/FrameXML.toc"

cp \
  "$src_main_dir/AlphaUI.xml" \
  "$src_main_dir/AlphaUI_Init.lua" \
  "$src_main_dir/AlphaUI_Chat.lua" \
  "$src_main_dir/AlphaUI_API.lua" \
  "$src_main_dir/AlphaUI_Config.lua" \
  "$src_main_dir/AlphaUI_Registry.lua" \
  "$src_main_dir/AlphaUI_Bundle.lua" \
  "$runtime_main_dir/"

cp -R "$src_main_dir/Media/." "$runtime_main_dir/Media/"

printf '%s\n' "Published AlphaUI runtime files into $runtime_main_dir"
