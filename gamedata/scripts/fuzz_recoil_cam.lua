local m_settings = settings or fuzz_recoil.settings
local m_cfg = config or fuzz_recoil.config
local utils = fuzz_recoil_utils
local logger = fuzz_recoil_logger

local CAM_FX_ID = 7897
local function create_cam_effector()
	if not level.check_cam_effector(CAM_FX_ID) then
		level.add_cam_effector("camera_effects\\onerad.anm", 7897, true, "", 0, true, 0.0001)
	end
end
local function has_camera_effector()
	return level.check_cam_effector(CAM_FX_ID)
end
local function set_player_angle(angle)
	--PERF: remove check if set factor does not throw
	if has_camera_effector() then
		level.set_cam_effector_factor(CAM_FX_ID, math.max(0.0001, math.min(angle, 0.999)))
	end
end
function set_cam_effect_id(id)
	CAM_FX_ID = id
end
function cam_fx_id()
	return CAM_FX_ID
end

local M = {}
_G.fuzz_recoil_cam = M

local bonus_return_speed = 0

function M:new()
	self.is_returned = false
	self.angle = 0
	self.vel = 0
	M.instance = self
	return self
end
function M:init(bspeed, mode)
	bonus_return_speed = bspeed or 0
	if mode then
		self:switch_mode(mode)
	end
	self:stop()
end
function M:start()
	create_cam_effector()
	self.is_returned = false
end
function M:stop()
	--NOTE: seems like we don't have to remove it...
	-- level.remove_cam_effector(CAM_FX_ID)
	self.is_returned = true
	self.angle = 0
	self.vel = 0
end
function M:on_fire(handle, wforce, ammo_scale, scale)
	self.is_returned = false
	handle = math.pow(1 - handle, 2)
	local cam_impulse = wforce * handle * ammo_scale --* scale
	self.vel = self.vel + cam_impulse
end

function M:update_cubic(dt)
	local drag = m_settings.cam_drag * math.sqrt(math.abs(self.vel))
	self.vel = self.vel * math.exp(-drag * dt)
	self.angle = self.angle + self.vel * dt
	set_player_angle(self.angle)
end
function M:update_exp(dt)
	-- self.cam_vel = self.cam_vel * (1.0 - dt * debug_var.float_x2)
	local decay = math.exp(-dt * 15)
	local step = self.vel * (1 - decay) / 15
	self.vel = self.vel * decay
	self.angle = self.angle + step
	set_player_angle(self.angle)
end
function M:update_spring(dt)
	--TODO: don't forget me~~~
	self.angle, self.vel = apply_spring(self.angle, self.vel, dt, debug_var.float_x1)
	set_player_angle(self.angle)
end
--TODO: enum but not here,it should be in main script so every module can use it
M.MODE = {
	EXP = 0,
	CUBIC = 1,
	SPRING = 2,
}
function M:switch_mode(mode)
	if mode == "exp" then
		self._update_fn = self.update_exp
	elseif mode == "cubic" then
		self._update_fn = self.update_cubic
	elseif mode == "spring" then
		self._update_fn = self.update_spring
	else
		self._update_fn = self.update_exp
	end
end

--NOTE: min_step is the best i can got...still can't get the final phase right.
--TODO: --maybe try simple_ease and lerp the vel to a min value?,it could be more natrual when the angle is high.
--i think it's fine for now, and maybe remove camera return in the future if we can get rid of cam_effector
--leave it here
function M:do_return(dt)
	--TODO:remove config and cache this when init
	if self.angle <= m_cfg.min_cam_return_step then
		self:stop()
		return
	end
	local speed_factor = m_cfg.base_cam_return_speed + bonus_return_speed
	local lerp_factor = 1.0 - math.exp(-speed_factor * dt)

	local step = self.angle * lerp_factor
	local min_step = m_cfg.min_cam_return_step
	local final_step = math.max(step, min_step)
	--NOTE:vel is actually step when returning ,im just lazy ,its easy to debug
	self.vel = final_step
	self.angle = self.angle - final_step
	set_player_angle(self.angle)
end

--FIXME: something feels off...
function M:update(dt, is_firing)
	-- local fn = self._update_fn or self.update_exp
	-- fn(self, dt)
	if is_firing then
		self._update_fn(self, dt)
		return false
	end
	if not self.is_returned then
		self:do_return(dt)
	end
	return self.is_returned
end
