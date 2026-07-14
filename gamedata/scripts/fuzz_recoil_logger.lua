local M = {}
_G.fuzz_recoil_logger = M

local log_text = "FuzzRecoilLog"
local enable_internal_log = false
local debug_enabled = fuzz_dev and true or false

function M.on_game_start()
	enable_internal_log = fuzz_recoil_imgui and true or false
end
function M.on_option_change()
	debug_enabled = fuzz_recoil_mcm.debug_mode
end
local function m_log(msg, ...)
	if msg == nil then
		log("[FuzzRecoil]: nil msg")
		log(debug.traceback())
		return
	end
	--NOTE: engine log() is LuaLog1(LPCSTR), a single string with no vararg formatting
	--(script_engine_script.cpp), so formatting in lua then passing one string is correct
	msg = string.format(msg, ...)
	log("[FuzzRecoil]:" .. msg)
	if enable_internal_log then
		log_text = log_text .. "\n" .. string.format("[%s]", time_global()) .. msg
	end
end
function M.dbg(msg, ...)
	if not debug_enabled then
		return
	end
	m_log(msg, ...)
end
function M.err(msg, ...)
	m_log("[ERROR]" .. msg, ...)
	m_log(debug.traceback())
end
function M.get_log_text()
	return log_text
end
function M.clear_internal_log()
	log_text = ""
end
function M.export_internal_log()
	local filename = string.format("../appdata/logs/fuzz_recoil_%s.log", os.time())
	local file = io.open(filename, "w")
	if not file then
		M.err("Failed to open file when exporting logs")
	end
	file:write(log_text)
	file:close()
end
local temp_text
local function new_line(msg, ...)
	new_text = string.format(msg, ...)
	temp_text = temp_text .. "\n" .. new_text
end
function M.format_table(t, indent, keep)
	if not keep then
		temp_text = ""
	end
	if not indent then
		indent = "  "
	end
	new_line("%s{", indent)
	for k, v in pairs(t) do
		if type(v) == "table" then
			new_line("%s%s=", indent, k)
			M.format_table(v, indent .. indent, true)
		else
			new_line("%s%s=%s,", indent, k, v)
		end
	end
	new_line("%s},", indent)
	return temp_text
end
function M.print_table(t)
	M.format_table(t)
	m_log(temp_text)
end
