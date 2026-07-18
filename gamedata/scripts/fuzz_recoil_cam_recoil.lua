local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local options = fuzz_recoil_mcm
local frm = fuzz_recoil

local M = {}
_G.fuzz_recoil_cam_recoil = M

----------
---Local Vars
----------
local is_restored = false
local m_vel = 0
local m_angle = 0
local wepaon_cam_restore_speed = 0

---@type fuzz_on_firing
local _firing_update_fn = M.update_exp
----------
---Cached vars
----------
local lift_force = 0
local impulse_factor = 0
--vanilla cam_max_angle cap in radians, 0 means uncapped
local max_angle = 0.9999
----------
---Pulibc Getters
----------
function M.get_angle()
	return m_angle
end
function M.get_vel()
	return m_vel
end
function M.is_restored()
	return is_restored
end
----------
---Configs
----------
base_cam_restore_speed = 4.0
min_cam_restore_step = 0.0045
--auto fire impulse decay and step divisor
cam_impulse_decay = 12
cam_step_div = 15
--critically damped glide to the burst start aim, off restores the exp step
restore_smooth = true
restore_ease = 1.0
----------
---Options
----------
local cam_drag = 12
function M.on_option_change()
	cam_drag = options.cam_drag
end

----------
---CAM_FX
----------
local CAM_FX_ID = 7897
local hud_sync_with_cam = true
local function create_cam_effector()
	if not level.check_cam_effector(CAM_FX_ID) then
		level.add_cam_effector("camera_effects\\onerad.anm", 7897, true, "", 0, hud_sync_with_cam, 0.0001)
	end
end
function M.has_camera_effector()
	return level.check_cam_effector(CAM_FX_ID)
end
function set_cam_effect_id(id)
	CAM_FX_ID = id
end
function cam_fx_id()
	return CAM_FX_ID
end
local function set_player_angle(angle)
	--no op until start adds the effector, resets before init are silent
	if M.has_camera_effector() then
		level.set_cam_effector_factor(CAM_FX_ID, math.max(0.0001, math.min(angle, max_angle)))
	end
end
function M.remove_cam_fx()
	if level.check_cam_effector(CAM_FX_ID) then
		level.remove_cam_effector(CAM_FX_ID)
	end
end

----------
---Event
----------
local EVENT_ID = fuzz_recoil_event.getEventID("cam_recoil")
----------
---Module
----------
function M.awake()
	M.instance = M
	frm.on_init_wpn:add(EVENT_ID, M.init)
	frm.on_start:add(EVENT_ID, M.start)
	frm.on_shot:add(EVENT_ID, M.on_shot)
	frm.on_firing_stop:add(EVENT_ID, M.on_firing_stop)
	frm.on_stop:add(EVENT_ID, M.stop)
	return M
end
function M.cache_profile(profile)
	lift_force = profile.cam_recoil_power
	impulse_factor = profile.shot_cam_impulse_factor
	wepaon_cam_restore_speed = profile.cam_restore_speed
	max_angle = profile.cam_max_angle or 0.9999
	hud_sync_with_cam = not profile.desync_hud
end
---@type fuzz_on_init_wpn
function M.init(profile)
	local mode = profile.shot_delay_enabled and "cubic" or "exp"
	if mode then
		M.switch_mode(mode)
	end
	M.restored()
	frm.on_firing:add(EVENT_ID, _firing_update_fn)
end
---@param profile fuzz_recoil_profile
---@type fuzz_on_start
function M.start(profile)
	M.cache_profile(profile)
	create_cam_effector()
	is_restored = false
end

---@type fuzz_on_shot
function M.on_shot(handle_power, scale)
	is_restored = false
	handle_power = math.pow(1 - handle_power, 2)
	local raw_impulse = lift_force * impulse_factor * (scale or 1)
	frm.add_handling_fatigue(raw_impulse)
	local cam_impulse = raw_impulse * handle_power
	m_vel = m_vel + cam_impulse
end

---@type fuzz_on_firing_stop
function M.on_firing_stop()
	--restore glides from rest, leftover kick velocity would bump upward first
	m_vel = 0
	frm.on_restoring:add(EVENT_ID, M.do_restore)
end

function M.restored()
	-- M.remove_cam_fx()
	frm.on_restoring:remove(EVENT_ID)
	set_player_angle(0.0001)
	is_restored = true
	m_angle = 0
	m_vel = 0
end
---@type fuzz_on_stop
function M.stop()
	-- NOTE: what if we don't remove cam effector at all?
	M.remove_cam_fx()
end
--scale carries the per shot koefs, frac variance, expansion and mode impulse

---@type fuzz_on_firing
function M.update_cubic(dt)
	if math.abs(m_vel) <= 0.01 then
		return
	end
	local drag = cam_drag * math.sqrt(math.abs(m_vel))
	m_vel = m_vel * math.exp(-drag * dt)
	m_angle = m_angle + m_vel * dt
	set_player_angle(m_angle)
end
---@type fuzz_on_firing
function M.update_exp(dt)
	if math.abs(m_vel) <= 0.01 then
		return
	end
	local decay = math.exp(-dt * cam_impulse_decay)
	local step = m_vel * (1 - decay) / cam_step_div
	m_vel = m_vel * decay
	m_angle = m_angle + step
	set_player_angle(m_angle)
end
---@type fuzz_on_firing
function M.update_spring(dt)
	m_angle, m_vel = utils.apply_spring(m_angle, m_vel, dt, frm.debug_var.float_x1)
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
		_firing_update_fn = M.update_exp
	elseif mode == "cubic" then
		_firing_update_fn = M.update_cubic
	elseif mode == "spring" then
		_firing_update_fn = M.update_spring
	else
		_firing_update_fn = M.update_exp
	end
end

--NOTE: min_step is the best i can got...still can't get the final phase right.
--TODO: --maybe try simple_ease and lerp the vel to a min value?,it could be more natrual when the angle is high.
--i think it's fine for now, and maybe remove camera return in the future if we can get rid of cam_effector
--leave it here
---@type fuzz_on_restoring
function M.do_restore(dt)
	--TODO:remove config and cache this when init
	if restore_smooth then
		--settled below perception, the final zero is invisible
		if m_angle <= 0.0008 and math.abs(m_vel) <= 0.01 then
			M.restored()
			return
		end
	elseif m_angle <= min_cam_restore_step then
		M.restored()
		return
	end
	local speed_factor = base_cam_restore_speed + wepaon_cam_restore_speed
	if restore_smooth then
		--critically damped glide, gentle entry and an eased settle into the aim
		local w = speed_factor * restore_ease
		local new_angle, new_vel = utils.apply_spring(m_angle, m_vel, dt, w * w)
		local final_step = m_angle - new_angle
		m_vel = new_vel
		if room_cap and final_step > room_cap then
			final_step = room_cap
			m_vel = 0
		end
		m_angle = m_angle - final_step
		set_player_angle(m_angle)
		return
	end
	local lerp_factor = 1.0 - math.exp(-speed_factor * dt)

	local step = m_angle * lerp_factor
	local min_step = min_cam_restore_step
	local final_step = math.max(step, min_step)
	--NOTE:vel is actually step when restoring ,im just lazy ,its easy to debug
	m_vel = final_step
	m_angle = m_angle - final_step
	set_player_angle(m_angle)
end

---------
---IMGUI
--------
function M.imgui_info_drawer()
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Camera recoil")
	local angle_text = string.format("Cam angle: %.3frad,%.2fdeg", m_angle, math.deg(m_angle))
	ImGui.ProgressBar(m_angle, vector2():set(-1, 0), angle_text)
	ImGui.Text(string.format("Cam velocity: %.3f", m_vel))
end
function M.imgui_config_drawer()
	ImGui.Text("Cam Recoil Config")
	_, base_cam_restore_speed = ImGui.SliderFloat("Base Cam Restore Speed", base_cam_restore_speed, 0.1, 10, "%.2frad")
	_, min_cam_restore_step = ImGui.SliderFloat("Min Cam Restore step", min_cam_restore_step, 0.001, 0.01, "%.4frad")
	_, cam_impulse_decay = ImGui.SliderFloat("Cam Impulse Decay", cam_impulse_decay, 1.0, 50.0, "%.2f")
	_, cam_step_div = ImGui.SliderFloat("Cam Step Div", cam_step_div, 1.0, 50.0, "%.2f")
	ImGui.Separator()
	_, restore_smooth = ImGui.Checkbox("Smooth Restore", restore_smooth)
	_, restore_ease = ImGui.SliderFloat("Restore Ease", restore_ease, 0.3, 3.0, "%.2f")
	ImGui.Separator()
	_, use_comp_return = ImGui.Checkbox("Comp Return Floor", use_comp_return)
	_, comp_eps = ImGui.SliderFloat("Comp Floor Eps", comp_eps, 0.0, 0.02, "%.4frad")
	_, write_flip_h = ImGui.Checkbox("Write Flip H", write_flip_h)
	_, write_flip_p = ImGui.Checkbox("Write Flip P", write_flip_p)
	_, write_verified = ImGui.Checkbox("Write Verified, arms transfer", write_verified)
	if probe_pending then
		local d = device().cam_dir
		if read_probe(d:getH(), d:getP()) then
			write_verified = true
		end
	end
	--identity write while standing still, a wrong flip shows as a view snap
	if ImGui.Button("Probe Cam Write") then
		local d = device().cam_dir
		send_probe(d:getH(), d:getP())
	end
	ImGui.Text("Probe: " .. probe_last)
end
