local logger = fuzz_recoil_logger
---@class fuzz_recoil_modifier
local M = {}
M.__index = M
_G.fuzz_recoil_modifier = M
local enabled = true
---------------
---modifier
---------------
--TODO: UNIT TEST for modifier
---NOTE: weapons shares modifier so we make it local
---@type ModiData[]
M.m_modifiers = {}
M.cached_modifiers = {
	simple = {},
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
function M:_add_modi(id, modi_data, force_replace)
	if self.m_modifiers[id] then
		if not id or not modi_data then
			logger.err("can't find id or modi_data")
			return 3
		end
		if not validate_modi(id, modi_data) then
			return 3
		end

		if force_replace then
			self.m_modifiers[id] = modi_data
			return 1
		else
			return 2
		end
	end
	self.m_modifiers[id] = modi_data
	return 0
end

---@param m ModiData
local function cache_simple_modi(t, m)
	-- logger.print_table(m, "modi table")
	if not t[m.param] then
		t[m.param] = { add = 0, scale = 1, mul = 1 }
	end
	if m.type == 0 then
		t[m.param].add = t[m.param].add + m.val
	elseif m.type == 1 then
		t[m.param].scale = t[m.param].scale + m.val
	elseif m.type == 2 then
		t[m.param].mul = t[m.param].mul * m.val
	end
end
function M:refresh_modi_cache()
	--clear the cache
	self.cached_modifiers = {
		simple = {},
		funcs = {},
	}
	for id, mod in pairs(self.m_modifiers) do
		if mod.type < 3 then
			cache_simple_modi(self.cached_modifiers.simple, mod)
		else
			self.cached_modifiers.funcs[id] = mod.func
		end
	end
end

---------------
---Internal methods
---------------
---@return fuzz_recoil_modifier
function M:new()
	local ins = {}
	setmetatable(ins, M)
	ins.m_modifiers = {}
	ins.cached_modifiers = {
		simple = {},
		funcs = {},
	}
	return ins
end

---@param target fuzz_recoil_profile
---Internal calls for fuzz_recoil,don't use
function M:apply_modifiers(source, target, extra_target)
	if not enabled then
		return
	end
	--NOTE: we can use ... isntead of extra_target
	if not target then
		logger.err("can't find profile when applying modifiers")
	end
	--NOTE: no nil check since we validate them
	for k, v in pairs(self.cached_modifiers.simple) do
		-- logger.dbg("applying modifier-%s:%.6f,%.6f,%.6f", k, v.add, v.scale, v.mul)
		target[k] = (source[k] + v.add) * v.scale * v.mul
		if extra_target then
			extra_target[k] = target[k]
		end
	end
	for _, func in pairs(self.cached_modifiers.funcs) do
		func(target)
	end
end

---@param flag boolean
---set modifier enabled state
function M.enabled(flag)
	enabled = flag
end

function M.is_enabled()
	return enabled
end

function M:__tostring()
	local temp = {
		m_modifiers = self.m_modifiers,
		cached_modifiers = self.cached_modifiers,
	}
	return logger.format_table(temp)
	-- return logger.format_table(self)
	-- 	.. "\n m_modifiers = \n"
	-- 	.. (self.m_modifiers and logger.format_table(self.m_modifiers) or "no modi")
end

---------------
---Public methods
---------------
---@param id integer 0-100 and 500-600 is resevered for fuzz_recoil
---@param force_replace? boolean force replace if the mod exsits
---@param no_refresh? boolean enable this if you are adding multiple modifiers,then refresh cache manully
---@param modi_data ModiData
---@return AddModiResult result
---!!!DO NOT CALL THIS FREQUENTLY!!!
function M:add_modifier(id, modi_data, force_replace, no_refresh)
	result = self:_add_modi(id, modi_data, force_replace)
	if not no_refresh and result < 2 then
		self:refresh_modi_cache()
	end
	return result
end

---@param id integer 0-100 and 500-600 is resevered for fuzz_recoil
---@return boolean
---|true found and removed
---|false not found
function M:remove_modifier(id)
	if self.m_modifiers[id] then
		self.m_modifiers[id] = nil
		--TODO: brute refresh,not that good
		self:refresh_modi_cache()
		return true
	end
	return false
end

---@param id integer 0-100 and 500-600 is resevered for fuzz_recoil
---nil if not exsits
function M:get_modifier(id)
	return self.m_modifiers[id]
end
