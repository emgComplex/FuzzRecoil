local M = { version = "a5" }
_G.fuzz_recoil = M
---@diagnostic disable: lowercase-global
----------Imports
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
local Profile = fuzz_recoil_profile
local options = fuzz_recoil_mcm
local camrc = fuzz_recoil_cam_recoil.awake()
local hudrc = fuzz_recoil_hud_recoil.awake()
--NOTE:update when swithcing wepaon
M.static_modifiers = fuzz_recoil_modifier:new()
--NOTE:update before fire
M.dynamic_modifiers = fuzz_recoil_modifier:new()
---@type fuzz_recoil_profile
local m_profile = Profile:new()
------------
local cur_wpn = nil
local cur_cast_wpn = nil
local player = nil
--------- state
local active = false
local is_firing = false
local handling_power = 0.0
local handling_fatigue = 0
local FATIGUE_MAX_POWER = 0.55
--shots in the current burst, drives heat and recoil expansion
local burst_shots = 0
--refreshed per shot, addon koefs x ammo k_cam_dispersion and ads flag
local is_ads = false
local shot_cam_k = 1
--fire bloom state, heat in cone multiples over the cached vanilla base
local bloom_heat = 0
local orig_fire_disp = 0
local bloom_applied = -1
--attached addon fingerprint, throttled check in on_update
local addon_sig = ""
local next_addon_check = 0
local cur_wpn_id = 0
--bloom multiplies the weapons fire_dispersion_base, silencer, ammo and
--condition koefs stack on top like vanilla (WeaponDispersion.cpp)
--base is the flat hip penalty, rate grows per shot, heat caps at max
M.bloom = {
	--master variance, scales the whole extra cone, 0 is vanilla dispersion
	variance = 1.0,
	decay = 1.2,
	--heat grows at full rate scoped, stance only changes the base share
	ads_mul = 1.0,
	ads_base = 0.3,
	classes = {
		pistol = { base = 1.1, rate = 0.18, max = 3.0 },
		smg = { base = 0.4, rate = 0.11, max = 2.4 },
		ar = { base = 0.45, rate = 0.13, max = 2.6 },
		lmg = { base = 0.9, rate = 0.16, max = 4.0 },
		other = { base = 0.6, rate = 0.13, max = 2.8 },
	},
}
--TODO:MCM
function M.on_option_change()
	init_static_modifiers()
	init_dynamic_modifiers()
	m_profile:reload_modifiers()
	hudrc.on_option_change()
	camrc.on_option_change()
	hudrc.switch_mode(options.hud_kick_v2 and hudrc.MODE.INSTANT or hudrc.MODE.SPRING)
	logger.dbg("apply options to hud")
end
------- config
local allowed_kinds = {
	w_pistol = true,
	w_rifle = true,
	w_shotgun = true,
	w_sniper = true,
	w_smg = true,
}
local firing_handling_ease = utils.simple_ease:new(1, 1, 0.2, 4)
local idle_handling_ease = utils.simple_ease:new(-1, -1, 0.2, 6)
--NOGUI
sniper_idle_handling = { offset = 0.2, intensity = 0.8 }

local wpn_info = {
	--NOTE: upgrade needed
	cam_dispersion = 0,
	cam_step_angle_horz = 0,
	cam_dispersion_inc = 0,
	--NOTE: always needed
	zoom_cam_dispersion = 0,
	zoom_cam_dispersion_inc = 0,
	rpm = 600,
	cam_relax_speed = 0,
	mag_size = 30,
	--NOTE: feature needed
	cam_dispersion_frac = 0.7,
	cam_max_angle = 0,
	addon_cam_k = 1,
	addon_cam_inc_k = 1,
	inv_weight = 0,
}

--------------------
---Public Getter
--------------------
function M.get_wpn_info()
	return wpn_info
end
function M.get_recoil_profile()
	return m_profile
end
function M.get_cur_wpn()
	return cur_wpn
end
function M.get_cur_wpn_id()
	return cur_wpn_id
end
function M.is_active()
	return active
end
function M.is_firing()
	return is_firing
end
function M.get_handling_power()
	return handling_power
end
function M.get_handling_fatigue()
	return handling_fatigue
end
function M.get_shot_cam_k()
	return shot_cam_k
end
function M.get_handling_eases()
	return firing_handling_ease, idle_handling_ease
end
function M.get_bloom_state()
	return bloom_heat, bloom_applied, orig_fire_disp
end
--------------------
---Public Setter
--------------------
function M.set_handling_speed(val)
	firing_handling_ease:set_speed(val)
	idle_handling_ease:set_speed(val)
end
function M.add_handling_fatigue(val)
	handling_fatigue = handling_fatigue + math.abs(val) * options.impulse_fatigue_ratio
end
--------------------
---Engine HOOKS
--------------------
function M.on_game_start()
	RegisterScriptCallback("actor_on_changed_slot", on_changed_slot)
	RegisterScriptCallback("actor_on_weapon_before_fire", on_before_fire)
	RegisterScriptCallback("actor_on_weapon_fired", on_fire)
	RegisterScriptCallback("actor_on_update", on_update)
end

function on_changed_slot()
	--NOTE: i think calling  this will cause cam glith when camera not fully is_cam_returned
	--Never seen it happens since switching animation will give us a natrual delay
	--but if it happens we can fix it with a TimeEvent
	M.force_reset_recoil()
	--NOTE:!!!breaking change,load weapon when switching,
	--less performance impact on before fire
	M.check_current_weapon()
end
function on_before_fire()
	-- logger.dbg("Before Shot ")
	if not active then
		active = M.check_current_weapon()
	end
	--the engine reads dispersion when the bullet leaves, apply before the first one
	if active then
		hudrc.pick_yaw_sign()
		update_bloom(0)
	end
end
function on_fire()
	--first draw reaches here with active already true, check the effector too
	if not active or not camrc.has_camera_effector() then
		start_recoil()
	end
	if m_profile.shot_delay_enabled then
		--create is a no op while one is pending, reset makes the delay count from the last shot
		CreateTimeEvent("fuzz_recoil", "bolt_delay_stop", m_profile.shot_delay_time, function()
			on_fire_stop()
			return true
		end)
		ResetTimeEvent("fuzz_recoil", "bolt_delay_stop", m_profile.shot_delay_time)
	end
	-- logger.dbg("Shot ")

	is_firing = true

	update_shot_cam_k()
	if options.use_bloom then
		local bc = M.bloom.classes[m_profile.burst_class] or M.bloom.classes.other
		bloom_heat = math.min(bloom_heat + bc.rate * (is_ads and M.bloom.ads_mul or 1), bc.max)
	end

	local fatigue_scale = 1
	if handling_fatigue > 1 then
		fatigue_scale = 1 - utils.lerp_in(handling_fatigue - 1, 0, FATIGUE_MAX_POWER)
	end
	hudrc.on_fire(handling_power * fatigue_scale, is_ads, shot_cam_k, burst_shots)

	--vanilla dispersion_frac as mean preserving per shot variance
	local frac_factor = options.use_pitch_frac and (1 + (math.random() * 2 - 1) * (1 - m_profile.pitch_frac)) or 1
	burst_shots = burst_shots + 1
	local kick_scale = frac_factor * shot_cam_k * (options.hud_kick_v2 and hudrc.get_mode_kick_mul() or 1)
	camrc.on_fire(handling_power * fatigue_scale, kick_scale)
end
function on_update()
	local dt = device().time_delta / 1000
	if not is_firing and handling_fatigue > 0 then
		--NOTE: regen from 1 is by design, you can try turn it off
		handling_fatigue = math.min(1, handling_fatigue - 0.003)
	end
	if active == false then
		return
	end
	-- logger.dbg("Update")
	--addon swap while adjust mode is on sticks the hands, reset and reinit instead
	if time_global() >= next_addon_check then
		next_addon_check = time_global() + 250
		if get_addon_sig() ~= addon_sig then
			M.force_reset_recoil()
			cur_wpn_id = 0
			return
		end
	end
	---@diagnostic disable-next-line: need-check-nil, undefined-field
	if is_firing and cur_wpn:get_state() ~= 5 then
		on_fire_stop()
	end

	update_handling_power(dt)
	update_bloom(dt)
	local hud_returned = hudrc.update(dt, is_firing and handling_power or nil)
	local cam_returned = camrc.update(dt, is_firing)
	if handling_power <= 0 and hud_returned and cam_returned then
		reset_recoil()
	end
end
function on_fire_stop()
	is_firing = false
	burst_shots = 0
	logger.dbg("Fire stopped")
end

----------------------
---Recoil state
---------------------
function start_recoil()
	active = true
	get_actor_state()
	init_dynamic_modifiers()
	m_profile:apply_dynamic_modifiers()
	camrc.start(m_profile)
	hudrc.start(m_profile)
	RemoveTimeEvent("fuzz_recoil", "bolt_delay_stop")
	logger.dbg("Initialize Recoil")
end
function reset_recoil()
	active = false
	is_firing = false
	burst_shots = 0
	handling_power = 0

	camrc.remove_cam_fx()
	hudrc.disable_hud_adjust()
	restore_vanilla_fire_disp()
	RemoveTimeEvent("fuzz_recoil", "bolt_delay_stop")

	logger.dbg("reset recoil")
end
function M.force_reset_recoil()
	camrc.stop()
	hudrc.stop()
	reset_recoil()
end
function update_handling_power(dt)
	if is_firing then
		handling_power = utils.math_clamp(firing_handling_ease:update(handling_power, dt), 0, 1)
	else
		-- handling_power = 0
		handling_power = utils.math_clamp(idle_handling_ease:update(handling_power, dt), 0, 1)
	end
end

----------------------
---Vannilla Recoil Hanlder
---------------------
function remove_vanilla_cam_recoil()
	set_vanilla_cam_recoil(cur_cast_wpn, 0, 0, 0, 0)
end
function restore_vanilla_cam_recoil()
	if not cur_cast_wpn then
		return
	end
	--NOTE: setters take raw radians, wpn_info is kept in ini degrees
	set_vanilla_cam_recoil(
		cur_cast_wpn,
		math.rad(wpn_info.cam_dispersion),
		math.rad(wpn_info.cam_dispersion_inc),
		math.rad(wpn_info.zoom_cam_dispersion),
		math.rad(wpn_info.zoom_cam_dispersion_inc)
	)
end
function set_vanilla_cam_recoil(cast_wpn, cam_disp, cam_disp_inc, zoom_cam_disp, zoom_cam_dis_inc)
	cast_wpn:SetCamDispersion(cam_disp)
	cast_wpn:SetCamDispersionInc(cam_disp_inc)
	cast_wpn:SetZoomCamDispersion(zoom_cam_disp)
	cast_wpn:SetZoomCamDispersionInc(zoom_cam_dis_inc)
end
----------------------
---Weapon Info
---------------------
---@diagnostic disable: undefined-field,need-check-nil
---!!!!! DO NOT CALL THIS!!!!!!
---NOTE:no nil check for cast_wpn
function init_weapon(wpn_sec)
	collect_wpn_info(wpn_sec)
	--TODO: better entry point needed
	init_static_modifiers()
	m_profile = fuzz_recoil_profile:new():load(wpn_sec, wpn_info)
	m_profile:apply_static_modifiers()
	remove_vanilla_cam_recoil()

	--vanilla cone base in radians, bloom multiplies it at runtime
	orig_fire_disp = cur_cast_wpn and cur_cast_wpn:GetFireDispersion() or 0
	bloom_heat = 0
	bloom_applied = -1

	-- inil some recoil paramete from here
	firing_handling_ease:set_speed(m_profile.handling_speed)
	idle_handling_ease:set_speed(m_profile.handling_speed)

	if m_profile.is_bolt_action then
		idle_handling_ease.intensity = sniper_idle_handling.intensity
		idle_handling_ease.offset = sniper_idle_handling.offset
	else
		idle_handling_ease:reset()
	end

	camrc.init(m_profile.shot_delay_enabled and "cubic" or "exp")
	hudrc.init(wpn_sec, cur_cast_wpn)

	addon_sig = get_addon_sig()
	logger.dbg("Initialize weapon")
end
--TODO:if using cached profile , we need check upgrades and call this agian
--NOTE: engine getters return the live post-upgrade values in radians,
--converter rules are tuned to ini degrees, so convert back with math.deg
function collect_wpn_info(wpn_sec)
	get_upgrade_wpn_info()
	get_basic_wpn_info()
	get_feat_wpn_info()
	-- for k, v in pairs(wpn_info) do
	-- 	logger.dbg(type(v) == "number" and "%s:%.6f" or "%s:%s", k, v)
	-- end
end
function get_upgrade_wpn_info()
	wpn_info.cam_dispersion = math.deg(cur_cast_wpn:GetCamDispersion())
	wpn_info.cam_dispersion_inc = math.deg(cur_cast_wpn:GetCamDispersionInc())
	wpn_info.cam_step_angle_horz = math.deg(cur_cast_wpn:GetCamStepAngleHorz())
end
function get_basic_wpn_info()
	wpn_info.zoom_cam_dispersion = math.deg(cur_cast_wpn:GetZoomCamDispersion())
	wpn_info.zoom_cam_dispersion_inc = math.deg(cur_cast_wpn:GetZoomCamDispersionInc())
	wpn_info.rpm = cur_cast_wpn:RealRPM()
	wpn_info.mag_size = cur_cast_wpn:GetAmmoMagSize()
	wpn_info.cam_relax_speed = math.deg(cur_cast_wpn:GetCamRelaxSpeed())
end
function get_feat_wpn_info()
	--NOTE: dispersion_frac is a unitless fraction, no deg conversion
	wpn_info.cam_dispersion_frac = cur_cast_wpn:GetCamDispersionFrac()
	wpn_info.cam_max_angle = math.deg(cur_cast_wpn:GetCamMaxAngleVert())
	--live weight includes attached addons
	wpn_info.inv_weight = cur_cast_wpn:Weight()
	collect_addon_koefs()
end
function read_upgrade_wpn_info(wpn_sec)
	return {
		cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion"),
		cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc"),
		cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz"),
	}
end
---@diagnostic enable: undefined-field,need-check-nil
----------------------
---Weapon Check
---------------------
--TODO: fallback to vanilla if something went wrong
--PERF:smart_cast everytime or cached table?
--i think cached table is better ,but we still have to update the profile evertime
--TODO: use vannilla recoil for grende launcher
function should_active(wpn_sec)
	local kind = utils.get_string(wpn_sec, "kind")
	return allowed_kinds[kind], kind
end
function M.check_current_weapon()
	player = db.actor
	if not player then
		return false
	end
	cur_wpn = player:active_item()
	if not cur_wpn then
		return false
	end
	local new_id = cur_wpn:id()
	if cur_wpn_id == new_id then
		return active
	end
	--NOTE: give the previous weapon its vanilla cam recoil back,
	--otherwise re-equipping it would collect our zeroed values
	if cur_wpn_id ~= -1 then
		restore_vanilla_cam_recoil()
		restore_vanilla_fire_disp()
	end
	cur_wpn_id = new_id
	local wpn_sec = cur_wpn:section()
	local kind_flag, kind = should_active(wpn_sec)
	if not kind_flag then
		-- logger.dbg("Should not active:" .. kind)
		cur_wpn_id = -1
		return false
		-- else
		-- logger.dbg("active:" .. kind)
	end
	cur_cast_wpn = cur_wpn:cast_Weapon()
	if not cur_cast_wpn then
		logger.err("Cannot cast Weapon:%s(%s)", tostring(cur_wpn), cur_wpn_id)
		cur_wpn_id = -1
		return false
	end
	wpn_info.kind = kind
	init_weapon(wpn_sec)
	return true
end
function M.force_recheck_weapon()
	cur_wpn_id = -2
	M.check_current_weapon()
end
----------------------
---Feat
---------------------
--engine clamps addon koefs to [0.01, 2.0], empty section means koef 1 like engine reset
local function get_addon_koef(sec, key)
	if not sec or sec == "" then
		return 1
	end
	return utils.math_clamp(utils.get_float(sec, key, 1), 0.01, 2.0)
end
--NOTE: engine multiplies cam recoil by attached addon section koefs (EffectorShot.cpp)
function collect_addon_koefs()
	if not options.use_addon_ammo_koefs then
		wpn_info.addon_cam_k = 1
		wpn_info.addon_cam_inc_k = 1
		return
	end
	local cam_k, cam_inc_k = 1, 1
	local addons = {
		{ cur_cast_wpn:IsSilencerAttached(), cur_cast_wpn:GetSilencerName() },
		{ cur_cast_wpn:IsScopeAttached(), cur_cast_wpn:GetScopeName() },
		{ cur_cast_wpn:IsGrenadeLauncherAttached(), cur_cast_wpn:GetGrenadeLauncherName() },
	}
	for _, addon in ipairs(addons) do
		if addon[1] then
			cam_k = cam_k * get_addon_koef(addon[2], "cam_dispersion_k")
			cam_inc_k = cam_inc_k * get_addon_koef(addon[2], "cam_dispersion_inc_k")
		end
	end
	wpn_info.addon_cam_k = cam_k
	wpn_info.addon_cam_inc_k = cam_inc_k
end
--k_cam_dispersion of the selected ammo type, default 1 unclamped like engine
--NOTE: engine uses the chambered round, no lua export, selected type is the best approximation
function get_ammo_cam_k()
	local cur_type = cur_cast_wpn:GetAmmoType()
	local ammo_k = 1
	cur_cast_wpn:AmmoTypeForEach(function(i, sec)
		if i == cur_type then
			ammo_k = utils.get_float(sec, "k_cam_dispersion", 1)
			return true
		end
		return false
	end)
	return ammo_k
end
--refresh per shot so addon attach, ammo switch and ads state apply without a weapon re draw
function update_shot_cam_k()
	is_ads = (cur_cast_wpn and cur_cast_wpn:IsZoomed()) and true or false
	if not cur_cast_wpn or not options.use_addon_ammo_koefs then
		shot_cam_k = 1
		return
	end
	collect_addon_koefs()
	shot_cam_k = wpn_info.addon_cam_k * get_ammo_cam_k()
end
--attached addon fingerprint, a change means the engine reloaded hud measures
function get_addon_sig()
	if not cur_cast_wpn then
		return ""
	end
	return (cur_cast_wpn:IsScopeAttached() and "s" or "")
		.. tostring(cur_cast_wpn:GetScopeName())
		.. (cur_cast_wpn:IsSilencerAttached() and "m" or "")
		.. tostring(cur_cast_wpn:GetSilencerName())
		.. (cur_cast_wpn:IsGrenadeLauncherAttached() and "g" or "")
end

--================Bloom
--drives the live bullet cone, base hip penalty plus decaying heat
function update_bloom(dt)
	if not cur_cast_wpn or orig_fire_disp <= 0 then
		return
	end
	if not options.use_bloom then
		if bloom_applied ~= 1 then
			cur_cast_wpn:SetFireDispersion(orig_fire_disp)
			bloom_applied = 1
		end
		return
	end
	--stance can change without a shot, keep it current
	is_ads = cur_cast_wpn:IsZoomed() and true or false
	--heat only cools between bursts, sustained fire climbs all the way to the class cap
	if not is_firing then
		bloom_heat = bloom_heat * math.exp(-M.bloom.decay * dt)
	end
	local bc = M.bloom.classes[m_profile.burst_class] or M.bloom.classes.other
	local mul = 1 + (bc.base * (is_ads and M.bloom.ads_base or 1) + bloom_heat) * M.bloom.variance
	if math.abs(mul - bloom_applied) > 0.01 then
		cur_cast_wpn:SetFireDispersion(orig_fire_disp * mul)
		bloom_applied = mul
	end
end
function restore_vanilla_fire_disp()
	if not cur_cast_wpn or orig_fire_disp <= 0 then
		return
	end
	cur_cast_wpn:SetFireDispersion(orig_fire_disp)
	bloom_applied = -1
	bloom_heat = 0
end
--================actor stats
local actor_hunger = 1
local actor_stamina = 1
local actor_recoil_modi_val = 0
local actor_stat_threshold = 0.8
function get_actor_state()
	if not player then
		player = db.actor
		if not player then
			return
		end
	end
	local condition = db.actor:cast_Actor():conditions()
	actor_hunger = condition:GetSatiety()
	actor_stamina = player.power
	actor_recoil_modi_val = 0
	if actor_hunger <= actor_stat_threshold then
		actor_recoil_modi_val = actor_recoil_modi_val + (1 - actor_hunger) / 2
	end
	if actor_stamina <= actor_stat_threshold then
		actor_recoil_modi_val = actor_recoil_modi_val + (1 - actor_stamina) / 2
	end
	-- logger.dbg("hunger:%.4f,stamina:%.4f", actor_hunger, actor_stamina)
end
--------------------
--#region modifiers
--------------------
function init_static_modifiers()
	---@type ModiData[]
	local basic_modi = {
		{ name = "", param = "cam_recoil_power", type = 1, val = options.recoil_cam_scale },
		-- { name = "", param = "force_pitch", type = 1, val = options.recoil_v_scale },
		-- { name = "", param = "force_y", type = 1, val = options.recoil_v_scale },
		{ name = "", param = "force_yaw", type = 1, val = options.recoil_h_scale },
		-- { name = "", param = "force_x", type = 1, val = options.recoil_h_scale },
		{ name = "", param = "handling_speed", type = 1, val = options.handling_speed_scale },
	}
	for i, v in ipairs(basic_modi) do
		local result = M.static_modifiers:add_modifier(i, v, true, true)
	end
	M.static_modifiers:refresh_modi_cache()
end
function init_dynamic_modifiers()
	---@type ModiData[]
	local basic_modi = {
		{ name = "", param = "cam_recoil_power", type = 1, val = actor_recoil_modi_val },
		{ name = "", param = "force_pitch", type = 1, val = actor_recoil_modi_val },
		-- { name = "", param = "force_y", type = 1, val = actor_recoil_modi_val },
		{ name = "", param = "force_yaw", type = 1, val = actor_recoil_modi_val },
		-- { name = "", param = "force_x", type = 1, val = actor_recoil_modi_val },
		-- { name = "", param = "handling_speed", type = 1, val = actor_recoil_modi_val },
	}
	for i, v in ipairs(basic_modi) do
		local result = M.dynamic_modifiers:add_modifier(i, v, true, true)
	end
	M.dynamic_modifiers:refresh_modi_cache()
end
function M.reload_static_modifiers()
	m_profile:apply_static_modifiers()
end
--------------------
--#endregion modifiers
--------------------
--------------------
---IMGUI
--------------------
function M.imgui_config_drawer()
	firing_handling_ease:draw_imgui("Handling inc")
	idle_handling_ease:draw_imgui("Handling dec")
	if ImGui.TreeNode("Fire Bloom Configs") then
		ImGui.Text(string.format("heat %.2f, applied x%.2f, base %.4frad", bloom_heat, bloom_applied, orig_fire_disp))
		_, M.bloom.variance = ImGui.SliderFloat("Variance", M.bloom.variance, 0.0, 3.0, "%.2f")
		_, M.bloom.decay = ImGui.SliderFloat("Decay", M.bloom.decay, 0.2, 5.0, "%.2f")
		_, M.bloom.ads_mul = ImGui.SliderFloat("ADS Mul", M.bloom.ads_mul, 0.0, 1.0, "%.2f")
		_, M.bloom.ads_base = ImGui.SliderFloat("ADS Base Share", M.bloom.ads_base, 0.0, 1.0, "%.2f")
		for _, class in ipairs({ "pistol", "smg", "ar", "lmg", "other" }) do
			ImGui.PushID(class)
			local bc = M.bloom.classes[class]
			_, bc.base = ImGui.SliderFloat(class .. " base", bc.base, 0.0, 2.0, "%.2f")
			_, bc.rate = ImGui.SliderFloat(class .. " rate", bc.rate, 0.0, 0.5, "%.3f")
			_, bc.max = ImGui.SliderFloat(class .. " max", bc.max, 0.0, 3.0, "%.2f")
			ImGui.PopID()
		end
		ImGui.TreePop()
	end
end
--------------------------------------
---Debug
--------------------------------------
M.debug_var = {
	bool0 = false,
	bool1 = true,
	float_s1 = 0.8,
	float_s2 = 0,
	float_x1 = 0,
	float_x2 = 0,
}
