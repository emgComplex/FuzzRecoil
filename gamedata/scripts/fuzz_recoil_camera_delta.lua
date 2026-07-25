local M = {}
_G.fuzz_recoil_camera_delta = M

local queue_delta = level.queue_actor_camera_delta
local poll_delta = level.poll_actor_camera_delta
local cancel_delta = level.cancel_actor_camera_delta

local STATUS_PENDING = 1
local STATUS_APPLIED = 2
local EPSILON = 0.000001
local MAX_PENDING = 16

local available = type(queue_delta) == "function"
	and type(poll_delta) == "function"
	and type(cancel_delta) == "function"

local requests = {}
local applied_pitch = 0
local submitted_pitch = 0

function M.available()
	return available
end

function M.epsilon()
	return EPSILON
end

function M.pending_count()
	return #requests
end

function M.applied_pitch()
	return applied_pitch
end

function M.submitted_pitch()
	return submitted_pitch
end

function M.poll()
	if not available then
		return 0
	end

	local missed_pitch = 0
	for i = #requests, 1, -1 do
		local request = requests[i]
		local status, _, pitch = poll_delta(request.id)
		if status ~= STATUS_PENDING then
			local applied = 0
			if status == STATUS_APPLIED then
				applied = -pitch
				applied_pitch = applied_pitch + applied
				submitted_pitch = submitted_pitch + applied - request.pitch
			else
				submitted_pitch = submitted_pitch - request.pitch
			end

			missed_pitch = missed_pitch + request.pitch - applied
			table.remove(requests, i)
		end
	end

	return missed_pitch
end

function M.submit(target_pitch)
	if not available then
		return false
	end

	local delta = target_pitch - submitted_pitch
	if math.abs(delta) <= EPSILON then
		return true
	end
	if #requests >= MAX_PENDING then
		return false
	end

	-- CameraFirstEye pitch is inverted relative to visible camera pitch.
	local request_id = queue_delta(0, -delta)
	if request_id == 0 then
		return false
	end

	requests[#requests + 1] = {
		id = request_id,
		pitch = delta,
	}
	submitted_pitch = target_pitch
	return true
end

function M.adopt(pitch)
	applied_pitch = pitch
	submitted_pitch = pitch
end

function M.cancel_and_reset()
	if available then
		for i = #requests, 1, -1 do
			local request_id = requests[i].id
			cancel_delta(request_id)
			poll_delta(request_id)
			requests[i] = nil
		end
	end

	applied_pitch = 0
	submitted_pitch = 0
end

return M
