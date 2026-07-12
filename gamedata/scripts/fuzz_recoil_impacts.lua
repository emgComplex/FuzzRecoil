--in game impact markers, mirrors the sim viewer wall dots
--positions come from the modded exes bullet impact functor, the exact engine hit point
local logger = fuzz_recoil_logger

local M = {}
_G.fuzz_recoil_impacts = M

--toggled from the FuzzRecoil imgui window
M.enabled = false
M.ghosts = true
--seconds a fresh mark stays hot before it turns into a ghost
M.fade_time = 5.0
M.max_ghosts = 150
M.mark_size = 8

local marks = {}
local ghosts = {}
--rolling window for the live spread readout, survives the hot to ghost handoff
local recent = {}
local RECENT_CAP = 30

--r, g, b like the sim viewer, hot bullet yellow and dark blue ghost
local HOT = { r = 255, g = 226, b = 74 }
local GHOST = { r = 68, g = 68, b = 160 }

--imgui packs colors as 0xAABBGGRR
local function pack(c, a)
	return math.floor(a * 255) * 16777216 + c.b * 65536 + c.g * 256 + c.r
end

function M.clear()
	marks = {}
	ghosts = {}
	recent = {}
end

function M.on_impact(t)
	if not M.enabled then
		return
	end
	--only the players own bullets
	if not db.actor or t.parent_id ~= db.actor:id() then
		return
	end
	marks[#marks + 1] = { pos = vector():set(t.position), t = time_global() }
	recent[#recent + 1] = marks[#marks].pos
	if #recent > RECENT_CAP then
		table.remove(recent, 1)
	end
end

--live spread of the recent impacts, rms radius around the centroid
--meters plus the angle it subtends from the player, wall test friendly
local function spread_stats()
	local n = #recent
	if n < 3 then
		return nil
	end
	local c = vector():set(0, 0, 0)
	for _, p in ipairs(recent) do
		c:add(p)
	end
	c:mul(1 / n)
	local sum = 0
	for _, p in ipairs(recent) do
		local d = vector():set(p):sub(c)
		sum = sum + d:magnitude() * d:magnitude()
	end
	local rms = math.sqrt(sum / n)
	local dist = db.actor and db.actor:position():distance_to(c) or 0
	local ang = dist > 0.1 and math.deg(math.atan(rms / dist)) or 0
	return n, rms, dist, ang
end

local function draw_mark(pos, color, size, id, sx, sy)
	local ui = game.world2ui(pos, false, false)
	if ui.x == -9999 then
		return
	end
	ImGui.SetNextWindowPos(vector2():set(ui.x * sx - size / 2, ui.y * sy - size / 2))
	ImGui.SetNextWindowSize(vector2():set(size, size))
	ImGui.PushStyleVar(ImGuiStyleVar.WindowRounding, size / 2)
	ImGui.PushStyleColor(ImGuiCol.WindowBg, color)
	--NoBackground off, the colored background IS the marker
	local expanded, _ = ImGui.Begin(id, true, ImGuiWindowFlags.NoDecoration + ImGuiWindowFlags.NoInputs)
	ImGui.End()
	ImGui.PopStyleColor()
	ImGui.PopStyleVar()
end

function M.draw()
	if not M.enabled or (#marks == 0 and #ghosts == 0) then
		return
	end
	local now = time_global()
	local dev = device()
	local sx = dev.width / 1024
	local sy = dev.height / 768
	--expire hot marks into ghosts
	local keep = {}
	for _, m in ipairs(marks) do
		if (now - m.t) / 1000 >= M.fade_time then
			if M.ghosts then
				ghosts[#ghosts + 1] = m
				if #ghosts > M.max_ghosts then
					table.remove(ghosts, 1)
				end
			end
		else
			keep[#keep + 1] = m
		end
	end
	marks = keep
	for i, m in ipairs(ghosts) do
		draw_mark(m.pos, pack(GHOST, 0.55), M.mark_size * 0.75, "##fzg" .. i, sx, sy)
	end
	for i, m in ipairs(marks) do
		--hot fades toward the ghost handoff, never fully invisible
		local a = 1 - ((now - m.t) / 1000 / M.fade_time) * 0.6
		draw_mark(m.pos, pack(HOT, a), M.mark_size, "##fzm" .. i, sx, sy)
	end
end

--overlays draw in imgui_on_render like the rest of the mod windows
ImGui.Groups.Unique.Widget(function()
	M.draw()
end)

function M.on_game_start()
	--single global functor, chain whatever another mod installed
	local prev = _G.CBulletOnImpact
	_G.CBulletOnImpact = function(t)
		if prev then
			prev(t)
		end
		M.on_impact(t)
	end
	RegisterScriptCallback("actor_on_first_update", M.clear)
end

function M.imgui_settings_drawer()
	_, M.enabled = ImGui.Checkbox("Impact Markers", M.enabled)
	_, M.ghosts = ImGui.Checkbox("Impact Ghosts", M.ghosts)
	local n, rms, dist, ang = spread_stats()
	if n then
		ImGui.Text(string.format("Spread last %d: rms %.1fcm @ %.1fm (%.2fdeg)", n, rms * 100, dist, ang))
		local bh = fuzz_recoil.get_bloom_state()
		ImGui.Text(string.format("Bloom heat now: %.2f", bh))
	else
		ImGui.Text("Spread: need 3+ marked impacts")
	end
	_, M.fade_time = ImGui.SliderFloat("Mark Fade Time", M.fade_time, 1.0, 15.0, "%.1fs")
	_, M.max_ghosts = ImGui.SliderFloat("Max Ghosts", M.max_ghosts, 20, 500, "%.0f")
	_, M.mark_size = ImGui.SliderFloat("Mark Size", M.mark_size, 3, 20, "%.0f")
	if ImGui.Button("Clear Marks", vector2():set(-1, 25)) then
		M.clear()
	end
end
