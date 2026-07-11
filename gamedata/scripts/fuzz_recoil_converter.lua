converter = {}
local utils = fuzz_utils or fuzz_recoil_utils.fuzz_utils

local wpn_profile_def = {
	is_bolt_action = false,
	cam_recoil_power = 4,
	cam_return_speed = 1,
	cam_max_angle = 0,
	pitch_frac = 1,
	zoom_ratio = 1,

	shot_pitch = 15,
	shot_pos_y = -0.04,
	shot_yaw = 15,
	shot_pos_x = 0.0006,

	pull_force = 1.5,
	firing_damping = 1.0,
	shot_pos_z = 0.006,

	handling_speed = 0.5,
	increase_rate = 0,
	-- mass_inertia = -1,
}

local wpn_info_def = {
	cam_dispersion = 0,
	cam_dispersion_inc = 0,
	zoom_cam_dispersion = 0,
	zoom_cam_dispersion_inc = 0,
	cam_step_angle_horz = 0,
	cam_relax_speed = 0,
	addon_cam_k = 1,
	addon_cam_inc_k = 1,
	inv_weight = 0,
	rpm = 600,
}
converter.rule = {
	["cam_recoil_power"] = { offset = 1, from = { min = 0, max = 4 }, to = { min = 1, max = 5 } },
	["cam_return_speed"] = { offset = 0, from = { min = 0, max = 10 }, to = { min = 0, max = 2 }, clamp = true },

	["shot_pitch"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 3, max = 16 }, clamp = true },
	["shot_pos_y"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 0, max = -0.08 }, clamp = true },
	["shot_pos_z"] = { offset = 0, from = { min = 0, max = 4 }, to = { min = 0.003, max = 0.012 }, clamp = true },
	["shot_yaw"] = { offset = 0, from = { min = 0, max = 2 }, to = { min = 0, max = 1 }, clamp = true },
	["shot_pos_x"] = { offset = 0, from = { min = 0, max = 2 }, to = { min = 0, max = 0.001 }, clamp = true },

	["pull_force"] = { offset = 1, from = { min = 0, max = 0.09 }, to = { min = 0.8, max = 0.3 }, clamp = true },
	-- ["firing_damping"] = { offset = 0, from = { min = 0.1, max = 0.7 }, to = { min = 1, max = 1.5 } },

	["handling_speed"] = { offset = 0.3, from = { min = 0, max = 0.09 }, to = { min = 0.35, max = 0 }, clamp = true },
	-- ["increase_rate"] = { offset = 0, from = { min = 0.1, max = 0.7 }, to = { min = 1, max = 1.5 } },
}
converter.convert = function(op, np)
	-- op = wpn_info
	-- np = wpn_profile
	--cam side addon koef is applied per shot at runtime (state.shot_cam_k)
	--inc koef stays here, it feeds nonlinear handling lerps
	local cam_disp_inc = op.cam_dispersion_inc * (op.addon_cam_inc_k or 1)

	np.cam_recoil_power = op.cam_dispersion
	np.cam_return_speed = op.cam_relax_speed

	np.shot_pitch = op.cam_dispersion
	np.shot_pos_y = op.cam_dispersion
	np.shot_pos_z = op.cam_dispersion
	np.shot_yaw = op.cam_step_angle_horz
	np.shot_pos_x = op.cam_step_angle_horz

	np.pull_force = cam_disp_inc
	np.handling_speed = cam_disp_inc
	apply_rules(np, converter.rule)
	np.firing_damping = 1
	np.is_bolt_action = is_bolt_action(op)

	--cam_angle is radians, ini cam_max_angle is degrees
	np.cam_max_angle = op.cam_max_angle > 0 and math.rad(op.cam_max_angle) or 0
	np.pitch_frac = utils.math_clamp(op.cam_dispersion_frac or 1, 0, 1)
	--engine growth ratio, per shot kick = base*(1 + (inc/base)*n)
	np.increase_rate = op.cam_dispersion > 0 and op.cam_dispersion_inc / op.cam_dispersion or 0
	--vanilla ads to hip recoil ratio, defaults to 1 when the ini omits zoom keys
	np.zoom_ratio = op.cam_dispersion > 0
			and utils.math_clamp(op.zoom_cam_dispersion / op.cam_dispersion, 0.25, 2)
		or 1

	np.shot_yaw = np.shot_pitch + np.shot_yaw

	--TODO: Kind bonus
	--TODO: mass bonus
end
function apply_rules(np, rule)
	for k, v in pairs(rule) do
		np[k] = utils.range_lerp(np[k], v.from, v.to, v.offset, v.clamp)
	end
end
function is_bolt_action(op)
	if op.kind ~= "w_sniper" then
		return false
	end
	--NOTE: rpm now comes from cast_wpn:RealRPM() (60/fOneShotTime)
	--thx to @Gabriell
	return op.rpm <= 60
	--NOTE: no lua api exposes hud motion length, animation check not feasible
	-- credite @verdatim
end
