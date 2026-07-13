## Fuzz Recoil

Physics based 3D recoil system inspired by Escape from tarkov.\
This an Alpha test to collect bugs.

### NOTE

- This mod is still in early stage of development,everything could be changed in the future.
- Expecting bugs,I haven't done enough test definitely
- It's safe to add or remove in mid-game
- NO MCM configurations, it will be implented once the mod in a stable stage.Everything is in ImGui for now.

## Compatibility

- Out-of-the-box compatibility with any weapon pack

### Installation

1. Download mod from Release page,Install with MO2.Do NOT clone or download zip.
2. Options

- 01 disable shot_fx(camera-shake) from gboobs
- 02 Imgui editor

3. In-game settings
   <img width="2692" height="746" alt="swappy-20260708-185300" src="https://github.com/user-attachments/assets/5f2565a5-2159-4ca0-9d2c-909257b32ab9" />
   <img width="3781" height="530" alt="swappy-20260708-185223" src="https://github.com/user-attachments/assets/f5382907-e53e-4c6a-ab9b-2b62fcf25557" />

### Issue and bug report

- Logs and how to reproduce
- DO NOT DM
- PR would be greatly appreciated.

### Know Bugs And Limitations

1. All recoil profile is converted from vanilla recoil data,strange behaviour is expected.

### TODO

1. Weapon weight affects recoil
2. API for modder (skill,buff, etc.)

### Recoil profile Customization

1. Open Fuzz recoil editor in ImGui.
2. Open weapon profile.Shoot one bullet to refresh the profile
3. Edit (**You will lost every change you made if you switch weapon.**)
4. Export ltx file,it will be located in your game bin folder.
5. Copy the exported ltx file to `gamedata/configs` or create a mod in MO2.
6. Restart the game
<img width="1091" height="1142" alt="swappy-20260709-012222" src="https://github.com/user-attachments/assets/30910141-071e-49ac-98f0-baafb67130b0" />

###Performance
<img width="1226" height="918" alt="fr-perf" src="https://github.com/user-attachments/assets/394c6149-3ee5-43d4-a737-b400ec3763e9" />

