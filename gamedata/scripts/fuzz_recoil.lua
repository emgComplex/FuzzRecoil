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
}
--TODO:MCM
function M.apply_settings()
	hudrc.load_settings(M.settings)
	camrc.load_settings(M.settings)
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
pitch_expansion = 1.5

local m_profile = Profile:new()
local wpn_info = {
	cam_dispersion = 0,
	cam_dispersion_inc = 0,
	zoom_cam_dispersion = 0,
	zoom_cam_dispersion_inc = 0,
	cam_step_angle_horz = 0,
	cam_relax_speed = 0,
	inv_weight = 0,
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
	force_reset_recoil()
end
function on_before_fire()
	-- logger.dbg("Before Shot ")
	if not active then
		--TODO: this is fine,we need a hook when applying upgrades on cur_weapon,to refresh
		active = M.check_current_weapon()
	end
end
function on_fire()
	if not active then
		--TODO:this is the major impact(0.26ms) on peformance, i mean 0.26ms is not that slow
		--this is bad entry point i think ,but i got nothing better
		--so find out who did the impact(i m guessing cam_effector or hud_adjust.enabled)
		--no need to good deep for optimization ,leave it here for now.
		start_recoil()
	end
	if m_profile.shot_delay_enabled then
		CreateTimeEvent("fuzz_recoil", "bolt_delay_stop", m_profile.shot_delay_time, function()
			on_fire_stop()
			return true
		end)
	end
	-- logger.dbg("Shot ")

	is_firing = true

	hudrc.on_fire(handling_power)
	camrc.on_fire(handling_power, m_profile.cam_recoil_power, m_profile.shot_cam_impulse_factor)
end
function on_update()
	local dt = device().time_delta / 1000
	if active == false then
		return
	end
	-- logger.dbg("Update")
	---@diagnostic disable-next-line: need-check-nil, undefined-field
	if is_firing and cur_wpn:get_state() ~= 5 then
		on_fire_stop()
	end
	-- update_sim_shooting(dt)

	update_handling_power(dt)
	local hud_returned = hudrc.update(dt, is_firing and handling_power or nil)
	local cam_returned = camrc.update(dt, is_firing)
	if handling_power <= 0 and hud_returned and cam_returned then
		reset_recoil()
	end
end
function on_fire_stop()
	is_firing = false
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
	camrc.start()
	hudrc.start()
	RemoveTimeEvent("fuzz_recoil", "bolt_delay")
	logger.dbg("Initialize Recoil")
end
function reset_recoil()
	active = false
	is_firing = false
	handling_power = 0

	camrc.remove_cam_fx()
	hudrc.disable_hud_adjust()
	RemoveTimeEvent("fuzz_recoil", "bolt_delay")

	logger.dbg("reset recoil")
end
function force_reset_recoil()
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

	-- inil some recoil paramete from here
	firing_handling_ease:set_speed(m_profile.handling_speed)
	idle_handling_ease:set_speed(m_profile.handling_speed)

	if m_profile.is_bolt_action then
		idle_handling_ease.intensity = sniper_idle_handling.intensity
		idle_handling_ease.offset = sniper_idle_handling.offset
	else
		idle_handling_ease:reset()
	end

	camrc.init(m_profile.cam_return_speed, m_profile.shot_delay_enabled and "cubic" or "exp")
	hudrc.init(wpn_sec, m_profile)

	logger.dbg("Initialize weapon")
end
--FIXME: only cam_step_angle_horz update with upgrades
--tested with wpn_m98b,there is an unpacked upgrades ltx in
--configs/items/weapons/upgrades/w_m98b_up.ltx
--it does reduce cam_dispersion
--NOTE: engine getters return the live post-upgrade values in radians,
--converter rules are tuned to ini degrees,so convert back with math.deg
function collect_wpn_info(wpn_sec)
	wpn_info.kind = utils.get_string(wpn_sec, "kind")
	if cur_cast_wpn then
		wpn_info.cam_dispersion = math.deg(cur_cast_wpn:GetCamDispersion())
		wpn_info.cam_dispersion_inc = math.deg(cur_cast_wpn:GetCamDispersionInc())
		wpn_info.zoom_cam_dispersion = math.deg(cur_cast_wpn:GetZoomCamDispersion())
		wpn_info.zoom_cam_dispersion_inc = math.deg(cur_cast_wpn:GetZoomCamDispersionInc())
		wpn_info.cam_step_angle_horz = math.deg(cur_cast_wpn:GetCamStepAngleHorz())
		wpn_info.cam_relax_speed = math.deg(cur_cast_wpn:GetCamRelaxSpeed())
		wpn_info.rpm = cur_cast_wpn:RealRPM()
		wpn_info.inv_weight = cur_cast_wpn:Weight()
	else
		--fallback: base section values,no upgrades
		wpn_info.cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion")
		wpn_info.cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc")
		wpn_info.zoom_cam_dispersion = utils.get_float(wpn_sec, "zoom_cam_dispersion")
		wpn_info.zoom_cam_dispersion_inc = utils.get_float(wpn_sec, "zoom_cam_dispersion_inc")
		wpn_info.cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz")
		wpn_info.cam_relax_speed = utils.get_float(wpn_sec, "cam_relax_speed")
		wpn_info.rpm = utils.get_float(wpn_sec, "rpm", 600)
		--NOTE: if we are considering mass effect,we should use engine-getter
		wpn_info.inv_weight = utils.get_float(wpn_sec, "inv_weight", 3)
	end
	for k, v in pairs(wpn_info) do
		logger.dbg(type(v) == "number" and "%s:%.6f" or "%s:%s", k, v)
	end
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
	--NOTE: setters take raw radians,wpn_info is kept in ini degrees
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
