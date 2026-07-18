## Fuzz Recoil

Physics based 3D recoil system inspired by Escape from tarkov.\
99% weapons are playable,not all of them are lore-accurate,that's up to you , we have an imgui editor inculded.\
Please share you recoil profile ,create a PR or ,even better create you own mod.

## Feature
* Physics-based 3D recoil system with camera movement, it replaced the vanilla recoil system completely
* The system will auto adapts to vanilla weapon's data ,convert them to new recoil profile in runtime
* Fully customizable per-weapon recoil profile with an ImGUI Editor
* Safe to add or remove in mid-game
* API for modders ,check `fuzz_recoil_modifier.lua` , `dyanmic_modifiers` and `static_modifiers` from `fuzz_recoil.lua`

## Rquirement
xray-monolith that supports 3D ballsitic.

## Installation

1. Download mod from Release page,Install with MO2.Do NOT clone or download zip.
2. Options
- 01 disable shot_fx(camera-shake) from gboobs,we have a bulit-in one which cause less dizzyness
- 02 Imgui editor,if you want to edit per-wepaon recoil.
- 03 gamma patch

3. In-game settings: turn off parallax shader in 3dss settings
   <img width="2692" height="746" alt="swappy-20260708-185300" src="https://github.com/user-attachments/assets/5f2565a5-2159-4ca0-9d2c-909257b32ab9" />

## Compatibility

- Out-of-the-box compatibility with any weapon pack that supported 3DB(that means every weapon from gamma)
- `Dynamic viewmodel` will break this mod(no hud reocil),**won't** be fixed.
- `Unicoil` is **conflicted** with this mod 
- Scope from `MASG` will disappear when shooting
- Does not work for 2d scopes

## Know Bugs And Limitations
- Due to the engine limitation,we have to return the camera after shooting,maybe it will be fixed in the future.
- If you have no horizontal recoil,you probably have `Dynamic viewmodel` installed,diable it
- Weapon tilt won't work when shooting

## Recoil profile Customization
1. Open Fuzz recoil editor in ImGui.
2. Open weapon profile.Shoot one bullet to refresh the profile
3. Edit (**You will lost every change you made if you switch weapon.**).It'best to edit a wepaon with no upgrade and make sure you actor is in good shape.
4. Export ltx file,it will be located in your game bin folder.
5. Copy the exported ltx file to `gamedata/configs` or create a mod in MO2.
6. Restart the game
<img width="1091" height="1142" alt="swappy-20260709-012222" src="https://github.com/user-attachments/assets/30910141-071e-49ac-98f0-baafb67130b0" />

## Recoil Customization in detail
TLDR:Recoil is mainly base on Camera recoil power(vertical) and Force Yaw(horizontal)

### TODO
- ~~Better recoil for pistol and shotgun~~
- ~~Better camera recoil~~ 
- ~~Weapon weight affects recoil(won't be implemented, it should reflects on the recoil profile directly)~~
- ~~Recoil scales with scope zoom factor~~
- ~~Upgrades affects recoil~~
- ~~Recoil still increase slowly in stable phase~~
- ~~API for modders (skill,buff, etc.)~~



### Performance
<img width="1652" height="498" alt="image" src="https://github.com/user-attachments/assets/8b0f0234-cef7-43a0-bd8e-e57f86f61c01" />


