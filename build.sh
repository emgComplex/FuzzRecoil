#!/usr/bin/env bash
set -euo pipefail

should_release=0
while getopts ":r" opt; do
	case "$opt" in
	r) should_release=1 ;;
	\?)
		echo "bad arg:-$OPTARG" >&2
		exit 1
		;;
	esac
done

shift $((OPTIND - 1))

mod_name="fuzz_recoil"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

lua_file="$script_dir/gamedata/scripts/fuzz_recoil.lua"
[[ -e "$lua_file" ]] || {
	echo "Not found: $lua_file"
	exit 1
}

version="$(grep -nE 'version[[:space:]]*=' "$lua_file" | head -n1 | sed -nE 's/.*"([^"]+)".*/\1/p')"
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
	"./gamedata/anims/camera_effects/oneshove.anm" \
	"gamedata/scripts/fuzz_recoil_converter.lua" \
	"gamedata/scripts/fuzz_recoil_logger.lua" \
	"gamedata/scripts/fuzz_recoil_utils.lua" \
	"gamedata/scripts/fuzz_recoil_profile.lua" \
	"gamedata/scripts/fuzz_recoil_modifier.lua" \
	"gamedata/scripts/fuzz_recoil_cam_recoil.lua" \
	"gamedata/scripts/fuzz_recoil_hud_recoil.lua" \
	"gamedata/scripts/fuzz_recoil_event.lua" \
	"gamedata/scripts/fuzz_recoil_punch.lua" \
	"gamedata/scripts/fuzz_recoil_mcm.lua" \
	"gamedata/configs/text/eng/ui_mcm_fuzz_recoil.xml" \
	"gamedata/scripts/fuzz_recoil.lua"

copy_files "01 Shot_fx_disable(camshake)" \
	"gamedata/scripts/zzzz_shot_effect_patch.script"

copy_files "02 ImGui_Editors" \
	"gamedata/scripts/fuzz_recoil_imgui.lua" \
	"gamedata/scripts/fuzz_recoil_impacts.lua"

copy_files "03 Gamma_Patch" \
	"./gamedata/configs/mod_system_z_fuzz_recoil_gamma_patch_pistol.ltx" \
	"./gamedata/configs/mod_system_z_fuzz_recoil_gamma_patch_sniper.ltx"

copy_files "04 MASG_Patch" \
	"./gamedata/scripts/fuzz_recoil_zz_masg_patch.lua"

copy_files "05 No_Weapon_Inertion" \
	"./gamedata/configs/mod_system_zzzzz_fuzz_no_inertion.ltx" \
	"./gamedata/scripts/fuzz_recoil_zz_inertia_patch.lua"

out_zip="./output/${mod_name}_${version}.7z"
if [[ -e "$out_zip" ]]; then
	rm "$out_zip"
fi

7z a "$out_zip" "${out_root}/*"

if ((should_release)); then
	gh release create "${version}" "${out_zip}" --generate-notes --latest "$@"
fi
