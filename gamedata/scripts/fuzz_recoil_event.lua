local logger = fuzz_recoil_logger
---@class FuzzEvent
---@field label string
---@field handlers function[]
---@field count integer
---@field on_empty function|nil
local M = {}
_G.fuzz_recoil_event = M
M.__index = M

--TODO:or read from modules?
local event_id_list = {
	[5] = "shot_delay",
	[11] = "bloom",
	[25] = "handling_power",
	[35] = "cam_recoil",
	[45] = "hud_recoil",
	[55] = "cam_punch",
}
local unknown_id = 100
function M.getEventID(event_name)
	for id, n in pairs(event_id_list) do
		if n == event_name then
			return id
		end
	end
	unknown_id = unknown_id + 1
	logger.err("Can't get Event id  fallback to %s", unknown_id)
	return unknown_id
end
---@type FuzzEvent[]
local m_events = {}
local m_events_count = 0

function M.print_all_events()
	for _, e in ipairs(m_events) do
		e:print_handlers()
	end
end
function M.get_all_evetns_info()
	local result = "Events:\n"
	for _, e in ipairs(m_events) do
		result = e:get_handlers_info() .. "\n"
	end
	return result
end

--@generic T:function
--@return FuzzEvent<T>:FuzzEvent
function M.new(label)
	local ins = {
		label = label or "Unknown",
		handlers = {},
		count = 0,
		on_empty = nil,
	}
	m_events_count = m_events_count + 1
	m_events[m_events_count] = ins
	return setmetatable(ins, M)
end

function M:set_empty_callback(callback)
	self.on_empty = callback
end

--NOTE:this won't work
--@generic T
--@param self FuzzEvent<T>
--@param id integer
--@param handler T
function M:add(id, handler)
	if not id or not handler then
		return
	end
	-- if self.handlers[id] then
	-- 	return
	-- end

	self.handlers[id] = handler
	self.count = self.count + 1
end

function M:remove(id, silent)
	if not self.handlers[id] then
		return
	end

	self.handlers[id] = nil
	self.count = self.count - 1

	if self.count == 0 and self.on_empty and not silent then
		self.on_empty()
	end
end
function M:remove_all(silent)
	self.handlers = {}
	self.count = 0
	if self.on_empty and not silent then
		self.on_empty()
	end
end

function M:invoke(...)
	-- logger.dbg("Event(%s) %s", self.label, self)
	for id, handler in pairs(self.handlers) do
		handler(...)
	end
end

function M:__tostring()
	local result = "Subscribers:"
	for id, _ in pairs(self.handlers) do
		local name = event_id_list[id] or "Unknown"
		result = result .. name .. ","
	end
	return result
end
function M:get_handlers_info()
	result = self.label .. ":/n"
	for _, h in pairs(self.handlers) do
		result = result .. logger.get_func_info(h) .. "\n"
	end
end

function M:print_handlers()
	logger.dbg(M:get_handlers_info())
	-- logger.dbg(self.label)
	-- for _, h in pairs(self.handlers) do
	-- 	logger.print_func_info(h)
	-- end
end
