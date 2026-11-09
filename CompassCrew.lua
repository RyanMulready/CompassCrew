-- Compass Crew: group members on the Wayfinder compass (through Wayfinder.API), and on the
-- minimap and world map (Maps.lua). Positions come from UnitPosition, which the game hides
-- for other players inside dungeons and raids, so members disappear there and return outside.
--
-- Performance: per frame, only real group members are touched, with your own position and
-- facing read once. Icon details (marker, class, dead, online) are read on events and a slow
-- timer, never per frame, and frames re-apply them only when they changed.

local ADDON_NAME, ns = ...

local function msg(text) print("|cff66ccffCompass Crew:|r " .. text) end
ns.msg = msg

local api = Wayfinder and Wayfinder.API
local hbd = LibStub and LibStub("HereBeDragons-2.0", true)
if not (api and api.AddElementToBanner and hbd) then
	msg("Wayfinder (and the HereBeDragons library it includes) wasn't found.")
	return
end
ns.hbd = hbd

local abs, floor, min, max, exp, deg = math.abs, math.floor, math.min, math.max, math.exp, math.deg
local GetTime, GetPlayerFacing = GetTime, GetPlayerFacing
local issecret = issecretvalue or function() return false end
local function safe(v) if not issecret(v) then return v end end
ns.safe = safe

ns.STYLE_CLASS, ns.STYLE_AUTO, ns.STYLE_MARKER, ns.STYLE_PORTRAIT = "class", "auto", "marker", "portrait"
ns.DEFAULTS = {
	style = ns.STYLE_CLASS,
	size = 25,             -- compass icon size; Wayfinder's banner is 25px tall
	sticky = true,         -- pin members behind you to the compass edges
	raid = false,          -- show raid members, not just party
	distanceScale = false, -- shrink icons for members farther away
	showDistance = false,  -- distance/ETA under icons (each line also needs Wayfinder's own setting)
	dimDead = true,
	stack = true,          -- combine members whose compass icons would overlap
	hideNear = true,       -- hide members right next to you
	showAway = true,       -- row of icons under the compass for members elsewhere
	minimap = true,
	worldmap = true,
	mapSize = 25,
}
ns.NEAR, ns.FAR, ns.MIN_SCALE = 25, 250, 0.5 -- distance scaling: full size to NEAR yds, half at FAR
ns.MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
ns.CLASS_TEXTURE = "Interface\\TargetingFrame\\UI-Classes-Circles"
ns.PORTRAIT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Wayfinder's banner geometry (CompassBanner.lua; not exposed, so mirrored here)
local HALF_WIDTH, HALF_FOV = 300, 67.5

local db

---------------------------------------------------------------------------
-- Members and their icons
---------------------------------------------------------------------------
-- One table per unit token, kept for the session (`byUnit`); `members` lists those in the
-- group right now and is rebuilt on roster changes.

local byUnit, members = {}, {}
ns.byUnit, ns.members = byUnit, members

-- Read what a member's icon should be. `m.version` goes up when anything changed, which is
-- how every frame showing this member knows to redraw.
local function refreshMember(m)
	local unit, style = m.unit, db.style
	local kind, marker, class, secret
	if safe(UnitIsConnected(unit)) ~= false then
		if style == ns.STYLE_AUTO or style == ns.STYLE_MARKER then
			-- A marker can be "secret": unreadable, but a texture can still show it.
			marker = GetRaidTargetIndex(unit)
			secret = issecret(marker)
			if secret or marker ~= nil then kind = "marker" end
		end
		if not kind and style == ns.STYLE_PORTRAIT then
			kind = "portrait"
		elseif not kind and style ~= ns.STYLE_MARKER then
			class = safe(select(2, UnitClass(unit)))
			if class and CLASS_ICON_TCOORDS[class] then kind = "class" end
		end
	end
	local dead = db.dimDead and safe(UnitIsDeadOrGhost(unit)) == true
	local guid = safe(UnitGUID(unit))
	-- Secret markers can't be compared, so they always count as changed.
	if secret or m.secret or kind ~= m.kind or marker ~= m.marker or class ~= m.class or dead ~= m.dead or guid ~= m.guid then
		m.kind, m.marker, m.secret, m.class, m.dead, m.guid = kind, marker, secret, class, dead, guid
		m.version = (m.version or 0) + 1
	end
end

local function refreshAll()
	for _, m in ipairs(members) do refreshMember(m) end
end

-- An icon frame (texture + the round mask portraits use), shared by compass and maps.
function ns.CreateIconFrame(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	holder:Hide()
	local tex = holder:CreateTexture(nil, "OVERLAY")
	tex:SetAllPoints()
	local mask = holder:CreateMaskTexture()
	mask:SetTexture(ns.PORTRAIT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:SetAllPoints(tex)
	return { holder = holder, tex = tex, mask = mask }
end

-- Draw member `m` on icon frame `p`, only if it changed since that frame last drew it.
function ns.ApplyIcon(p, m)
	if p.version == m.version then return end
	p.version = m.version
	local tex, kind = p.tex, m.kind
	local portrait = kind == "portrait"
	if portrait ~= (p.masked or false) then
		if portrait then tex:AddMaskTexture(p.mask) else tex:RemoveMaskTexture(p.mask) end
		p.masked = portrait
	end
	if kind == "marker" then
		tex:SetTexture(ns.MARKER_TEXTURE)
		SetRaidTargetIconTexture(tex, m.marker)
	elseif kind == "class" then
		local c = CLASS_ICON_TCOORDS[m.class]
		tex:SetTexture(ns.CLASS_TEXTURE)
		tex:SetTexCoord(c[1], c[2], c[3], c[4])
	elseif portrait then
		tex:SetTexCoord(0, 1, 0, 1)
		SetPortraitTexture(tex, m.unit)
	end
	tex:SetDesaturated(m.dead)
	tex:SetAlpha(m.dead and 0.6 or 1)
end

---------------------------------------------------------------------------
-- Steadying positions
---------------------------------------------------------------------------
-- Other players' positions arrive in small jumps while yours moves every frame, so the
-- direction to someone beside you jittered. Each member's speed is estimated from recent
-- updates, the position is projected forward between them, and the result eased.

local POS_EASE = 0.15       -- seconds for the shown position to catch up
local SPEED_WINDOW = 0.15   -- seconds between samples used to estimate speed
local MAX_PREDICT = 0.5     -- seconds; never project further
local MAX_SPEED = 20        -- yds/s; faster is a teleport or glitch
local TELEPORT = 40         -- yds; bigger jumps snap

local function track(m, x, y, now)
	if not m.rawX or abs(x - m.rawX) + abs(y - m.rawY) > TELEPORT then
		m.rawX, m.rawY, m.rawT, m.refX, m.refY, m.refT = x, y, now, x, y, now
		m.vx, m.vy, m.dispX, m.dispY, m.dispT, m.gap = 0, 0, x, y, now, 0.2
		return x, y
	end
	if x ~= m.rawX or y ~= m.rawY then -- a new update arrived
		local gap = now - m.rawT
		if gap < 1 then m.gap = m.gap * 0.8 + gap * 0.2 end
		m.rawX, m.rawY, m.rawT = x, y, now
		local window = now - m.refT
		if window >= SPEED_WINDOW then
			local vx, vy = (x - m.refX) / window, (y - m.refY) / window
			if vx * vx + vy * vy > MAX_SPEED * MAX_SPEED then vx, vy = 0, 0 end
			m.vx, m.vy = (m.vx + vx) / 2, (m.vy + vy) / 2
			m.refX, m.refY, m.refT = x, y, now
		end
	end
	-- No update for a bit longer than usual: they stopped. Otherwise project ahead, plus
	-- POS_EASE to cancel the lag the easing adds.
	local since, tx, ty = now - m.rawT, m.rawX, m.rawY
	if since > min(MAX_PREDICT, max(0.1, m.gap * 1.3)) then
		m.vx, m.vy = 0, 0
	else
		tx, ty = tx + m.vx * (since + POS_EASE), ty + m.vy * (since + POS_EASE)
	end
	local a = 1 - exp(-(now - m.dispT) / POS_EASE)
	m.dispX, m.dispY, m.dispT = m.dispX + (tx - m.dispX) * a, m.dispY + (ty - m.dispY) * a, now
	return m.dispX, m.dispY
end

---------------------------------------------------------------------------
-- Readout (distance and ETA), styled and formatted like Wayfinder's own
---------------------------------------------------------------------------

-- Whether Wayfinder shows this line for its own target. Clients without its tracking have
-- no such setting: distance yes, ETA no.
local function wayfinderShows(kind)
	local st = api.SuperTracking
	if st and st.IsSupported and st.IsSupported() then
		return st["GetShow" .. kind]() and true or false
	end
	return kind == "Distance"
end
ns.WayfinderShows = wayfinderShows

-- ETA = distance / closing speed (smoothed). Like Wayfinder's, it counts down by itself and
-- only jumps when a new estimate disagrees by more than 1.5s or 4%; nil when not closing in.
local function etaSeconds(m, dist, now)
	if m.etaD and now > m.etaT then
		local dt = now - m.etaT
		local speed = (m.etaD - dist) / dt
		m.closing = m.closing and (m.closing + (speed - m.closing) * (1 - exp(-dt / 0.5))) or speed
	end
	m.etaD, m.etaT = dist, now
	if not m.closing or m.closing < 0.5 then m.etaAnchor = nil return end
	local estimate = dist / m.closing
	local counted = m.etaAnchor and m.etaAnchor - (now - m.etaAt)
	if not counted or abs(estimate - counted) > max(1.5, estimate * 0.04) then
		m.etaAnchor, m.etaAt, counted = estimate, now, estimate
	end
	return max(counted, 0)
end

local function updateReadout(m, p, now)
	local dist = m.distance
	local showD = db.showDistance and wayfinderShows("Distance")
	local showE = db.showDistance and wayfinderShows("ETA")

	-- The number only changes once the distance moved a full yard, so it doesn't flicker.
	if showD and (not m.yds or abs(dist - m.yds) >= 1) then
		m.yds = floor(dist + 0.5)
		local text = m.yds < 1000 and tostring(m.yds) or AbbreviateNumbers(m.yds)
		p.dist:SetText(IN_GAME_NAVIGATION_RANGE and IN_GAME_NAVIGATION_RANGE:format(text) or text .. " yds")
	end
	p.dist:SetShown(showD)

	if showE then
		local eta = etaSeconds(m, dist, now)
		local secs = eta and floor(eta + 0.5) or -1
		if secs ~= m.etaSecs then
			m.etaSecs = secs
			p.eta:SetText(secs < 0 and "--" or secs < 60 and secs .. "s" or floor(secs / 60) .. "m " .. secs % 60 .. "s")
		end
		local anchor = showD and p.dist or p.holder -- right under the icon when distance is off
		if p.etaAnchor ~= anchor then
			p.etaAnchor = anchor
			p.eta:ClearAllPoints()
			p.eta:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
		end
	end
	p.eta:SetShown(showE)
end

function ns.SizeForDistance(dist)
	local size = db.size
	if db.distanceScale and dist then
		local t = max(0, min(1, (dist - ns.NEAR) / (ns.FAR - ns.NEAR)))
		size = size * (1 - t * (1 - ns.MIN_SCALE))
	end
	return floor(size + 0.5)
end

---------------------------------------------------------------------------
-- The per-frame pass: positions, directions and stacking for every member at once
---------------------------------------------------------------------------
-- Angles here are Wayfinder's "relative" angle: facing - bearing, in degrees.

local SIDE_HOLD = 15     -- degrees either side of straight behind
local NEAR_HIDE, NEAR_SHOW = 10, 12 -- yds; hidden closer than 10, back past 12 (no flicker)
local STACK_PADDING = 4  -- px; icons closer than their size plus this stack
local READOUT_WIDTH = 44 -- px; about a "123 yds" line, when the readout is on

local frameTime
local visible = {} -- reused each frame

local function wrap180(a) return (a + 180) % 360 - 180 end

-- Someone just past straight behind you stays on the edge they were on, instead of flipping.
local function holdSide(m, rel)
	local side = rel < 0 and -1 or 1
	if abs(rel) <= 180 - SIDE_HOLD then
		m.lastSide = side
	elseif m.lastSide and side ~= m.lastSide then
		return m.lastSide * 179
	else
		m.lastSide = m.lastSide or side
	end
	return rel
end

-- Where Wayfinder will draw a relative angle: px from the banner center, or nil (hidden).
local function bannerX(rel)
	local ui = -rel
	if abs(ui) < HALF_FOV then return ui / HALF_FOV * HALF_WIDTH end
	if db.sticky then return ui < 0 and -HALF_WIDTH or HALF_WIDTH end
end

local function byX(a, b) return a.x < b.x end

-- Who represents a stack: someone with a target marker first, then the nearest.
local function better(a, b)
	local am, bm = a.kind == "marker", b.kind == "marker"
	if am ~= bm then return am end
	return a.distance < b.distance
end

local function setBearings(facing)
	for _, m in ipairs(visible) do m.bearing = (facing - m.rel) % 360 end
end

local function pass(now)
	frameTime = now
	wipe(visible)
	local facing = GetPlayerFacing() -- Wayfinder only updates while it's readable
	local px, py, inst = hbd:GetPlayerWorldPosition()
	if not (facing and px) or issecret(facing) then return end
	facing = (360 - deg(facing)) % 360

	for _, m in ipairs(members) do
		m.rel, m.count, m.x, m.leader = nil, nil, nil, nil
		local x, y, uinst
		if m.kind then x, y, uinst = hbd:GetUnitWorldPosition(m.unit) end
		if x and uinst == inst then
			x, y = track(m, x, y, now)
			local angle, dist = hbd:GetWorldVector(inst, px, py, x, y)
			if angle then
				m.distance = dist
				m.rel = holdSide(m, wrap180(facing - (360 - deg(angle))))
				m.near = db.hideNear and dist < (m.near and NEAR_SHOW or NEAR_HIDE) or nil
				m.x = not m.near and bannerX(m.rel) or nil
				if m.x then visible[#visible + 1] = m end
			end
		end
		if not m.rel then m.rawX, m.lastSide, m.etaD, m.closing = nil, nil, nil, nil end
	end

	if not db.stack then
		for _, m in ipairs(visible) do m.count = 1 end
		return setBearings(facing)
	end

	-- People together nearly straight behind you can straddle the line onto opposite edges:
	-- put them all on the nearest one's edge, so they stack.
	local nearestBehind
	for _, m in ipairs(visible) do
		if abs(m.rel) > 180 - SIDE_HOLD and (not nearestBehind or m.distance < nearestBehind.distance) then
			nearestBehind = m
		end
	end
	if nearestBehind then
		for _, m in ipairs(visible) do
			if abs(m.rel) > 180 - SIDE_HOLD then m.x, m.rel = nearestBehind.x, nearestBehind.rel end
		end
	end

	-- Left to right, chain icons that would touch into groups; each group shows one icon
	-- (marked members first, then the nearest) at the group's center, with a count.
	table.sort(visible, byX)
	local gap = db.size + STACK_PADDING
	if db.showDistance and (wayfinderShows("Distance") or wayfinderShows("ETA")) then
		gap = max(gap, READOUT_WIDTH)
	end
	ns.stackGap = gap
	local i = 1
	while i <= #visible do
		local leader, sumX, j = visible[i], 0, i
		repeat
			local m = visible[j]
			sumX = sumX + m.x
			if better(m, leader) then leader = m end
			j = j + 1
		until j > #visible or visible[j].x - visible[j - 1].x >= gap
		local n = j - i
		for k = i, j - 1 do visible[k].leader = leader end
		leader.count = n
		if n > 1 and abs(leader.x) < HALF_WIDTH then
			leader.rel = -(sumX / n) / HALF_WIDTH * HALF_FOV -- the group's center
		end
		i = j
	end
	setBearings(facing)
end

---------------------------------------------------------------------------
-- Compass elements
---------------------------------------------------------------------------

-- Called by Wayfinder every frame for each enabled member.
local function angleFor(m)
	local now = GetTime()
	if now ~= frameTime then pass(now) end
	local p = m.compass
	if not m.count or (m.leader and m.leader ~= m) then return nil end

	ns.ApplyIcon(p, m)
	local size = ns.SizeForDistance(m.distance)
	if p.size ~= size then p.size = size; p.holder:SetSize(size, size) end
	updateReadout(m, p, now)
	if p.count ~= m.count then
		p.count = m.count
		p.badgeText:SetText(m.count)
		p.badge:SetShown(m.count > 1)
		p.shadow:SetShown(m.count > 1)
	end
	return m.bearing
end

local function noop() end

local function newMember(unit)
	local m = { unit = unit }
	-- Wayfinder positions and hides the holder; everything else is its child. It also calls
	-- SetRotation on markers, which frames lack: rotation is off for these, so a no-op.
	local function create(banner)
		ns.banner = banner
		local p = ns.CreateIconFrame(banner, db.size)
		local h = p.holder
		h.SetRotation = noop
		p.dist = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall") -- Wayfinder's readout font
		p.dist:SetPoint("TOP", h, "BOTTOM", 0, -2)
		p.eta = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		-- stack look: a dark disc peeking out behind, and a count badge
		p.shadow = h:CreateTexture(nil, "ARTWORK")
		p.shadow:SetTexture(ns.PORTRAIT_MASK)
		p.shadow:SetVertexColor(0, 0, 0, 0.55)
		p.shadow:SetPoint("TOPLEFT", 4, -3)
		p.shadow:SetPoint("BOTTOMRIGHT", 4, -3)
		p.badge = CreateFrame("Frame", nil, h)
		p.badge:SetSize(14, 14)
		p.badge:SetPoint("CENTER", h, "TOPRIGHT", -2, -2)
		p.badge:SetFrameLevel(h:GetFrameLevel() + 2)
		local bg = p.badge:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetTexture(ns.PORTRAIT_MASK)
		bg:SetVertexColor(0.1, 0.1, 0.1, 0.9)
		p.badgeText = p.badge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		p.badgeText:SetPoint("CENTER")
		for _, r in ipairs({ p.dist, p.eta, p.shadow, p.badge }) do r:Hide() end
		m.compass = p
		return h
	end
	m.element = api.AddElementToBanner("CompassCrew_" .. unit, function() return angleFor(m) end, create, db.sticky)
	api.SetElementRotateWhenSticky(m.element, false)
	byUnit[unit] = m
	return m
end

---------------------------------------------------------------------------
-- Members elsewhere
---------------------------------------------------------------------------
-- Members whose position the game doesn't share with you (another continent, or inside a
-- dungeon or raid) get a small faded icon in a row under the compass, with their zone on
-- hover. Skipped while you're in an instance yourself: nobody's position is shared then.
-- Updated on the slow timer, not per frame.

local AWAY_SIZE, AWAY_GAP = 16, 4
local awayRow

local function awayTooltip(holder)
	local m = holder.member
	local c = m.class and RAID_CLASS_COLORS[m.class]
	GameTooltip:SetOwner(holder, "ANCHOR_BOTTOM")
	GameTooltip:SetText(safe(UnitName(m.unit)) or m.unit, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	GameTooltip:AddLine(m.zone or "Somewhere the game doesn't share, like a dungeon or raid", 0.8, 0.8, 0.8, true)
	GameTooltip:Show()
end

local function updateAway()
	if not ns.banner then return end
	if not awayRow then
		awayRow = CreateFrame("Frame", nil, ns.banner)
		awayRow:SetSize(1, AWAY_SIZE)
		awayRow:SetPoint("TOP", ns.banner, "BOTTOM", 0, -4)
	end
	for _, m in pairs(byUnit) do
		if m.away then m.away.holder:Hide() end
	end
	if not db.showAway or IsInInstance() then return end

	local _, _, inst = hbd:GetPlayerWorldPosition()
	local n = 0
	for _, m in ipairs(members) do
		local x, _, uinst
		if m.kind then x, _, uinst = hbd:GetUnitWorldPosition(m.unit) end
		if m.kind and (not x or uinst ~= inst) then
			local mapID = safe(C_Map.GetBestMapForUnit(m.unit))
			local info = mapID and C_Map.GetMapInfo(mapID)
			m.zone = info and info.name
			if not m.away then
				m.away = ns.CreateIconFrame(awayRow, AWAY_SIZE)
				m.away.holder.member = m
				m.away.holder:SetAlpha(0.6)
				m.away.holder:SetMouseMotionEnabled(true) -- hover only; clicks pass through
				m.away.holder:SetScript("OnEnter", awayTooltip)
				m.away.holder:SetScript("OnLeave", GameTooltip_Hide)
			end
			ns.ApplyIcon(m.away, m)
			m.away.holder:ClearAllPoints()
			m.away.holder:SetPoint("LEFT", awayRow, "LEFT", n * (AWAY_SIZE + AWAY_GAP), 0)
			m.away.holder:Show()
			n = n + 1
		end
	end
	awayRow:SetWidth(math.max(1, n * (AWAY_SIZE + AWAY_GAP) - AWAY_GAP))
end

local function slowUpdate()
	refreshAll()
	updateAway()
end

-- Rebuild the member list from the roster. Only these get a Wayfinder element enabled, so
-- Wayfinder skips empty party and raid slots entirely.
local function rebuildMembers()
	wipe(members)
	local raid = IsInRaid()
	if IsInGroup() and (db.raid or not raid) then
		for i = 1, raid and 40 or 4 do
			local unit = (raid and "raid" or "party") .. i
			if UnitExists(unit) and safe(UnitIsUnit(unit, "player")) == false then
				local m = byUnit[unit] or newMember(unit)
				members[#members + 1] = m
				refreshMember(m)
			end
		end
	end
	for _, m in pairs(byUnit) do m.active = false end
	for _, m in ipairs(members) do m.active = true end
	for _, m in pairs(byUnit) do api.SetElementEnabled(m.element, m.active) end
	frameTime = nil
	updateAway()
	if ns.OnMembersChanged then ns.OnMembersChanged() end
end

---------------------------------------------------------------------------
-- Settings access (Options.lua), slash command, events
---------------------------------------------------------------------------

function ns.Get(key) return db[key] end

function ns.Set(key, value)
	db[key] = value
	if key == "raid" then
		rebuildMembers()
	elseif key == "sticky" then
		for _, m in pairs(byUnit) do m.element.isSticky = value end -- Wayfinder keeps it on the handle
	elseif key == "style" or key == "dimDead" then
		refreshAll()
	end
	if key == "showAway" or key == "style" or key == "dimDead" then updateAway() end
	frameTime = nil
	if ns.OnSettingChanged then ns.OnSettingChanged(key) end
end

function ns.ResetToDefaults()
	for k, v in pairs(ns.DEFAULTS) do ns.Set(k, v) end
end

SLASH_COMPASSCREW1, SLASH_COMPASSCREW2 = "/crew", "/compasscrew"
SlashCmdList.COMPASSCREW = function(input)
	if not (input or ""):lower():match("^%s*debug") then
		if ns.OpenOptions then ns.OpenOptions() end
		return
	end
	if #members == 0 then msg("No group members to report on.") end
	for _, m in ipairs(members) do
		local raw = GetRaidTargetIndex(m.unit)
		local markerText = issecret(raw) and "hidden by the game" or raw and ("#" .. raw) or "none"
		local where = not m.rel and ("elsewhere: " .. (m.zone or "position not shared"))
			or m.near and string.format("hidden, right next to you (%d yds)", floor(m.distance + 0.5))
			or not m.x and "off the compass"
			or string.format("%d px from center, %d yds%s", floor(m.x + 0.5), floor(m.distance + 0.5),
				m.leader and m.leader ~= m and (", stacked under " .. m.leader.unit) or "")
		msg(string.format("%s: icon %s, marker %s, %s", m.unit, m.kind or "none", markerText, where))
	end
	msg(db.stack and string.format("Stacking on: icons closer than %d px stack.", ns.stackGap or db.size + STACK_PADDING) or "Stacking off.")
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		CompassCrewDB = CompassCrewDB or {}
		db = CompassCrewDB
		for k, v in pairs(ns.DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
		self:UnregisterEvent("ADDON_LOADED")
		for _, e in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "RAID_TARGET_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_CONNECTION" }) do
			self:RegisterEvent(e)
		end
		C_Timer.NewTicker(0.5, slowUpdate) -- dead/alive, members elsewhere, anything an event missed
		if ns.BuildOptions then ns.BuildOptions() end
		rebuildMembers()
	elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
		rebuildMembers()
	elseif event == "UNIT_PORTRAIT_UPDATE" then
		local m = byUnit[arg1]
		if m then m.version = (m.version or 0) + 1 end
	else
		refreshAll()
	end
end)
