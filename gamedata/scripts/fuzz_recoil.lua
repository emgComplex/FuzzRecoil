local M = { version = "a4" }
_G.fuzz_recoil = M
---@diagnostic disable: lowercase-global
----------Imports
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
local Profile = fuzz_recoil_profile
local camrc = fuzz_recoil_cam_recoil.awake()
local hudrc = fuzz_recoil_hud_recoil.awake()
------------
local cur_wpn = nil
local cur_cast_wpn = nil
local player = nil
--------- state
local active = false
local is_firing = false
local handling_power = 0.0
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
--NOTE: need for scope scale?of just zoom_factor>1
--cur_aim_state = 0
local cur_wpn_id = 0
------- Settitngs
M.settings = {
	debug_mode = fuzz_dev and true or false,

	--TODO:
	recoil_v_scale = 1,
	recoil_h_scale = 1,
	recoil_cam_scale = 1,
	increase_rate_scale = 1,
	handling_speed_scale = 1,
	--The higher the sharper, the lower the smoother (and softer)
	cam_drag = 12,
	bolt_action_Y_lift = true,
	--tarkov style hud kick, instant displacement with eased recovery
	hud_kick_v2 = true,

	--vanilla data extras, off keeps stock feel
	use_pitch_frac = false,
	use_cam_max_angle = false,
	use_addon_ammo_koefs = false,
	use_increase_rate = false,
	--gamma zoom values sit at 0.6-0.8 of hip, on would weaken ads below the tune
	use_zoom_ratio = false,
	--fire bloom, sustained fire and hip stance widen the real bullet cone
	use_bloom = true,
}
--bloom multiplies the weapons fire_dispersion_base, silencer, ammo and
--condition koefs stack on top like vanilla (WeaponDispersion.cpp)
--base is the flat hip penalty, rate grows per shot, heat caps at max
M.bloom = {
	decay = 1.2,
	ads_mul = 0.75,
	classes = {
		pistol = { base = 1.1, rate = 0.18, max = 3.0 },
		smg = { base = 0.4, rate = 0.11, max = 2.4 },
		ar = { base = 0.45, rate = 0.13, max = 2.6 },
		lmg = { base = 0.9, rate = 0.16, max = 4.0 },
		other = { base = 0.6, rate = 0.13, max = 2.8 },
	},
}
--TODO:MCM
function M.apply_settings()
	hudrc.load_settings(M.settings)
	camrc.load_settings(M.settings)
	hudrc.switch_mode(M.settings.hud_kick_v2 and hudrc.MODE.INSTANT or hudrc.MODE.SPRING)
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

local m_profile = Profile:new()
local wpn_info = {
	cam_dispersion = 0,
	cam_dispersion_inc = 0,
	cam_dispersion_frac = 0.7,
	cam_max_angle = 0,
	cam_max_angle_horz = 0,
	cam_step_angle_horz = 0,
	cam_relax_speed = 0,
	zoom_cam_dispersion = 0,
	zoom_cam_dispersion_inc = 0,
	zoom_cam_dispersion_frac = 0.7,
	zoom_cam_max_angle = 0,
	zoom_cam_max_angle_horz = 0,
	zoom_cam_step_angle_horz = 0,
	zoom_cam_relax_speed = 0,
	addon_cam_k = 1,
	addon_cam_inc_k = 1,
	inv_weight = 0,
	mag_size = 30,
	rpm = 600,
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
--------------------
---HOOKS
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
end
function on_before_fire()
	-- logger.dbg("Before Shot ")
	if not active then
		--TODO: this is fine,we need a hook when applying upgrades on cur_weapon,to refresh
		active = M.check_current_weapon()
	end
	--the engine reads dispersion when the bullet leaves, apply before the first one
	if active then
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
	if M.settings.use_bloom then
		local bc = M.bloom.classes[m_profile.burst_class] or M.bloom.classes.other
		bloom_heat = math.min(bloom_heat + bc.rate * (is_ads and M.bloom.ads_mul or 1), bc.max)
	end
	hudrc.on_fire(handling_power, is_ads, shot_cam_k, burst_shots)

	--vanilla dispersion_frac as mean preserving per shot variance
	local frac_factor = M.settings.use_pitch_frac and (1 + (math.random() * 2 - 1) * (1 - m_profile.pitch_frac))
		or 1
	--engine style expansion, kick grows linearly with burst length (EffectorShot Shot)
	local expansion = M.settings.use_increase_rate
			and (1 + m_profile.increase_rate * M.settings.increase_rate_scale * burst_shots)
		or 1
	burst_shots = burst_shots + 1
	local kick_scale = frac_factor
		* expansion
		* shot_cam_k
		* M.settings.recoil_cam_scale
		* (M.settings.hud_kick_v2 and hudrc.get_mode_kick_mul() or 1)
	camrc.on_fire(handling_power, kick_scale)
end
function on_update()
	local dt = device().time_delta / 1000
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
	-- update_sim_shooting(dt)

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
	sim_firing = false
	logger.dbg("Fire stopped")
end

----------------------
---state
---------------------
--TODO: fallback to vanilla if something went wrong
--PERF:smart_cast everytime or cached table?
--i think cached table is better ,but we still have to update the profile evertime
function start_recoil()
	active = true
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
--drives the live bullet cone, base hip penalty plus decaying heat
function update_bloom(dt)
	if not cur_cast_wpn or orig_fire_disp <= 0 then
		return
	end
	if not M.settings.use_bloom then
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
	local mul = 1 + (is_ads and 0 or bc.base) + bloom_heat
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
function update_sim_shooting(dt)
	if sim_firing then
		sim_timer = sim_timer - dt
		if sim_timer <= 0 then
			on_fire_stop()
		else
			if math.modf(sim_timer / 0.08) ~= math.modf((sim_timer + dt) / 0.08) then
				on_fire()
			end
		end
	end
end

----------------------
---Feat
---------------------
--=========Init Recoil and Info Collection============
function M.init_weapon(wpn_sec)
	collect_wpn_info(wpn_sec)
	m_profile = fuzz_recoil_profile:new():load(wpn_sec, wpn_info)
	remove_vanilla_cam_recoil()

	--vanilla cone base in radians, bloom multiplies it at runtime
	orig_fire_disp = cur_cast_wpn and cur_cast_wpn:GetFireDispersion() or 0
	bloom_heat = 0
	bloom_applied = -1

	-- inil some recoil paramete from here
	firing_handling_ease:set_speed(m_profile.handling_speed * M.settings.handling_speed_scale)
	idle_handling_ease:set_speed(m_profile.handling_speed * M.settings.handling_speed_scale)

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
--NOTE: engine getters return the live post-upgrade values in radians,
--converter rules are tuned to ini degrees, so convert back with math.deg
function collect_wpn_info(wpn_sec)
	wpn_info.kind = utils.get_string(wpn_sec, "kind")
	if cur_cast_wpn then
		--NOTE: dispersion_frac is a unitless fraction, no deg conversion
		wpn_info.cam_dispersion = math.deg(cur_cast_wpn:GetCamDispersion())
		wpn_info.cam_dispersion_inc = math.deg(cur_cast_wpn:GetCamDispersionInc())
		wpn_info.cam_dispersion_frac = cur_cast_wpn:GetCamDispersionFrac()
		wpn_info.cam_max_angle = math.deg(cur_cast_wpn:GetCamMaxAngleVert())
		wpn_info.cam_max_angle_horz = math.deg(cur_cast_wpn:GetCamMaxAngleHorz())
		wpn_info.cam_step_angle_horz = math.deg(cur_cast_wpn:GetCamStepAngleHorz())
		wpn_info.cam_relax_speed = math.deg(cur_cast_wpn:GetCamRelaxSpeed())
		wpn_info.zoom_cam_dispersion = math.deg(cur_cast_wpn:GetZoomCamDispersion())
		wpn_info.zoom_cam_dispersion_inc = math.deg(cur_cast_wpn:GetZoomCamDispersionInc())
		wpn_info.zoom_cam_dispersion_frac = cur_cast_wpn:GetZoomCamDispersionFrac()
		wpn_info.zoom_cam_max_angle = math.deg(cur_cast_wpn:GetZoomCamMaxAngleVert())
		wpn_info.zoom_cam_max_angle_horz = math.deg(cur_cast_wpn:GetZoomCamMaxAngleHorz())
		wpn_info.zoom_cam_step_angle_horz = math.deg(cur_cast_wpn:GetZoomCamStepAngleHorz())
		wpn_info.zoom_cam_relax_speed = math.deg(cur_cast_wpn:GetZoomCamRelaxSpeed())
		wpn_info.rpm = cur_cast_wpn:RealRPM()
		wpn_info.mag_size = cur_cast_wpn:GetAmmoMagSize()
		--live weight includes attached addons
		wpn_info.inv_weight = cur_cast_wpn:Weight()
		collect_addon_koefs()
	else
		--fallback: base section values, no upgrades
		wpn_info.cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion")
		wpn_info.cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc")
		wpn_info.cam_dispersion_frac = utils.get_float(wpn_sec, "cam_dispersion_frac", 0.7)
		wpn_info.cam_max_angle = utils.get_float(wpn_sec, "cam_max_angle")
		wpn_info.cam_max_angle_horz = utils.get_float(wpn_sec, "cam_max_angle_horz")
		wpn_info.cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz")
		wpn_info.cam_relax_speed = utils.get_float(wpn_sec, "cam_relax_speed")
		--NOTE: engine copies hip values to zoom when the ini omits the zoom keys
		wpn_info.zoom_cam_dispersion = utils.get_float(wpn_sec, "zoom_cam_dispersion", wpn_info.cam_dispersion)
		wpn_info.zoom_cam_dispersion_inc = utils.get_float(wpn_sec, "zoom_cam_dispersion_inc", wpn_info.cam_dispersion_inc)
		wpn_info.zoom_cam_dispersion_frac = utils.get_float(wpn_sec, "zoom_cam_dispersion_frac", wpn_info.cam_dispersion_frac)
		wpn_info.zoom_cam_max_angle = utils.get_float(wpn_sec, "zoom_cam_max_angle", wpn_info.cam_max_angle)
		wpn_info.zoom_cam_max_angle_horz = utils.get_float(wpn_sec, "zoom_cam_max_angle_horz", wpn_info.cam_max_angle_horz)
		wpn_info.zoom_cam_step_angle_horz = utils.get_float(wpn_sec, "zoom_cam_step_angle_horz", wpn_info.cam_step_angle_horz)
		wpn_info.zoom_cam_relax_speed = utils.get_float(wpn_sec, "zoom_cam_relax_speed", wpn_info.cam_relax_speed)
		wpn_info.rpm = utils.get_float(wpn_sec, "rpm", 600)
		wpn_info.mag_size = utils.get_float(wpn_sec, "ammo_mag_size", 30)
		wpn_info.inv_weight = utils.get_float(wpn_sec, "inv_weight", 3)
		wpn_info.addon_cam_k = 1
		wpn_info.addon_cam_inc_k = 1
	end
	for k, v in pairs(wpn_info) do
		logger.dbg(type(v) == "number" and "%s:%.6f" or "%s:%s", k, v)
	end
end
--engine clamps addon koefs to [0.01, 2.0], empty section means koef 1 like engine reset
local function get_addon_koef(sec, key)
	if not sec or sec == "" then
		return 1
	end
	return utils.math_clamp(utils.get_float(sec, key, 1), 0.01, 2.0)
end
--NOTE: engine multiplies cam recoil by attached addon section koefs (EffectorShot.cpp)
function collect_addon_koefs()
	if not M.settings.use_addon_ammo_koefs then
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
	if not cur_cast_wpn or not M.settings.use_addon_ammo_koefs then
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
--TODO: call this when switching weapon
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
	restore_vanilla_cam_recoil()
	restore_vanilla_fire_disp()
	cur_wpn_id = new_id
	local wpn_sec = cur_wpn:section()
	local flag, kind = should_active(wpn_sec)
	if flag then
		logger.dbg("active:" .. kind)
	else
		logger.dbg("Should not active:" .. kind)
		return false
	end
	cur_cast_wpn = cur_wpn:cast_Weapon()
	if not cur_cast_wpn then
		logger.err("Cannot cast Weapon:%s(%s)", tostring(cur_wpn), cur_wpn_id)
		return false
	end
	M.init_weapon(wpn_sec)
	return true
end
--TODO: use vannilla recoil for grende launcher
function should_active(wpn_sec)
	local kind = utils.get_string(wpn_sec, "kind")
	return allowed_kinds[kind], kind
end

--TODO: fix this
--
-- local function get_aim_state()
-- 	-- local is_gl = weapon:weapon_in_grenade_mode()
-- 	if not cur_cast_wpn:IsZoomed() then
-- 		cur_aim_state = 0
-- 		return
-- 	end
-- 	cur_aim_state = cur_cast_wpn:GetZoomType() + 1
-- 	if cur_aim_state > 3 then
-- 		logger.err("Unknown aim state(out of bound):" .. cur_aim_state)
-- 		cur_aim_state = 0
-- 	end
-- end
--=========Vannilla recoil handler============
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

--------------------
---IMGUI
--------------------
function M.imgui_config_drawer()
	firing_handling_ease:draw_imgui("Handling inc")
	idle_handling_ease:draw_imgui("Handling dec")
	if ImGui.TreeNode("Fire Bloom") then
		ImGui.Text(string.format("heat %.2f, applied x%.2f, base %.4frad", bloom_heat, bloom_applied, orig_fire_disp))
		_, M.bloom.decay = ImGui.SliderFloat("Decay", M.bloom.decay, 0.2, 5.0, "%.2f")
		_, M.bloom.ads_mul = ImGui.SliderFloat("ADS Mul", M.bloom.ads_mul, 0.0, 1.0, "%.2f")
		for _, class in ipairs({ "pistol", "smg", "ar", "lmg", "other" }) do
			local bc = M.bloom.classes[class]
			_, bc.base = ImGui.SliderFloat(class .. " base", bc.base, 0.0, 2.0, "%.2f")
			_, bc.rate = ImGui.SliderFloat(class .. " rate", bc.rate, 0.0, 0.5, "%.3f")
			_, bc.max = ImGui.SliderFloat(class .. " max", bc.max, 0.0, 3.0, "%.2f")
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
	float_s1 = 0,
	float_s2 = 0,
	float_x1 = 0,
	float_x2 = 0,
}
sim_firing = false
sim_timer = 0.0

--defaults reach the modules without waiting for an imgui apply
M.apply_settings()
