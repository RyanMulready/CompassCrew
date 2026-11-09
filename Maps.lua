-- Minimap and world map icons: the same icons as the compass, placed with HereBeDragons-Pins
-- (added to Libs by the packager). Positions update 5 times a second; icons redraw only when they change.
-- With OpenMap, these show over the zone under the view (as Blizzard's own group dots do), and
-- a toggle for them is added to OpenMap's menu.

local ADDON_NAME, ns = ...
if not ns.Get then return end -- Wayfinder missing; already reported

local pins = LibStub("HereBeDragons-Pins-2.0", true)
if not pins then
	ns.msg("Map pins library missing; minimap and world map icons are off.")
	return
end

local hbd, safe = ns.hbd, ns.safe
local SHOW_ON = HBD_PINS_WORLDMAP_SHOW_CONTINENT or 2           -- zone and continent maps
local LEVEL = "PIN_FRAME_LEVEL_VEHICLE_ABOVE_GROUP_MEMBER"     -- just above Blizzard's group dots
local MOVE = 0.5                                                -- yds; less doesn't re-place a world pin

local ticker

local function tooltip(holder)
	local m = holder.member
	local name = safe(UnitName(m.unit))
	local c = m.class and RAID_CLASS_COLORS[m.class]
	GameTooltip:SetOwner(holder, "ANCHOR_RIGHT")
	GameTooltip:SetText(name or m.unit, c and c.r or 1, c and c.g or 1, c and c.b or 1)
	local px, py, pi = hbd:GetPlayerWorldPosition()
	local ux, uy, ui = hbd:GetUnitWorldPosition(m.unit)
	local _, dist = px and ux and pi == ui and hbd:GetWorldVector(pi, px, py, ux, uy)
	if dist then GameTooltip:AddLine(string.format("%d yards away", math.floor(dist + 0.5)), 0.8, 0.8, 0.8) end
	if m.dead then GameTooltip:AddLine(DEAD or "Dead", 1, 0.3, 0.3) end
	GameTooltip:Show()
end

local function icon(m)
	local p = ns.CreateIconFrame(UIParent, ns.Get("mapSize"))
	p.holder.member = m
	p.holder:SetMouseMotionEnabled(true) -- hover for the tooltip; clicks still reach the map
	p.holder:SetScript("OnEnter", tooltip)
	p.holder:SetScript("OnLeave", GameTooltip_Hide)
	return p
end

local function removeAll(m)
	if m.mini and m.mini.placed then pins:RemoveMinimapIcon(ADDON_NAME, m.mini.holder); m.mini.placed = nil end
	if m.world and m.world.placed then pins:RemoveWorldMapIcon(ADDON_NAME, m.world.holder); m.world.placed = nil end
end

local function update()
	local wantMini, wantWorld = ns.Get("minimap"), ns.Get("worldmap")
	for _, m in pairs(ns.byUnit) do
		local x, y, inst
		if m.active and m.kind then x, y, inst = hbd:GetUnitWorldPosition(m.unit) end
		if not x then
			removeAll(m)
		else
			if wantMini then
				m.mini = m.mini or icon(m)
				ns.ApplyIcon(m.mini, m)
				pins:AddMinimapIconWorld(ADDON_NAME, m.mini.holder, inst, x, y, true) -- true: stay on the edge
				m.mini.placed = true
			elseif m.mini and m.mini.placed then
				pins:RemoveMinimapIcon(ADDON_NAME, m.mini.holder); m.mini.placed = nil
			end
			if wantWorld then
				m.world = m.world or icon(m)
				local w = m.world
				ns.ApplyIcon(w, m)
				-- re-placing a world pin rebuilds it, so only when they actually moved
				if not w.placed or math.abs(w.x - x) > MOVE or math.abs(w.y - y) > MOVE then
					pins:AddWorldMapIconWorld(ADDON_NAME, w.holder, inst, x, y, SHOW_ON, LEVEL)
					w.placed, w.x, w.y = true, x, y
				end
			elseif m.world and m.world.placed then
				pins:RemoveWorldMapIcon(ADDON_NAME, m.world.holder); m.world.placed = nil
			end
		end
	end
end

-- OpenMap: a switch for these icons in its menu (its API is read-only otherwise). Added once
-- settings are loaded, since OpenMap may read it straight away.
local function registerOpenMap()
	registerOpenMap = nil
	if not (OpenMapAPI and OpenMapAPI.RegisterMenuToggle) then return end
	OpenMapAPI.RegisterMenuToggle("CompassCrew", {
		id = "worldmap",
		label = "Compass Crew party icons",
		icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
		get = function() return ns.Get("worldmap") end,
		set = function(on) ns.Set("worldmap", on) end,
	})
end

-- Run only while there's a group and a map to show it on.
local function setTicker()
	if registerOpenMap then registerOpenMap() end
	local want = #ns.members > 0 and (ns.Get("minimap") or ns.Get("worldmap"))
	if want and not ticker then
		ticker = C_Timer.NewTicker(0.2, update)
	elseif not want and ticker then
		ticker:Cancel()
		ticker = nil
	end
	update()
end

ns.OnMembersChanged = setTicker

function ns.OnSettingChanged(key)
	if key == "mapSize" then
		local size = ns.Get("mapSize")
		for _, m in pairs(ns.byUnit) do
			if m.mini then m.mini.holder:SetSize(size, size) end
			if m.world then m.world.holder:SetSize(size, size) end
		end
	elseif key == "minimap" or key == "worldmap" then
		setTicker()
	end
end
