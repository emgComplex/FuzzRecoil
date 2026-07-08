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
	--FIXME: figure out why printf doesn't format
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
