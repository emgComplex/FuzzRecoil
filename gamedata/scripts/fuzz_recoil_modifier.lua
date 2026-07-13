local logger = fuzz_recoil_logger
local M = {}
_G.fuzz_recoil_modifier = M
---------------
---modifier
---------------
--TODO: UNIT TEST for modifier
---NOTE: weapons shares modifier so we make it local
local m_modifiers = {}
local cached_modifiers = {
	basic = {},
	funcs = {},
}
---@alias ModiType
---| 0 # add
---| 1 # scale
---| 2 # mul
---| 3 # func
---@alias AddModiResult
---| 0 # succeed
---| 1 # replaced
---| 2 # exsisted
---| 3 # failed

---@class ModiData
---@field name string the name or description for your modifier
---@field param string the parameter you want change
---@field type ModiType final_v = (v +adds)*(1+scales)*muls,then apply functions
---@field val number
---@field func? fun(profile:any):any

---@param modi_data ModiData
local function validate_modi(id, modi_data)
	--TODO: assert
	if not modi_data.type then
		logger.err("can't find param %s for modifier %s", modi_data.param, id)
		return false
	end
	if modi_data.type == 3 then
		if not modi_data.func then
			logger.err("no func for modifier %s", id)
			return false
		end
		if not type(modi_data) == "function" then
			logger.err("modifier %s is not a function", id)
			return false
		end
		return true
	end
	if not modi_data.param or not modi_data.val then
		logger.err("no param or val for modifier %s", id)
		return false
	end
	if fuzz_recoil_profile[modi_data.param] == nil then
		logger.err("can't find param %s for modifier %s", modi_data.param, id)
		return false
	end
	return true
end

---@param modi_data ModiData
---@return AddModiResult result
local function m_add_modi(id, modi_data, force_replace)
	if m_modifiers[id] then
		if not id or not modi_data then
			logger.err("can't find id or modi_data")
			return 3
		end
		if not validate_modi(id, modi_data) then
			return 3
		end

		if force_replace then
			m_modifiers[id] = modi_data
			return 1
		else
			return 2
		end
	end
	m_modifiers[id] = modi_data
	return 0
end

---@param m ModiData
local function cache_basic_modi(t, m)
	if not t[m.param] then
		t[m.param] = { add = 0, scale = 1, mul = 1 }
	end
	if m.type == 0 then
		t[m.param].add = t[m.param].add + m.val
	elseif m.type == 1 then
		t[m.param].scale = t[m.param].scale + m.val
	elseif m.type == 2 then
		t[m.param].mul = t[m.param].mul + m.val
	end
end
function M.refresh_modi_cache()
	--clear the cache
	cached_modifiers = {
		basic = {},
		funcs = {},
	}
	for id, mod in ipairs(m_modifiers) do
		if mod.type < 3 then
			cache_basic_modi(cached_modifiers.basic, mod)
		else
			cached_modifiers.funcs[id] = mod.func
		end
	end
	logger.print_table(cached_modifiers)
end

---------------
---Internal functions
---------------

---@param profile fuzz_recoil_profile
---Internal calls for fuzz_recoil,don't use
function M.apply_modifiers(profile)
	if not profile then
		logger.err("can't find profile when applying modifiers")
	end
	local raw_prf = profile.raw_profile
	--NOTE: no nil check since we validate them
	for k, v in pairs(cached_modifiers.basic) do
		profile[k] = (raw_prf[k] + v.add) * v.scale * v.mul
	end
	for _, func in pairs(cached_modifiers.funcs) do
		func(profile)
	end
end

---------------
---Public functions
---------------
---@param id integer 0-100 and 500-600 is resevered for fuzz_recoil
---@param force_replace? boolean force replace if the mod exsits
---@param no_refresh? boolean enable this if you are adding multiple modifiers,then refresh cache manully
---@param modi_data ModiData
---@return AddModiResult result
---!!!DO NOT CALL THIS FREQUENTLY!!!
function M.add_modifier(id, modi_data, force_replace, no_refresh)
	result = m_add_modi(id, modi_data, force_replace)
	if not no_refresh and result < 2 then
		M.refresh_modi_cache()
	end
	return result
end

---@param id integer 0-100 and 500-600 is resevered for fuzz_recoil
---@return boolean
---|true found and removed
---|false not found
function M.remove_modifier(id)
	if m_modifiers[id] then
		m_modifiers[id] = nil
		--TODO: brute refresh,not that good
		M.refresh_modi_cache()
		return true
	end
	return false
end

---@param id integer 0-100 and 500-600 is resevered for fuzz_recoil
---nil if not exsits
function M.get_modifier(id)
	return m_modifiers[id]
end
