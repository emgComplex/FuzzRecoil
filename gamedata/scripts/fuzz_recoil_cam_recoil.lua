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
---@type fuzz_on_restoring
local __restoring_fn = M.do_restore_lerp
---@type fuzz_on_restoring
local __real_restoring_fn = M.do_restore_lerp
function M.on_option_change()
	cam_drag = options.cam_drag
	if options.use_comp_return ~= nil then
		use_comp_return = options.use_comp_return
		no_cam_restore = options.no_cam_restore
		if options.no_cam_restore then
			__restoring_fn = M.no_restore
		elseif use_comp_return then
			__restoring_fn = M.prepare_compensation
		else
			__restoring_fn = M.do_restore_lerp
		end
	end
end

----------
---COMP_RETURN, floors the pitch restore at the burst start aim, the user's
---downpull already paid that angle so restoring it would double subtract
----------
use_comp_return = true
no_cam_restore = false
--comp floor deadband, absorbs bob wobble and the one frame read skew
comp_eps = 0.003
local anchor_pitch = 0
local has_anchor = false
--camera members are inverted vs getH/getP (ChangeHP, CameraFirstEye transpose)
--so set_actor_direction takes negated angles, probe confirms in game
local write_flip_h = true
local write_flip_p = true
local write_verified = false
--auto probe, identity write at a quiet moment arms the transfer hands free
local PROBE_EPS = 0.005
local STILL_EPS = 0.001
local STILL_FRAMES_NEEDED = 5
local PROBE_MAX_TRIES = 3
local probe_pending = false
local probe_h0, probe_p0 = 0, 0
local probe_last = "not run"
local probe_tries = 0
local still_frames = 0
local still_h, still_p = nil, nil
--onerad authored angle, on screen pitch = atan(factor*sin)
local SIN_ONERAD = math.sin(0.994838)
local function effector_screen_pitch(angle)
	return math.atan(utils.math_clamp(angle, 0.0001, max_angle) * SIN_ONERAD)
end
local function screen_to_angle(pitch)
	return math.tan(math.max(pitch, 0)) / SIN_ONERAD
end
--composite camera pitch, getP is up positive (_vector3d.h atan(y/hyp))
local function cam_pitch_up()
	return device().cam_dir:getP()
end
local function angle_gap(a, b)
	local d = math.abs(a - b)
	if d > math.pi then
		d = 2 * math.pi - d
	end
	return d
end
--send the identity write, next frame drift near zero proves the sign flips
local function send_probe(h, p)
	if not db.actor then
		return
	end
	probe_h0, probe_p0 = h, p
	db.actor:set_actor_direction(write_flip_h and -h or h, write_flip_p and -p or p, 0)
	probe_pending = true
end
local function read_probe(h, p)
	probe_pending = false
	local dh, dp = angle_gap(h, probe_h0), angle_gap(p, probe_p0)
	local ok = dh < PROBE_EPS and dp < PROBE_EPS
	probe_last = string.format("dH %.4f, dP %.4f, %s", dh, dp, ok and "OK within noise" or "FLIP SUSPECT")
	return ok
end
--quiet moment probe, effector drained and camera still so the write is safe
--driven from the main update every frame so it can arm before any recoil episode
function M.update_probe(is_firing)
	if not (use_comp_return or no_cam_restore) or write_verified or probe_tries >= PROBE_MAX_TRIES then
		return
	end
	if is_firing or m_angle > 0.001 then
		still_frames = 0
		return
	end
	local d = device().cam_dir
	local h, p = d:getH(), d:getP()
	if probe_pending then
		if read_probe(h, p) then
			write_verified = true
		else
			probe_tries = probe_tries + 1
		end
		still_frames = 0
		return
	end
	if still_h and angle_gap(h, still_h) < STILL_EPS and angle_gap(p, still_p) < STILL_EPS then
		still_frames = still_frames + 1
	else
		still_frames = 0
	end
	still_h, still_p = h, p
	if still_frames >= STILL_FRAMES_NEEDED then
		send_probe(h, p)
		still_frames = 0
	end
end
function M.is_write_verified()
	return write_verified
end

--bakes the held lift into the base camera and zeroes the effector in the
--same frame, the view holds and the state resets clean
local function bake_cam_fx(pitch)
	local actor = db.actor
	if actor then
		local d = device().cam_dir
		local h = d:getH()
		local p = pitch or d:getP()
		actor:set_actor_direction(write_flip_h and -h or h, write_flip_p and -p or p, 0)
	end
end
----------
---cam delta
----------
local function set_camera_offset_delta(pitch_delta)
	--FIXME:well.......
	local real_pitch_delta = effector_screen_pitch(m_angle + pitch_delta) - effector_screen_pitch(m_angle)
	level.add_actor_camera_delta(0, real_pitch_delta)
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
local EVENT_PRE_ID = fuzz_recoil_event.getEventID("cam_recoil_pre")
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
	--NOTE: full restore if desync_hud
	__real_restoring_fn = profile.desync_hud and M.do_restore_lerp or __restoring_fn
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
	--TODO: use evnet pre once debug is done.
	--fresh episode anchors the restore floor at the current aim
	if (use_comp_return or no_cam_restore) and (is_restored or m_angle <= min_cam_restore_step) then
		anchor_pitch = cam_pitch_up()
		has_anchor = true
	end
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
	frm.on_restoring:add(EVENT_ID, __real_restoring_fn)
end

function M.restored()
	-- M.remove_cam_fx()
	frm.on_restoring:remove(EVENT_ID)
	-- FIXME: might be an issue when force reset,but simple stop is accetpable.
	-- set_player_angle(0.0001)
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
	-- set_player_angle(m_angle)
	set_camera_offset_delta(m_vel * dt)
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
	-- set_player_angle(m_angle)
	set_camera_offset_delta(step)
end
---@type fuzz_on_firing
function M.update_spring(dt)
	m_angle, m_vel = utils.apply_spring(m_angle, m_vel, dt, frm.debug_var.float_x1)
	-- set_player_angle(m_angle)
	set_camera_offset_delta(m_vel * dt)
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
function M.do_restore_lerp(dt)
	if m_angle <= min_cam_restore_step then
		M.restored()
		return
	end
	--TODO:cache this when init
	local speed_factor = base_cam_restore_speed + wepaon_cam_restore_speed
	local lerp_factor = 1.0 - math.exp(-speed_factor * dt)

	local step = m_angle * lerp_factor
	local min_step = min_cam_restore_step
	local final_step = math.max(step, min_step)
	--NOTE:vel is actually step when restoring ,im just lazy ,its easy to debug
	m_vel = final_step
	m_angle = m_angle - final_step
	-- set_player_angle(m_angle)
	set_camera_offset_delta(m_vel)
end
local function go_restore()
	--replace with old lerp restore
	frm.on_restoring:add(EVENT_ID, M.do_restore_lerp)
end
--NOTE: bake camera first then do restore, so we can share different retstoring style.
function M.prepare_compensation()
	if has_anchor then
		-- if write_verified then
		if cam_pitch_up() > anchor_pitch then
			m_angle = screen_to_angle(math.abs(cam_pitch_up() - anchor_pitch))
			-- set_player_angle(m_angle)
			-- bake_cam_fx(anchor_pitch)
			go_restore()
			return
		else
			--NOTE: no cam restore if lower than anchor
			M.no_restore(0, false)
			return
		end
		-- end
	else
		go_restore()
	end
end
---@type fuzz_on_restoring
function M.no_restore()
	if write_verified then
		-- bake_cam_fx()
		M.restored()
		logger.dbg("restored")
		return
	end
	logger.err("Unexpected Restored")
	M.restored()
end

---------
---IMGUI
--------
function M.force_set_cam()
	create_cam_effector()
	max_angle = 6666
	set_player_angle(frm.debug_var.float_s1)
end
function M.force_bake()
	local actor = db.actor
	bake_cam_fx()
	M.remove_cam_fx()
end
function M.imgui_info_drawer()
	ImGui.TextColored(vector4():set(0, 1, 0.5, 1), "Camera recoil")
	local angle_text = string.format("Cam angle: %.3frad,%.2fdeg", m_angle, math.deg(m_angle))
	ImGui.ProgressBar(m_angle, vector2():set(-1, 0), angle_text)
	ImGui.Text(string.format("Cam velocity: %.3f", m_vel))
	ImGui.Text(string.format("Cam Dir Pitch:%.4f", device().cam_dir:getP()))
	if has_anchor then
		ImGui.Text(
			string.format(
				"Comp anchor: %.2fdeg, room %.2fdeg",
				math.deg(anchor_pitch),
				math.deg(cam_pitch_up() - anchor_pitch)
			)
		)
	else
		ImGui.Text("Comp anchor: none")
	end
end
function M.imgui_config_drawer()
	ImGui.Text("Cam Recoil Config")
	_, base_cam_restore_speed = ImGui.SliderFloat("Base Cam Restore Speed", base_cam_restore_speed, 0.1, 10, "%.2frad")
	_, min_cam_restore_step = ImGui.SliderFloat("Min Cam Restore step", min_cam_restore_step, 0.001, 0.01, "%.4frad")
	_, cam_impulse_decay = ImGui.SliderFloat("Cam Impulse Decay", cam_impulse_decay, 1.0, 50.0, "%.2f")
	_, cam_step_div = ImGui.SliderFloat("Cam Step Div", cam_step_div, 1.0, 50.0, "%.2f")
	ImGui.Separator()
	_, restore_smooth = ImGui.Checkbox("Smooth Restore Enabled", restore_smooth)
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
