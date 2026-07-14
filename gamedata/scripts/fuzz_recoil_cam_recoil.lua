local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger

local M = {}
_G.fuzz_recoil_cam_recoil = M

----------
---CAM_FX
----------
local CAM_FX_ID = 7897
local function create_cam_effector()
	if not level.check_cam_effector(CAM_FX_ID) then
		level.add_cam_effector("camera_effects\\onerad.anm", 7897, true, "", 0, true, 0.0001)
	end
end
function M.has_camera_effector()
	return level.check_cam_effector(CAM_FX_ID)
end
local function set_player_angle(angle)
	--no op until start adds the effector, resets before init are silent
	if M.has_camera_effector() then
		level.set_cam_effector_factor(CAM_FX_ID, math.max(0.0001, math.min(angle, 0.999)))
	end
end
function set_cam_effect_id(id)
	CAM_FX_ID = id
end
function cam_fx_id()
	return CAM_FX_ID
end

----------
---Local Vars
----------
local is_returned = false
local m_vel = 0
local m_angle = 0
local bonus_return_speed = 0

local _update_fn = M.update_exp
----------
---Cached vars
----------
local lift_force = 0
local impulse_factor = 0
--vanilla cam_max_angle cap in radians, 0 means uncapped
local max_angle = 0
----------
---Pulibc Getters
----------
function M.get_angle()
	return m_angle
end
function M.get_vel()
	return m_vel
end
function M.is_returned()
	return is_returned
end
----------
---Configs
----------
base_cam_return_speed = 4.0
min_cam_return_step = 0.0045
--auto fire impulse decay and step divisor
cam_impulse_decay = 12
cam_step_div = 15
----------
---Settings
----------
local cam_drag = 12
local use_cam_max_angle = false
function M.load_settings(settings)
	cam_drag = settings.cam_drag
	use_cam_max_angle = settings.use_cam_max_angle
end
----------
---Module
----------

function M.remove_cam_fx()
	if level.check_cam_effector(CAM_FX_ID) then
		level.remove_cam_effector(CAM_FX_ID)
	end
end

function M.awake()
	M.instance = M
	return M
end
function M.init(mode)
	if mode then
		M.switch_mode(mode)
	end
	M.stop()
end
function M.cache_profile(profile)
	lift_force = profile.cam_recoil_power
	impulse_factor = profile.shot_cam_impulse_factor
	bonus_return_speed = profile.cam_return_speed
	max_angle = profile.cam_max_angle or 0
end
function M.start(profile)
	M.cache_profile(profile)
	create_cam_effector()
	is_returned = false
end
function M.stop()
	-- NOTE: what if we don't remove cam effector at all?
	-- M.remove_cam_fx()
	set_player_angle(0.0001)
	is_returned = true
	m_angle = 0
	m_vel = 0
end
--scale carries the per shot koefs, frac variance, expansion and mode kick
function M.on_fire(handle, scale)
	is_returned = false
	handle = math.pow(1 - handle, 2)
	local raw_impulse = lift_force * impulse_factor * (scale or 1)
	fuzz_recoil.add_handling_fatigue(raw_impulse)
	local cam_impulse = raw_impulse * handle
	m_vel = m_vel + cam_impulse
end

--vanilla cam_max_angle cap, 0 disables
--NOTE: we use cam_fx which lerp from 0 to 1,
--animation is a simle 0-57.3(one rad) pitch rotation
--power glitch at 0 and 1, so i hard-clamp it in set_plyaer_angle
--most weapon clamps at 51 degree ,
local function clamp_angle()
	if not use_cam_max_angle then
		return
	end
	if max_angle > 0 and m_angle > max_angle then
		m_angle = max_angle
	end
end

function M.update_cubic(dt)
	if math.abs(m_vel) <= 0.01 then
		return
	end
	local drag = cam_drag * math.sqrt(math.abs(m_vel))
	m_vel = m_vel * math.exp(-drag * dt)
	m_angle = m_angle + m_vel * dt
	clamp_angle()
	set_player_angle(m_angle)
end
function M.update_exp(dt)
	if math.abs(m_vel) <= 0.01 then
		return
	end
	local decay = math.exp(-dt * cam_impulse_decay)
	local step = m_vel * (1 - decay) / cam_step_div
	m_vel = m_vel * decay
	m_angle = m_angle + step
	clamp_angle()
	set_player_angle(m_angle)
end
function M.update_spring(dt)
	--TODO: don't forget me~~~
	m_angle, m_vel = apply_spring(m_angle, m_vel, dt, debug_var.float_x1)
	set_player_angle(m_angle)
end
--TODO: enum but not here,it should be in main script so every module can use it
M.CURVEMODE = {
	EXP = 0,
	CUBIC = 1,
	SPRING = 2,
}

function M.switch_mode(mode)
	if mode == "exp" then
		_update_fn = M.update_exp
	elseif mode == "cubic" then
		_update_fn = M.update_cubic
	elseif mode == "spring" then
		_update_fn = M.update_spring
	else
		_update_fn = M.update_exp
	end
end

--NOTE: min_step is the best i can got...still can't get the final phase right.
--TODO: --maybe try simple_ease and lerp the vel to a min value?,it could be more natrual when the angle is high.
--i think it's fine for now, and maybe remove camera return in the future if we can get rid of cam_effector
--leave it here
function M.do_return(dt)
	--TODO:remove config and cache this when init
	if m_angle <= min_cam_return_step then
		M.stop()
		return
	end
	local speed_factor = base_cam_return_speed + bonus_return_speed
	local lerp_factor = 1.0 - math.exp(-speed_factor * dt)

	local step = m_angle * lerp_factor
	local min_step = min_cam_return_step
	local final_step = math.max(step, min_step)
	--NOTE:vel is actually step when returning ,im just lazy ,its easy to debug
	m_vel = final_step
	m_angle = m_angle - final_step
	set_player_angle(m_angle)
end

--FIXME: something feels off...
function M.update(dt, is_firing)
	if is_firing then
		_update_fn(dt)
		return false
	end
	if not is_returned then
		M.do_return(dt)
	end
	return is_returned
end
---------
---IMGUI
--------
function M.imgui_info_drawer()
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Camera recoil")
	ImGui.Text(string.format("Cam angle: %.3frad,%.2fdeg", m_angle, math.deg(m_angle)))
	ImGui.Text(string.format("Cam velocity: %.3f", m_vel))
end
function M.imgui_config_drawer()
	ImGui.Text("Cam Recoil Config")
	_, base_cam_return_speed = ImGui.SliderFloat("Base Cam Return Speed", base_cam_return_speed, 0.1, 10, "%.2frad")
	_, min_cam_return_step = ImGui.SliderFloat("Min Cam Return step", min_cam_return_step, 0.001, 0.01, "%.4frad")
	_, cam_impulse_decay = ImGui.SliderFloat("Cam Impulse Decay", cam_impulse_decay, 1.0, 50.0, "%.2f")
	_, cam_step_div = ImGui.SliderFloat("Cam Step Div", cam_step_div, 1.0, 50.0, "%.2f")
end
