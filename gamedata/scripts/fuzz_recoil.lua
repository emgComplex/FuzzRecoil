local M = { version = "v0.1.2" }
_G.fuzz_recoil = M
---@diagnostic disable: lowercase-global
--------------------
---Event
--------------------
local Event = fuzz_recoil_event

local HP_EVENT_ID = Event.getEventID("handling_power")

--FIXME:i don't now how to make generic type working for class

---@alias fuzz_on_init_wpn fun(profile:fuzz_recoil_profile, cast_wpn:CWeapon, wpn_sec:any)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_init_wpn),invoke: fun(self: FuzzEvent, profile:fuzz_recoil_profile, cast_wpn:CWeapon, wpn_sec:any) }
---
M.on_init_wpn = Event.new("init_weapon")

---@alias fuzz_on_start fun(profile:fuzz_recoil_profile)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_start),
---invoke: fun(self: FuzzEvent, profile:fuzz_recoil_profile) }
M.on_start = Event.new("start")

---@alias fuzz_on_before_fire fun(is_ads:boolean)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_before_fire),
---invoke: fun(self: FuzzEvent,is_ads:boolean) }
M.on_before_fire = Event.new("before_fire")

---@alias fuzz_on_before_shot fun(hp:number, impulse_scale:any, ads:boolean, ...)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_before_shot),
---invoke: fun(self: FuzzEvent, hp:number, impulse_scale:any, ads:boolean, ...) }
M.on_before_shot = Event.new("before_shot")

---@alias fuzz_on_shot fun(hp:number, impulse_scale:any, ads:boolean, ...)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_shot),
---invoke: fun(self: FuzzEvent, hp:number, impulse_scale:any, ads:boolean, ...) }
M.on_shot = Event.new("on_shot")

--NOTE: dt must be first for handling_power

---@alias fuzz_on_firing fun(dt:number, hp:number, ads:boolean)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_firing),
---invoke: fun(self: FuzzEvent, dt:number, hp:number, ads:boolean) }
M.on_firing = Event.new("on_firing")

---@alias fuzz_on_firing_stop fun()
---@type FuzzEvent|{add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_firing_stop)}
M.on_firing_stop = Event.new("firing_stop")

--NOTE: dt must be first for handling_power

---@alias fuzz_on_restoring fun(dt:number,ads:boolean)
---@type FuzzEvent|{ add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_restoring),
---invoke: fun(self: FuzzEvent, dt:number, ads:boolean) }
M.on_restoring = Event.new("restoring")

---@alias fuzz_on_stop fun()
---@type FuzzEvent|{add: fun(self: FuzzEvent, key: integer, handler: fuzz_on_stop)}
M.on_stop = Event.new("stop")

local m_events = {
	M.on_init_wpn,
	M.on_start,
	M.on_before_fire,
	M.on_shot,
	M.on_firing,
	M.on_firing_stop,
	M.on_stop,
}
function M.GetEventInfo()
	for _, e in pairs(m_events) do
		e:print_handlers()
	end
end
function M.GetEventRestoringInfo()
	M.on_restoring:print_handlers()
end

--------------------
---Import
--------------------
local utils = fuzz_recoil_utils
local cvter = fuzz_recoil_converter
local logger = fuzz_recoil_logger
local Profile = fuzz_recoil_profile
local options = fuzz_recoil_mcm
local camrc = fuzz_recoil_cam_recoil.awake()
local hudrc = fuzz_recoil_hud_recoil.awake()
local punchrc = fuzz_recoil_punch.awake()

local wct = weapon_cover_tilt

---@type fuzz_recoil_profile
local m_profile = Profile.new()
---@class fuzz_recoil_wpn_info
local m_wpn_info = {
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
	addon_cam_k = 1,
	addon_cam_inc_k = 1,
	inv_weight = 0,
}

---@class CachedWeaponEntry
---@field profile fuzz_recoil_profile
---@field wpn_info fuzz_recoil_wpn_info

---@type CachedWeaponEntry[]
local cached_weapons = {}

------------
local cur_wpn = nil
---@type CWeapon
local cur_cast_wpn = nil
local cur_wpn_id = 0
local player = nil
--------- state
local enabled = true
local active = false
local is_firing = false
local handling_power = 0.0
local handling_fatigue = 0
local real_handling_power = 0
local impulse_scale = 1
--shots in the current burst, drives heat and recoil expansion
local burst_shots = 0
--refreshed per shot, addon koefs x ammo k_cam_dispersion and ads flag
local is_ads = false
local shot_cam_k = 1
--attached addon fingerprint, throttled check in on_update
local addon_sig = ""
local check_addon_timer = 0
------- config
local allowed_kinds = {
	w_pistol = true,
	w_rifle = true,
	w_shotgun = true,
	w_sniper = true,
	w_smg = true,
}
local firing_handling_ease = utils.simple_ease.new(1, 1, 0.2, 4)
local idle_handling_ease = utils.simple_ease.new(-1, -1, 0.2, 6)
--NOGUI
local FATIGUE_MAX_POWER = 0.55
sniper_idle_handling = { offset = 0.2, intensity = 0.8 }

--------------------
---Public Getter
--------------------
function M.get_wpn_info()
	return m_wpn_info
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
function M.get_real_handling_power()
	local fatigue_scale = 1
	if handling_fatigue > 1 then
		fatigue_scale = 1 - utils.lerp_in(handling_fatigue - 1, 0, FATIGUE_MAX_POWER)
	end
	return handling_power * fatigue_scale
end
function M.get_shot_cam_k()
	return shot_cam_k
end
function M.get_handling_eases()
	return firing_handling_ease, idle_handling_ease
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
	-- RegisterScriptCallback("actor_on_first_update", actor_on_first_update)
	RegisterScriptCallback("actor_on_changed_slot", actor_on_changed_slot)
	RegisterScriptCallback("actor_on_weapon_before_fire", actor_on_weapon_before_fire)
	RegisterScriptCallback("actor_on_weapon_fired", actor_on_weapon_fired)
	RegisterScriptCallback("actor_on_update", actor_on_update)
	if wct then
		wct.add_callback("actor_on_weapon_tilting", actor_on_weapon_tilt_start)
		wct.add_callback("actor_on_weapon_tilting_back", actor_on_weapon_tilt_end)
	end
end
-- function actor_on_first_update()
-- logger.dbg("first update")
-- end

function M.on_option_change()
	logger.on_option_change()
	cvter.on_option_change()
	hudrc.on_option_change()
	camrc.on_option_change()
	punchrc.on_option_change()

	cached_weapons = {}
	bloom_on_option_change()
	add_option_scale_modifiers()
	m_profile:reload_static_modier()
	-- logger.dbg("apply options to hud")
end
function actor_on_changed_slot()
	--NOTE: i think calling  this will cause cam glith when camera not fully is_cam_restored
	--Never seen it happens since switching animation will give us a natrual delay
	--but if it happens we can fix it with a TimeEvent
	M.force_reset_recoil()
	M.check_current_weapon()
end
function actor_on_weapon_before_fire()
	if not enabled then
		return
	end
	-- logger.dbg("Before Shot ")
	if not active then
		active = M.check_current_weapon()
	end
	--the engine reads dispersion when the bullet leaves, apply before the first one
	--WARN: this could called without actually shooting caused by:
	--misfire ,no ammo, ...?
	if active then
		M.on_before_fire:invoke(is_ads)
	end
end
function actor_on_weapon_fired()
	if not enabled then
		return
	end
	--grenade launcher shots keep vanilla behavior, no rifle impulse
	if cur_wpn and cur_wpn:weapon_in_grenade_mode() then
		return
	end
	--first draw reaches here with active already true, check the effector too
	if not active or not camrc.has_camera_effector() then
		start_recoil()
	end
	-- logger.dbg("Shot ")

	is_firing = true

	-- ammo_addon_koefs_on_shot()

	--ads or hip impulse mul reaches cam and punch in every hud mode
	impulse_scale = shot_cam_k * hudrc.get_ads_hip_mul(is_ads)
	M.on_shot:invoke(real_handling_power, impulse_scale, is_ads, shot_cam_k, burst_shots)

	--TODO: instead of burst_shot,heating should implemented by a new system like how fatigue works
	burst_shots = burst_shots + 1
end
function actor_on_update()
	local dt = device().time_delta / 1000
	--arms the comp transfer at any quiet moment, cheap and independent of active
	--TODO: EVENT on_update_always
	camrc.update_probe(is_firing)
	update_fatigue(dt)
	if not active then
		return
	end

	--TODO: EVENT on_update_pre_firing
	check_addon(dt)

	---@diagnostic disable-next-line: need-check-nil, undefined-field
	if is_firing and cur_wpn:get_state() ~= 5 then
		firing_stop()
	end

	--stance can change without a shot, keep it current
	is_ads = cur_cast_wpn:IsZoomed() and true or false

	if is_firing then
		M.on_firing:invoke(dt, handling_power, is_ads)
	else
		M.on_restoring:invoke(dt, is_ads)
	end
end
function firing_stop()
	is_firing = false
	burst_shots = 0
	M.on_restoring:add(HP_EVENT_ID, handling_update_restoring)
	M.on_firing_stop:invoke()
	-- logger.dbg("Fire stopped")
end
----------------------
---Compat hook
---------------------
function actor_on_weapon_tilt_start()
	enabled = false
	if active then
		M.force_reset_recoil()
		hudrc.enable_hud_adjust()
	end
end

function actor_on_weapon_tilt_end()
	enabled = true
end
----------------------
---Recoil state
---------------------
function start_recoil()
	active = true
	get_actor_state()
	add_actor_stat_modifiers()
	M.dynamic_modifiers:refresh_modi_cache()
	m_profile:apply_dynamic_modifiers()
	M.on_start:invoke(m_profile)
	-- M.on_start:print_handlers()
	-- M.on_firing:print_handlers()
	-- logger.dbg("Start Recoil")
end
function stop_recoil()
	active = false
	is_firing = false
	burst_shots = 0
	handling_power = 0

	M.on_stop:invoke()

	-- logger.dbg("reset recoil")
end
function M.force_reset_recoil()
	camrc.restored()
	hudrc.restored()
	M.on_restoring:remove_all()
end

----------------------
---Internal features
---------------------
--addon swap while adjust mode is on sticks the hands, reset and reinit instead
function check_addon(dt)
	if check_addon_timer >= 0.25 then
		check_addon_timer = 0
		if get_addon_sig() ~= addon_sig then
			M.force_reset_recoil()
			cur_wpn_id = 0
			return
		end
	else
		check_addon_timer = check_addon_timer + dt
	end
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

function update_fatigue(dt)
	if not is_firing and handling_fatigue > 0 then
		--NOTE: regen from 1 is by design, you can try turn it off
		handling_fatigue = math.min(1, handling_fatigue - 0.18 * dt)
	end
end
---@type fuzz_on_init_wpn
function handling_init(profile)
	-- inil some recoil paramete from here
	firing_handling_ease:set_speed(profile.handling_speed)
	idle_handling_ease:set_speed(profile.handling_speed)

	if profile.is_bolt_action then
		idle_handling_ease.intensity = sniper_idle_handling.intensity
		idle_handling_ease.offset = sniper_idle_handling.offset
	else
		idle_handling_ease:reset()
	end
end
---@type fuzz_on_firing
function handling_update_firing(dt)
	handling_power = utils.math_clamp(firing_handling_ease:update(handling_power, dt), 0, 1)
	real_handling_power = M.get_real_handling_power()
end
---@type fuzz_on_restoring
function handling_update_restoring(dt)
	handling_power = utils.math_clamp(idle_handling_ease:update(handling_power, dt), 0, 1)
	if handling_power <= 0 then
		M.on_restoring:remove(HP_EVENT_ID)
	end
end

local SHOT_DELAY_EVENT_ID = Event.getEventID("shot_delay")
local shot_delay_timer = 0
local shot_dealy_duration = 0.4
---@param profile fuzz_recoil_profile
function shot_delay_init(profile)
	if profile.shot_delay_enabled then
		M.on_shot:add(SHOT_DELAY_EVENT_ID, shot_delay_on_shot)
		M.on_firing:add(SHOT_DELAY_EVENT_ID, shot_dealy_on_firing)
		shot_dealy_duration = profile.shot_delay_time
	else
		M.on_shot:remove(SHOT_DELAY_EVENT_ID)
		M.on_firing:remove(SHOT_DELAY_EVENT_ID)
	end
end

---@type fuzz_on_shot
function shot_delay_on_shot()
	shot_delay_timer = 0
end
---@type fuzz_on_firing
function shot_dealy_on_firing(dt)
	if shot_delay_timer >= shot_dealy_duration then
		firing_stop()
		shot_delay_timer = 0
	end
	shot_delay_timer = shot_delay_timer + dt
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
		math.rad(m_wpn_info.cam_dispersion),
		math.rad(m_wpn_info.cam_dispersion_inc),
		math.rad(m_wpn_info.zoom_cam_dispersion),
		math.rad(m_wpn_info.zoom_cam_dispersion_inc)
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
	local cache = cached_weapons[cur_wpn_id]
	if cache then
		logger.dbg("use cached(%s) for %s", cur_wpn_id, wpn_sec)
		m_profile = cache.profile
		m_wpn_info = cache.wpn_info
	else
		logger.dbg("create cached(%s) for %s", cur_wpn_id, wpn_sec)
		get_upgrade_wpn_info()
		get_basic_wpn_info()
		get_feat_wpn_info()
		-- for k, v in pairs(wpn_info) do
		-- 	logger.dbg(type(v) == "number" and "%s:%.6f" or "%s:%s", k, v)
		-- end
		m_profile = fuzz_recoil_profile.new():load(wpn_sec, m_wpn_info)
		cached_weapons[cur_wpn_id] = {
			wpn_info = m_wpn_info,
			profile = m_profile,
		}
	end
	check_upgrade(wpn_sec)
	m_profile:apply_static_modifiers()
	remove_vanilla_cam_recoil()
	M.on_init_wpn:invoke(m_profile, cur_cast_wpn, wpn_sec)
	-- ammo_addon_koefs_init()

	addon_sig = get_addon_sig()
	logger.dbg("Initialize weapon")
end
function M.force_invoke_init(profile)
	if not cur_wpn or cur_wpn_id <= 0 then
		return
	end
	local wpn_sec = cur_wpn:section()
	M.on_init_wpn:invoke(profile, cur_cast_wpn, wpn_sec)
end
--TODO:if using cached profile , we need check upgrades and call this agian
--NOTE: engine getters return the live post-upgrade values in radians,
--converter rules are tuned to ini degrees, so convert back with math.deg
function get_upgrade_wpn_info()
	m_wpn_info.cam_dispersion = math.deg(cur_cast_wpn:GetCamDispersion())
	m_wpn_info.cam_dispersion_inc = math.deg(cur_cast_wpn:GetCamDispersionInc())
	m_wpn_info.cam_step_angle_horz = math.deg(cur_cast_wpn:GetCamStepAngleHorz())
	-------this could change by upgrade
	m_wpn_info.rpm = cur_cast_wpn:RealRPM()
end
function get_basic_wpn_info()
	--still these could change by upgrade but we don't care
	m_wpn_info.mag_size = cur_cast_wpn:GetAmmoMagSize()
	m_wpn_info.zoom_cam_dispersion = math.deg(cur_cast_wpn:GetZoomCamDispersion())
	m_wpn_info.zoom_cam_dispersion_inc = math.deg(cur_cast_wpn:GetZoomCamDispersionInc())
	m_wpn_info.cam_relax_speed = math.deg(cur_cast_wpn:GetCamRelaxSpeed())
end
function get_feat_wpn_info()
	--live weight includes attached addons
	m_wpn_info.inv_weight = cur_cast_wpn:Weight()
end
function read_upgrade_wpn_info(wpn_sec)
	return {
		cam_dispersion = utils.get_float(wpn_sec, "cam_dispersion"),
		cam_dispersion_inc = utils.get_float(wpn_sec, "cam_dispersion_inc"),
		cam_step_angle_horz = utils.get_float(wpn_sec, "cam_step_angle_horz"),
	}
end
local function get_upgrade_count()
	count = 0
	cur_wpn:iterate_installed_upgrades(function(_, _)
		count = count + 1
	end)
	return count
end
--TODO:consider refactor this to profile
function check_upgrade(wpn_sec)
	local upd_count = get_upgrade_count()
	if upd_count == 0 then
		remove_upgrade_modifiers()
		return
	end

	--set interval no matter what
	m_profile:set_fire_interval(m_wpn_info.rpm)

	--NOTE: there could be some diffences between converted profile and ltx profile
	if m_profile:is_converted() then
		get_upgrade_wpn_info()
		m_profile:apply_converted_upgrade(m_wpn_info)
		return
	end
	-- NOTE: can't use that,modifier is not per-profile-based
	-- if not m_profile:checkUpgrades(get_upgrade_count()) then
	-- 	return
	-- end
	get_upgrade_wpn_info()
	local ori_info = read_upgrade_wpn_info(wpn_sec)
	local function gp(ori, now)
		logger.dbg("%s,%s,%s", ori, now, ((now - ori) / ori + 1))
		return (now - ori) / ori + 1
	end
	add_upgrades_modifiers(
		gp(ori_info.cam_dispersion, m_wpn_info.cam_dispersion),
		gp(ori_info.cam_step_angle_horz, m_wpn_info.cam_step_angle_horz),
		--NOTE:the handling speed is not accurate,but let's keep things simple
		gp(ori_info.cam_dispersion_inc, m_wpn_info.cam_dispersion_inc)
	)
end
---@diagnostic enable: undefined-field,need-check-nil
----------------------
---Weapon Check
---------------------
--TODO: fallback to vanilla if something went wrong
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
		--an upgrade can land while equipped, recheck when waking from idle
		if not active and cur_cast_wpn then
			check_upgrade(cur_wpn:section())
		end
		return active
	end
	--NOTE: give the previous weapon its vanilla cam recoil back,
	--otherwise re-equipping it would collect our zeroed values
	if cur_wpn_id ~= -1 then
		restore_vanilla_cam_recoil()
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
	m_wpn_info.kind = kind
	--a failed init keeps vanilla recoil instead of a zero recoil gun
	local ok, err = pcall(init_weapon, wpn_sec)
	if not ok then
		logger.err("init_weapon failed for %s, vanilla recoil kept: %s", wpn_sec, tostring(err))
		restore_vanilla_cam_recoil()
		cur_wpn_id = -1
		return false
	end
	return true
end
function M.force_recheck_weapon()
	cached_weapons[cur_wpn_id] = nil
	cur_wpn_id = -2
	M.check_current_weapon()
end
----------------------
---Extra Feat
---------------------
--TODO: bad coupling
--================addon ammo koef
--engine clamps addon koefs to [0.01, 2.0], empty section means koef 1 like engine reset
local function get_addon_koef(sec, key)
	if not sec or sec == "" then
		return 1
	end
	return utils.math_clamp(utils.get_float(sec, key, 1), 0.01, 2.0)
end
---@diagnostic disable: need-check-nil
--NOTE: engine multiplies cam recoil by attached addon section koefs (EffectorShot.cpp)
function ammo_addon_koefs_init()
	if not options.use_addon_ammo_koefs then
		m_wpn_info.addon_cam_k = 1
		m_wpn_info.addon_cam_inc_k = 1
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
	m_wpn_info.addon_cam_k = cam_k
	m_wpn_info.addon_cam_inc_k = cam_inc_k
end
--k_cam_dispersion of the selected ammo type, default 1 unclamped like engine
--NOTE: engine uses the chambered round, no lua export, selected type is the best approximation
local function get_ammo_cam_k()
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
---@diagnostic disable: need-check-nil
--refresh per shot so addon attach, ammo switch and ads state apply without a weapon re draw
function ammo_addon_koefs_on_shot()
	if not cur_cast_wpn or not options.use_addon_ammo_koefs then
		shot_cam_k = 1
		return
	end
	ammo_addon_koefs_init()
	shot_cam_k = m_wpn_info.addon_cam_k * get_ammo_cam_k() * impulse_scale
end

--================Bloom
--fire bloom state, heat in cone multiples over the cached vanilla base
local bloom_heat = 0
local orig_fire_disp = -1
local bloom_applied = -1
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
	bc = { base = 0.6, rate = 0.13, max = 2.8 },
}
local BLOOM_EVENT_ID = Event.getEventID("bloom")
function M.get_bloom_state()
	return bloom_heat, bloom_applied, orig_fire_disp
end
function bloom_on_option_change()
	if options.use_bloom then
		M.on_init_wpn:add(BLOOM_EVENT_ID, bloom_init)
		M.on_before_fire:add(BLOOM_EVENT_ID, bloom_before_fire)
		M.on_shot:add(BLOOM_EVENT_ID, bloom_on_shot)
		M.on_firing:add(BLOOM_EVENT_ID, bloom_update)
		M.on_restoring:add(BLOOM_EVENT_ID, bloom_restore)
		M.on_stop:add(BLOOM_EVENT_ID, bloom_on_stop)
	else
		M.on_init_wpn:remove(BLOOM_EVENT_ID)
		M.on_before_fire:remove(BLOOM_EVENT_ID)
		M.on_shot:remove(BLOOM_EVENT_ID)
		M.on_firing:remove(BLOOM_EVENT_ID)
		M.on_restoring:remove(BLOOM_EVENT_ID)
		M.on_stop:remove(BLOOM_EVENT_ID)
		if bloom_applied ~= 1 and cur_cast_wpn and orig_fire_disp ~= -1 then
			cur_cast_wpn:SetFireDispersion(orig_fire_disp)
			bloom_applied = 1
		end
	end
end
---NOTE: switching wepaon will force restore ori, no worry..
local function restore_vanilla_fire_disp()
	if not cur_cast_wpn or orig_fire_disp <= 0 then
		return
	end
	cur_cast_wpn:SetFireDispersion(orig_fire_disp)
	bloom_applied = -1
	bloom_heat = 0
end
--drives the live bullet cone, base hip penalty plus decaying heat
---@type fuzz_on_init_wpn
function bloom_init(_, cast_wpn, _)
	--vanilla cone base in radians, bloom multiplies it at runtime
	orig_fire_disp = cast_wpn and cast_wpn:GetFireDispersion() or 0
	bloom_heat = 0
	bloom_applied = -1
	M.bloom.bc = M.bloom.classes[m_profile.burst_class] or M.bloom.classes.other
end
---@type fuzz_on_before_fire
function bloom_before_fire(ads)
	bloom_update(0, 0, ads)
end
---@type fuzz_on_shot
function bloom_on_shot(_, _, ads)
	bloom_heat = math.min(bloom_heat + M.bloom.bc.rate * (ads and M.bloom.ads_mul or 1), M.bloom.bc.max)
end
---@type fuzz_on_firing
function bloom_update(dt, _, ads)
	if not cur_cast_wpn or orig_fire_disp <= 0 then
		return
	end
	--heat only cools between bursts, sustained fire climbs all the way to the class cap
	local bc = M.bloom.bc
	local mul = 1 + (bc.base * (ads and M.bloom.ads_base or 1) + bloom_heat) * M.bloom.variance
	if math.abs(mul - bloom_applied) > 0.01 then
		cur_cast_wpn:SetFireDispersion(orig_fire_disp * mul)
		bloom_applied = mul
	end
end
---@type fuzz_on_restoring
function bloom_restore(dt)
	bloom_heat = bloom_heat * math.exp(-M.bloom.decay * dt)
end
---@type fuzz_on_stop
function bloom_on_stop()
	bloom_heat = 0
	restore_vanilla_fire_disp()
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
function check_extra_feats() end

--------------------
--#region modifiers
--------------------
---@param modis ModiData[]
---@param target_modi fuzz_recoil_modifier
---@param id_start integer
---@param refresh? boolean
local function add_modis_to(modis, target_modi, id_start, refresh)
	for id, modi in pairs(modis) do
		local result = target_modi:add_modifier(id + id_start - 1, modi, true, true)
		-- logger.dbg("%s:%s", modi.name, result)
	end
	if refresh then
		target_modi:refresh_modi_cache()
	end
end

function add_option_scale_modifiers()
	---@type ModiData[]
	local scale_modi = {
		{ name = "option_scale", param = "cam_recoil_power", type = 1, val = options.recoil_cam_scale },
		{ name = "option_scale", param = "force_yaw", type = 1, val = options.recoil_h_scale },
		{ name = "option_scale", param = "handling_speed", type = 1, val = options.handling_speed_scale },
		-- { name = "", param = "force_x", type = 1, val = options.recoil_h_scale },
	}
	add_modis_to(scale_modi, M.static_modifiers, 1, true)
end
function add_actor_stat_modifiers()
	---@type ModiData[]
	local stat_modi = {
		{ name = "actor_stat", param = "cam_recoil_power", type = 1, val = actor_recoil_modi_val },
		{ name = "actor_stat", param = "force_pitch", type = 1, val = actor_recoil_modi_val },
		{ name = "actor_stat", param = "force_yaw", type = 1, val = actor_recoil_modi_val },
		-- { name = "", param = "force_y", type = 1, val = actor_recoil_modi_val },
		-- { name = "", param = "force_x", type = 1, val = actor_recoil_modi_val },
		-- { name = "", param = "handling_speed", type = 1, val = -actor_recoil_modi_val },
	}
	add_modis_to(stat_modi, M.dynamic_modifiers, 1, true)
end

local upgrade_modi = {
	{ name = "upgrade", param = "cam_recoil_power", type = 2 },
	{ name = "upgrade", param = "force_pitch", type = 2 },
	{ name = "upgrade", param = "force_yaw", type = 2 },
	{ name = "upgrade", param = "pull_force", type = 2 },
	{ name = "upgrade", param = "handling_speed", type = 2 },
}
UPGRADES_MODI_ID_START = 10
UPGRADES_MODI_ID_END = #upgrade_modi + UPGRADES_MODI_ID_START - 1
function add_upgrades_modifiers(vert, hori, handle)
	logger.dbg("aplly v:%.4f,hori:%.4f,handle:%.4f", vert, hori, handle)
	local val_list = { vert, vert, hori, 2 - handle, 2 - handle }
	for i, modi in ipairs(upgrade_modi) do
		modi.val = val_list[i]
	end
	add_modis_to(upgrade_modi, M.static_modifiers, UPGRADES_MODI_ID_START, true)
end

function remove_upgrade_modifiers()
	for id = UPGRADES_MODI_ID_START, UPGRADES_MODI_ID_END do
		M.static_modifiers:remove_modifier(id)
	end
	M.static_modifiers:refresh_modi_cache()
end

--NOTE:update when swithcing wepaon
M.static_modifiers = fuzz_recoil_modifier.new()
--NOTE:update before fire
M.dynamic_modifiers = fuzz_recoil_modifier.new()

local m_modifiers = {
	M.static_modifiers,
	M.dynamic_modifiers,
}

---@alias WhichModifier
---| 1 # static
---| 2 # dynamic
---
---@param modis ModiData[]
---@param which_modifier WhichModifier
---@param id_start integer
---@param refresh? boolean
function M.AddModifiers(modis, which_modifier, id_start, refresh)
	add_modis_to(modis, m_modifiers[which_modifier], id_start, refresh)
end
--NOTE: only static_modifiers need refresh mannualy.
function M.ReloadStaticModifiers()
	M.static_modifiers:refresh_modi_cache()
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
------------
---Sub Event
------------
M.on_restoring.on_empty = stop_recoil

M.on_init_wpn:add(HP_EVENT_ID, handling_init)
M.on_firing:add(HP_EVENT_ID, handling_update_firing)

M.on_init_wpn:add(SHOT_DELAY_EVENT_ID, shot_delay_init)
--------------------------------------
---Debug
--------------------------------------
M.debug_var = {
	bool0 = false,
	bool1 = true,
	float_s1 = 0.8,
	float_s2 = 0.03,
	float_x1 = 0,
	float_x2 = 0,
}
function M.log_cached_weapons()
	logger.print_table(cached_weapons, "cached weapons")
end
