logger = {}
local log_text = "FuzzRecoilLog"
enable_internal_log = false
function on_game_start()
	enable_internal_log = fuzz_recoil_imgui and true or false
end
function m_log(msg, ...)
	if msg == nil then
		log("[FuzzRecoil]: nil msg")
		log(debug.traceback())
		return
	end
	--NOTE: engine log() is LuaLog1(LPCSTR),a single string with no vararg formatting
	--(script_engine_script.cpp),so formatting in lua then passing one string is correct
	msg = string.format(msg, ...)
	log("[FuzzRecoil]:" .. msg)
	if enable_internal_log then
		log_text = log_text .. "\n" .. string.format("[%s]", time_global()) .. msg
	end
end
function logger.dbg(msg, ...)
	if not fuzz_recoil.settings.debug_mode then
		return
	end
	m_log(msg, ...)
end
function logger.err(msg, ...)
	m_log("[ERROR]" .. msg, ...)
	m_log(debug.traceback())
end
function logger.get_log_text()
	return log_text
end
function logger.clear_internal_log()
	log_text = ""
end
