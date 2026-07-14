## Fuzz Recoil

Physics based 3D recoil system inspired by Escape from tarkov.\
This an Alpha test to collect bugs.

## Feature
* Physics-based 3D recoil system with camera movement, it replaced the vanilla recoil system completely
* The system will auto adapts to vanilla weapon's data ,convert them to new recoil profile in runtime
* Fully customizable per-weapon recoil profile with an ImGUI Editor
* Safe to add or remove in mid-game
* API for modders ,check `fuzz_recoil_modifier.lua`

### Installation

1. Download mod from Release page,Install with MO2.Do NOT clone or download zip.
2. Options
<img width="172" height="111" alt="image" src="https://github.com/user-attachments/assets/ab2f0c14-58e9-43a7-bc35-661113348cd8" />

- 01 disable shot_fx(camera-shake) from gboobs
- 02 Imgui editor

3. In-game settings
   <img width="2692" height="746" alt="swappy-20260708-185300" src="https://github.com/user-attachments/assets/5f2565a5-2159-4ca0-9d2c-909257b32ab9" />


### Know Bugs And Limitations

1. All recoil profile is converted from vanilla recoil data,strange behaviour is expected.

## Compatibility

- Out-of-the-box compatibility with any weapon pack that supported 3DB(that means every gamma weapon)
- dynamic viewmodel will break this mod
- Unicoil is **conflicted** with this mod 
### TODO
- Better recoil for pistol and shotgun
- ~~Better camera recoil~~ 
- ~~Weapon weight affects recoil(won't be implemented, it should reflects on the recoil profile directly)~~
- ~~Recoil scales with scope zoom factor~~
- ~~Upgrades affects recoil~~
- ~~Recoil still increase slowly in stable phase~~
- ~~API for modders (skill,buff, etc.)~~

### Recoil profile Customization

1. Open Fuzz recoil editor in ImGui.
2. Open weapon profile.Shoot one bullet to refresh the profile
3. Edit (**You will lost every change you made if you switch weapon.**)
4. Export ltx file,it will be located in your game bin folder.
5. Copy the exported ltx file to `gamedata/configs` or create a mod in MO2.
6. Restart the game
<img width="1091" height="1142" alt="swappy-20260709-012222" src="https://github.com/user-attachments/assets/30910141-071e-49ac-98f0-baafb67130b0" />

### Performance
<img width="1652" height="498" alt="image" src="https://github.com/user-attachments/assets/8b0f0234-cef7-43a0-bd8e-e57f86f61c01" />


