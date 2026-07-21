## Fuzz Recoil

Physics based 3D recoil system inspired by Escape from tarkov.\
99% weapons are playable,not all of them are lore-accurate,that's up to you , we have an imgui editor inculded.\
Please share you recoil profile ,create a PR or ,even better create you own mod.

## Feature
* Physics-based 3D recoil system with camera movement, it replaced the vanilla recoil system completely
* The system will auto adapts to vanilla weapon's data ,convert them to new recoil profile in runtime
* Fully customizable per-weapon recoil profile with an ImGUI Editor
* Safe to add or remove in mid-game
* API for modders ,see `fuzz_recoil_modifier.lua` , [Modifiers](https://github.com/emgComplex/FuzzRecoil/blob/507b34d045d69ef8f016321cd2b9dac0e685b8c4/gamedata/scripts/fuzz_recoil.lua#L919),[Events](https://github.com/emgComplex/FuzzRecoil/blob/507b34d045d69ef8f016321cd2b9dac0e685b8c4/gamedata/scripts/fuzz_recoil.lua#L7)

## Rquirement
- xray-monolith that supports 3D ballsitic.
- MCM for configuration 

## Installation

1. Download mod from Release page,Install with MO2.Do NOT clone or download zip.
2. Options
- 01 disable shot_fx(camera-shake) from gboobs,we have a bulit-in one which cause less dizzyness
- 02 Imgui editor,if you want to edit per-wepaon recoil.
- 03 gamma patch
- 04 enable this if you play with MASG

3. In-game settings: turn off parallax shader in 3dss settings
   <img width="2692" height="746" alt="swappy-20260708-185300" src="https://github.com/user-attachments/assets/5f2565a5-2159-4ca0-9d2c-909257b32ab9" />
## Configuration
Basic settings is in MCM , you can hover on every option for more info.
<img width="2616" height="1456" alt="rc-mcm" src="https://github.com/user-attachments/assets/eb8e8fb7-7340-46f4-bd1e-057690b7d723" />


## Compatibility

- Out-of-the-box compatibility with any weapon pack that supported 3DB(that means every weapon from gamma)
- `Dynamic viewmodel` will break this mod(no hud reocil),**won't** be fixed.
- `Unicoil` is **conflicted** with this mod 
- `MASG`:Weapon may have a weird movement when you attached a scope for the first time.It's playable.
- Does not work for 2d scopes

## Known Bugs And Limitations
- ~~Due to the engine limitation,we have to return the camera after shooting,maybe it will be fixed in the future.~~ \
PR is already submited to xray-monolith, [use this for now](https://github.com/emgComplex/FuzzRecoil/releases/tag/no_cam_return_test-2)
- If you have no horizontal recoil,you probably have `Dynamic viewmodel` installed,diable it

## Recoil profile Customization
1. Open Fuzz recoil editor in ImGui.
2. Open weapon profile.Shoot one bullet to refresh the profile
3. Edit (**You will lost every change you made if you switch weapon.**).It'best to edit a wepaon with no upgrade and disable the modifiers.
4. Export ltx file,it will be located in your game bin folder.
5. Copy the exported ltx file to `gamedata/configs` or create a mod in MO2.
6. Restart the game to applly the ltx file .
<img width="713" height="840" alt="rc-info" src="https://github.com/user-attachments/assets/82a44fe9-2512-45f5-bba8-0725f7d433c2" />
<img width="1022" height="1153" alt="rc-profile" src="https://github.com/user-attachments/assets/d685db56-e8ce-4bb9-8b2f-c2433334b48b" />


## Recoil Customization in detail
TLDR:Recoil is mainly base on Camera recoil power(vertical) and Force Yaw(horizontal)
### Recoil System Overview (Translated & Polished)

To better adjust the Recoil Profile, we first need to understand how the entire recoil system works.

Each time a bullet is fired, the **Shot Impulse Force** is applied to the **HUD Weapon** via a spring-based system to simulate the recoil effect. Meanwhile, **Cam Recoil Power** is applied to camera movement.

When the player starts firing, **Handling Power** gradually increases to counteract the influence caused by **Impulse**. Once **Handling Power** reaches 1, the whole recoil system enters a stable state.

At the same time, **Handling Fatigue** increases gradually depending on the magnitude of **Cam Recoil Power**. When **Handling Fatigue** reaches 1, it will gradually reduce **Handling Power**, causing the recoil system to become unstable.

When the player stops firing, both **Handling Power** and **Handling Fatigue** gradually decrease to 0.

You will gradually adapt to the recoil, firearm control strength increases with the number of shots fired. Prolonged firing will cause you to lose control. Switching from a high-recoil weapon to a low-recoil weapon also increases recoil.

Everything naturally happens within this system. Of course, not everything is "realistic"—for example, **Handling Fatigue**—because this is still a game.

---

### Parameter Notes

Now that we understand the underlying mechanics, you likely already know what most parameters do. Here are a few additional parameter explanations:

- **Pull Force**: A multiplier for the spring system stiffness. If you feel like your arm has no strength while firing, you can increase this value.
- **Spring Damping**: Spring damping. Most of the time, you don’t need to adjust it, though you can experiment if you want.
- **PosZ**: Only works in **Instant Mode**. Most weapons already include Z-axis animation, so I didn’t want to “double up” the## Recoil System Overview (Translated & Polished)

To better adjust the Recoil Profile, we first need to understand how the entire recoil system works.

Each time a bullet is fired, the **Shot Impulse Force** is applied to the **HUD Weapon** through a spring system that simulates the recoil effect. **Cam Recoil Power** is applied to camera movement.

When the player begins firing, **Handling Power** gradually increases to counteract the influence of **Impulse**. When **Handling Power** reaches **1**, the recoil system enters a stable state.

At the same time, **Handling Fatigue** increases gradually based on the magnitude of **Cam Recoil Power**. When **Handling Fatigue** reaches **1**, it will gradually reduce **Handling Power**, causing the recoil system to become unstable.

When the player stops firing, **Handling Power** and **Handling Fatigue** both decrease.

You’ll gradually adapt to the recoil: weapon control strength increases with the number of shots fired. Prolonged firing will make you gradually lose control. Switching from a high-recoil weapon to a low-recoil weapon will also increase recoil.

All of this occurs naturally within the system. Of course, not everything is fully physically accurate—for example, **Handling Fatigue**—because it’s a game.

---

### Parameter Notes

Now that we understand the system’s operation, I assume you already know the role of most parameters. Here are a few additional ones:

- **Pull Force**: A multiplier for the spring system stiffness. If you feel like your arm doesn’t have enough strength while shooting, you can increase this value.
- **Spring Damping**: Spring damping. Most of the time you don’t need to adjust it, though it can be worth experimenting.
- **PosZ**: Only works in **Instant Mode**, because most weapons already include Z-axis animation, so I don’t want to “add extra” Z motion.
- **Shot Delay**: These three parameters are designed for semi-automatic weapons. For most pistols, shotguns, bolt-action rifles, and some marksman rifles, this is needed because the actual shot timing is determined by animations, which can’t reflect real firing time.
  - **DelayTime**: The time from pressing the left mouse button to when the recoil system starts returning.

- **Shot Cam Impulse Factor**: This is essentially a multiplier for **Cam Recoil Power**. Because of this mechanism, **Impulse** may become less noticeable, so I added this parameter.  
  - Note: Full-auto weapons also apply this multiplier; the default value is **0.2**.
- **Cam Desync HUD**: When enabled, the Weapon HUD will not follow the camera movement. Most semi-automatic weapons have this option on, which increases the weapon’s “weight” feeling.

## Contribution
- Use events or modifiers for new features
- Try not to introduce new varible to profile if you can . See how fatigue is implemented.
- Permance is critial for this mod,we can use some improvement.
- Try use reocil profile's parameter instead of adding new converter rules

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


