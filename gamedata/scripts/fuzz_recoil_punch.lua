local frm = fuzz_recoil
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger
local options = fuzz_recoil_mcm

local M = {}
_G.fuzz_recoil_punch = M

----------
---Per shot punch, fov widen at hip, positional shove while aiming
----------
--hip fov punch rides the effector m_fov channel (no g_fov cvar write, auto clears)
--any ads gets a positional shove instead so the scope image and zoom never pump
--one relative effector carries both, factor is the shove, m_fov is the fov punch
local PUNCH_FX_ID = 7900
--magnitude of oneshove.anm Z channel, position is linear in factor
local ONESHOVE_UNIT = 0.994838
local EPS = 0.001
--live on the PiP exe, absent on older non PiP builds where the console is the fallback
local has_fov_binding = level.set_cam_effector_fov ~= nil

local use_punch = false
--legacy reverts to the prior system, console fov and is_svp_active routing
local legacy = false
local m_punch = 0
--true base fov cached on the rising edge, nil when no punch is active
local base_fov = nil
local fov_on = false
local shove_on = false

--peak fov widen in degrees at full punch
local punch_fov_deg = 6.0
--peak shove in meters at full punch, sign set in game
local punch_shove = 0.06
--impulse added per shot and the auto fire ceiling
local punch_impulse = 0.6
local punch_max = 1.2
--exponential decay rate, higher is snappier
local punch_decay = 18

----------
---Punch effector, factor is the shove, m_fov is the hip fov punch
----------
local function create_punch_effector()
	if not level.check_cam_effector(PUNCH_FX_ID) then
		level.add_cam_effector("camera_effects\\oneshove.anm", PUNCH_FX_ID, true, "", 0, true, 0.0001)
	end
end
local function remove_punch_effector()
	if level.check_cam_effector(PUNCH_FX_ID) then
		level.remove_cam_effector(PUNCH_FX_ID)
	end
end
local function set_shove(dist)
	if level.check_cam_effector(PUNCH_FX_ID) then
		level.set_cam_effector_factor(PUNCH_FX_ID, utils.math_clamp(dist / ONESHOVE_UNIT, -0.5, 0.5))
	end
end
--true PiP test for the legacy route, guarded so non PiP exes read false
local function scoped_now()
	return is_svp_active and is_svp_active()
end
--effector m_fov unless legacy or the binding is missing, then the console channel
local function fov_via_effector()
	return has_fov_binding and not legacy
end
--absolute target fov
local function push_fov(deg)
	if fov_via_effector() then
		if level.check_cam_effector(PUNCH_FX_ID) then
			level.set_cam_effector_fov(PUNCH_FX_ID, deg)
		end
	else
		exec_console_cmd(string.format("fov %.3f", deg))
	end
end
local function clear_shove()
	if shove_on then
		set_shove(0)
		shove_on = false
	end
end
--drop the fov punch, effector m_fov clears to 0, the console channel restores the base
local function clear_fov()
	if not fov_on then
		return
	end
	if fov_via_effector() then
		if level.check_cam_effector(PUNCH_FX_ID) then
			level.set_cam_effector_fov(PUNCH_FX_ID, 0)
		end
	elseif base_fov then
		exec_console_cmd(string.format("fov %.3f", base_fov))
	end
	fov_on = false
end
--fully release both channels and forget the base
local function release()
	clear_fov()
	clear_shove()
	base_fov = nil
	m_punch = 0
end

----------
---Event
----------
local EVENT_ID = fuzz_recoil_event.getEventID("cam_punch")
local function sub_events(flag)
	if flag then
		--add event
		frm.on_init_wpn:add(EVENT_ID, M.init)
		frm.on_start:add(EVENT_ID, M.start)
		frm.on_shot:add(EVENT_ID, M.on_shot)
		frm.on_firing:add(EVENT_ID, M.on_firing)
		frm.on_firing_stop:add(EVENT_ID, M.on_firing_stop)
		frm.on_stop:add(EVENT_ID, M.stop)
	else
		-- remove event
		frm.on_init_wpn:remove(EVENT_ID)
		frm.on_start:remove(EVENT_ID)
		frm.on_shot:remove(EVENT_ID)
		frm.on_firing:remove(EVENT_ID)
		frm.on_firing_stop:remove(EVENT_ID)
		frm.on_stop:remove(EVENT_ID)
		frm.on_restoring:remove(EVENT_ID, true)
	end
end
----------
---Public
----------
function M.awake()
	M.instance = M
	return M
end
---@type fuzz_on_init_wpn
function M.init()
	M.stop()
end
function M.on_option_change()
	--clear via the old mode channel before switching so a toggle never strands a punch
	if options.punch_legacy ~= legacy then
		release()
	end
	legacy = options.punch_legacy
	local enable = options.use_punch
	if use_punch ~= enable then
		use_punch = enable
		sub_events(enable)
	end
end
---@type fuzz_on_start
function M.start(profile)
	create_punch_effector()
	set_shove(0)
end
---@type fuzz_on_stop
function M.stop()
	release()
	remove_punch_effector()
end

---@type fuzz_on_shot
function M.on_shot(_, scale)
	--cache the true base once, the console fallback would otherwise read its own punch
	if base_fov == nil then
		base_fov = get_console_cmd(2, "fov")
	end
	m_punch = math.min(m_punch + punch_impulse * (scale or 1), punch_max)
end

--returns true once the punch has fully settled so the caller can tear down
function M.update_internal(dt, is_ads)
	if m_punch <= EPS then
		if fov_on or shove_on or base_fov then
			release()
		end
		return true
	end
	m_punch = m_punch * math.exp(-punch_decay * dt)
	--legacy shoves on true PiP and fov punches everywhere else, default shoves on any aim
	local shove_here
	if legacy then
		shove_here = scoped_now()
	else
		shove_here = is_ads
	end
	if shove_here then
		--positional shove leaves the scope image and ads zoom untouched
		clear_fov()
		set_shove(m_punch * punch_shove)
		shove_on = true
	else
		--absolute fov punch on top of the cached base
		clear_shove()
		if base_fov then
			push_fov(base_fov + m_punch * punch_fov_deg)
			fov_on = true
		end
	end
	return false
end

---@type fuzz_on_firing
function M.on_firing(dt, _, is_ads)
	M.update_internal(dt, is_ads)
end
---@type fuzz_on_firing_stop
function M.on_firing_stop()
	frm.on_restoring:add(EVENT_ID, M.on_restoring)
end
---@type fuzz_on_restoring
function M.on_restoring(dt, is_ads)
	if M.update_internal(dt, is_ads) then
		frm.on_restoring:remove(EVENT_ID)
	end
end

----------
---IMGUI
----------
function M.imgui_config_drawer()
	ImGui.Text(
		string.format(
			"Punch Config (fov binding: %s, mode: %s)",
			has_fov_binding and "yes" or "no",
			legacy and "legacy console/PiP" or "effector hip/ads"
		)
	)
	_, punch_fov_deg = ImGui.SliderFloat("Punch FOV deg", punch_fov_deg, 0.0, 12.0, "%.2f")
	_, punch_shove = ImGui.SliderFloat("Punch Shove m", punch_shove, -0.1, 0.1, "%.3f")
	_, punch_impulse = ImGui.SliderFloat("Punch Impulse", punch_impulse, 0.1, 2.0, "%.2f")
	_, punch_max = ImGui.SliderFloat("Punch Max", punch_max, 0.2, 3.0, "%.2f")
	_, punch_decay = ImGui.SliderFloat("Punch Decay", punch_decay, 4.0, 40.0, "%.1f")
end
