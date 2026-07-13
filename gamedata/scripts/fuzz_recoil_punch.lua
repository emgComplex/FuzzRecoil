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

local cfg = {
	--peak fov widen in degrees at full punch
	punch_fov_deg = 4.0,
	--peak shove in meters at full punch, sign set in game
	punch_shove = 0.03,
	--impulse added per shot and the auto fire ceiling
	punch_impulse = 0.6,
	punch_max = 1.2,
	--exponential decay rate, higher is snappier
	punch_decay = 18,
}

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
---Public
----------
function M.awake()
	M.instance = M
	return M
end
function M.init()
	M.stop()
end
function M.on_option_change()
	--clear via the old mode channel before switching so a toggle never strands a punch
	if options.punch_legacy ~= legacy then
		release()
	end
	use_punch = options.use_punch
	legacy = options.punch_legacy
end
function M.start(profile)
	if use_punch then
		create_punch_effector()
		set_shove(0)
	end
end
function M.stop()
	release()
end
function M.remove_fx()
	remove_punch_effector()
end

function M.on_fire(scale)
	if not use_punch then
		return
	end
	--cache the true base once, the console fallback would otherwise read its own punch
	if base_fov == nil then
		base_fov = get_console_cmd(2, "fov")
	end
	m_punch = math.min(m_punch + cfg.punch_impulse * (scale or 1), cfg.punch_max)
end

--returns true once the punch has fully settled so the caller can tear down
function M.update(dt, is_firing, is_ads)
	if not use_punch then
		if fov_on or shove_on then
			release()
		end
		return true
	end
	if m_punch <= EPS then
		if fov_on or shove_on or base_fov then
			release()
		end
		return true
	end
	m_punch = m_punch * math.exp(-cfg.punch_decay * dt)
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
		set_shove(m_punch * cfg.punch_shove)
		shove_on = true
	else
		--absolute fov punch on top of the cached base
		clear_shove()
		if base_fov then
			push_fov(base_fov + m_punch * cfg.punch_fov_deg)
			fov_on = true
		end
	end
	return false
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
	_, cfg.punch_fov_deg = ImGui.SliderFloat("Punch FOV deg", cfg.punch_fov_deg, 0.0, 12.0, "%.2f")
	_, cfg.punch_shove = ImGui.SliderFloat("Punch Shove m", cfg.punch_shove, -0.1, 0.1, "%.3f")
	_, cfg.punch_impulse = ImGui.SliderFloat("Punch Impulse", cfg.punch_impulse, 0.1, 2.0, "%.2f")
	_, cfg.punch_max = ImGui.SliderFloat("Punch Max", cfg.punch_max, 0.2, 3.0, "%.2f")
	_, cfg.punch_decay = ImGui.SliderFloat("Punch Decay", cfg.punch_decay, 4.0, 40.0, "%.1f")
end
