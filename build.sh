#!/usr/bin/env bash
set -euo pipefail

mod_name="fuzz_recoil"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lua_file="$script_dir/gamedata/scripts/fuzz_recoil.lua"
[[ -e "$lua_file" ]] || {
	echo "Not found: $lua_file"
	exit 1
}

version="$(awk -F'"' '/fuzz_recoil[[:space:]]*=[[:space:]]*{[[:space:]]*version[[:space:]]*=[[:space:]]*"/{print $2; exit}' "$lua_file")"
[[ -n "$version" ]] || {
	echo "Can't parse fuzz_recoil.version from: $lua_file"
	exit 1
}

out_root="${script_dir}/output/${mod_name}_${version}"
if [[ -d "$out_root" ]]; then
	rm -r "$out_root"
fi
mkdir -p "$out_root"

copy_files() {
	local folder="$1"
	shift

	local out_dir="${out_root}/${folder}"
	mkdir -p "$out_dir"

	local f rel dest src
	for f in "$@"; do
		src="${script_dir}/${f}"
		[[ -e "$src" ]] || {
			echo "Not found: $src"
			exit 1
		}

		rel="${f#./}"

		# rename lua
		dest="$out_dir/$rel"
		if [[ "$dest" == *.lua ]]; then
			dest="${dest%.lua}.script"
		fi

		mkdir -p "$(dirname "$dest")"
		cp -f "$src" "$dest"
	done
}

copy_files "00 Core" \
	"gamedata/anims/camera_effects/onerad.anm" \
	"gamedata/scripts/fuzz_recoil.lua" \
	"gamedata/scripts/fuzz_recoil_converter.lua" \
	"gamedata/scripts/fuzz_recoil_logger.lua" \
	"gamedata/scripts/fuzz_recoil_utils.lua"

copy_files "01 Shot_fx_disable" \
	"gamedata/scripts/zzzz_shot_effect_patch.script"

copy_files "02 ImGui_Modules" \
	"gamedata/scripts/fuzz_recoil_imgui.lua"

out_zip="./output/${mod_name}_${version}.7z"
if [[ -e "$out_zip" ]]; then
	rm "$out_zip"
fi

7z a "$out_zip" "${out_root}/*"
