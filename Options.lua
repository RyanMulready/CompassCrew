-- Options page in Esc > Options > AddOns > Compass Crew (or /crew).
--
-- A canvas category built from the addon's own frames: Blizzard's pooled Settings.Create*
-- controls are reused on Blizzard's own pages and would carry this addon's taint onto them
-- (the reason Wayfinder builds its page this way too). The page is laid out from LAYOUT.

local _, ns = ...
if not ns.Get then return end -- Wayfinder missing; already reported

local category
local LEFT, ROW = 16, 30
local refreshers = {} -- functions that sync a control with the saved setting

-- Preview icons reuse the real icon code, with "members" made from your own character.
local function sample(kind)
	return { unit = "player", kind = kind, marker = 1, version = 0 }
end
local samples = { class = sample("class"), marker = sample("marker"), portrait = sample("portrait") }
local function sampleIcon(parent, kind, size)
	local p = ns.CreateIconFrame(parent, size)
	p.kind = kind
	p.holder:Show()
	return p
end
local function drawSample(p)
	local s = samples[p.kind]
	s.class = select(2, UnitClass("player"))
	if s.kind == "class" and not (s.class and CLASS_ICON_TCOORDS[s.class]) then return end
	s.version = s.version + 1 -- always redraw: your portrait isn't ready when the addon loads
	ns.ApplyIcon(p, s)
end

local function text(parent, str, font)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	fs:SetText(str)
	return fs
end

local function tooltip(owner, title, body)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		GameTooltip:AddLine(body, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", GameTooltip_Hide)
end

---------------------------------------------------------------------------
-- Controls. Each takes (parent, y, ...) and returns the next y.
---------------------------------------------------------------------------

local function header(parent, y, title)
	y = y - 16
	local fs = text(parent, title, "GameFontNormalLarge")
	fs:SetPoint("TOPLEFT", LEFT, y)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
	line:SetPoint("RIGHT", parent, "RIGHT", -LEFT, 0)
	return y - 32
end

local function check(parent, y, key, label, tip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb:SetPoint("TOPLEFT", LEFT, y)
	text(cb, label):SetPoint("LEFT", cb, "RIGHT", 4, 0)
	cb:SetScript("OnClick", function(self)
		ns.Set(key, self:GetChecked() and true or false)
		for _, r in ipairs(refreshers) do r() end -- the preview reflects some of these
	end)
	tooltip(cb, label, tip)
	refreshers[#refreshers + 1] = function() cb:SetChecked(ns.Get(key)) end
	return y - ROW
end

local function slider(parent, y, key, label, minV, maxV)
	local fs = text(parent, label, "GameFontNormal")
	fs:SetPoint("TOPLEFT", LEFT + 4, y - 4)
	local s = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	s:SetSize(220, 20)
	s:SetPoint("LEFT", fs, "LEFT", 120, 0)
	s:Init(ns.Get(key), minV, maxV, maxV - minV, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(v) return string.format("%d px", math.floor(v + 0.5)) end,
	})
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
		v = math.floor(v + 0.5)
		if v ~= ns.Get(key) then
			ns.Set(key, v)
			for _, r in ipairs(refreshers) do r() end
		end
	end, s)
	refreshers[#refreshers + 1] = function() s:SetValue(ns.Get(key)) end
	return y - 34, s
end

local STYLES = {
	{ ns.STYLE_CLASS, "Class icon", { "class" } },
	{ ns.STYLE_AUTO, "Target marker, or class icon if unmarked", { "marker", "class" } },
	{ ns.STYLE_MARKER, "Target marker only (hide unmarked members)", { "marker" } },
	{ ns.STYLE_PORTRAIT, "Player portrait", { "portrait" } },
}

local function styles(parent, y)
	local buttons, icons = {}, {}
	for i, st in ipairs(STYLES) do
		local rb = CreateFrame("CheckButton", nil, parent, "UIRadioButtonTemplate")
		rb:SetPoint("TOPLEFT", LEFT + 4, y - (i - 1) * 26)
		local x = 24
		for _, kind in ipairs(st[3]) do
			local p = sampleIcon(rb, kind, 18)
			p.holder:SetPoint("LEFT", rb, "LEFT", x, 0)
			icons[#icons + 1] = p
			x = x + 20
		end
		text(rb, st[2]):SetPoint("LEFT", rb, "LEFT", x + 6, 0)
		rb:SetScript("OnClick", function()
			ns.Set("style", st[1])
			for _, r in ipairs(refreshers) do r() end
		end)
		buttons[i] = rb
	end
	refreshers[#refreshers + 1] = function()
		for i, rb in ipairs(buttons) do rb:SetChecked(STYLES[i][1] == ns.Get("style")) end
		for _, p in ipairs(icons) do drawSample(p) end
	end
	return y - #STYLES * 26 - 8
end

-- The compass size slider, with a preview of how members will look on the compass.
local function sizeWithPreview(parent, y)
	local nextY, s = slider(parent, y, "size", "Icon size", 10, 40)
	local box = CreateFrame("Frame", nil, parent)
	box:SetSize(130, 84)
	box:SetPoint("LEFT", s, "RIGHT", 50, 0)
	local bg = box:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.45)
	local tick = box:CreateTexture(nil, "BORDER")
	tick:SetColorTexture(1, 1, 1, 0.6)
	tick:SetSize(2, 84)
	tick:SetPoint("CENTER")
	local icons = { class = sampleIcon(box, "class", 25), marker = sampleIcon(box, "marker", 25), portrait = sampleIcon(box, "portrait", 25) }
	local dist = text(box, IN_GAME_NAVIGATION_RANGE and IN_GAME_NAVIGATION_RANGE:format("40") or "40 yds", "GameFontNormalSmall")
	local eta = text(box, "12s", "GameFontNormalSmall")

	refreshers[#refreshers + 1] = function()
		local size, kinds = ns.Get("size"), nil
		for _, st in ipairs(STYLES) do if st[1] == ns.Get("style") then kinds = st[3] end end
		for _, p in pairs(icons) do p.holder:Hide() end
		for i, kind in ipairs(kinds) do
			local p = icons[kind]
			p.holder:SetSize(size, size)
			p.holder:ClearAllPoints()
			p.holder:SetPoint("CENTER", box, "CENTER", #kinds == 1 and 0 or (i == 1 and -32 or 32), 0)
			p.holder:Show()
			drawSample(p)
		end
		-- the readout under the first icon, as on the compass
		local first = icons[kinds[1]].holder
		local showD = ns.Get("showDistance") and ns.WayfinderShows("Distance")
		dist:ClearAllPoints()
		dist:SetPoint("TOP", first, "BOTTOM", 0, -2)
		dist:SetShown(showD)
		eta:ClearAllPoints()
		eta:SetPoint("TOP", showD and dist or first, "BOTTOM", 0, -2)
		eta:SetShown(ns.Get("showDistance") and ns.WayfinderShows("ETA"))
	end
	return nextY - 36
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

local LAYOUT = {
	{ header, "Icons" },
	{ styles },
	{ sizeWithPreview },
	{ check, "distanceScale", "Shrink icons for members farther away",
		string.format("Icons are full size within %d yards and shrink to half size at %d yards.", ns.NEAR, ns.FAR) },
	{ check, "showDistance", "Show distance and ETA under icons",
		"The readout Wayfinder shows for your tracked target. Each line also follows Wayfinder's own 'Show distance' and 'Show ETA' settings." },
	{ header, "Members" },
	{ check, "sticky", "Pin members behind you to the compass edges",
		"Members you're facing away from stay at the left or right edge, so you know which way to turn." },
	{ check, "stack", "Stack members who are close together",
		"Members whose icons would overlap are shown as one icon with a count: someone with a target marker, or else the nearest." },
	{ check, "hideNear", "Hide members right next to you",
		"Members within 10 yards are left off the compass, since you can see them anyway." },
	{ check, "showAway", "Show members who are elsewhere",
		"Members on another continent or inside a dungeon or raid show as small icons under the compass. Hover one for their zone." },
	{ check, "dimDead", "Grey out dead members", "So it's easy to find who needs a resurrection." },
	{ check, "raid", "Show raid members", "Everyone in a raid, not just your party. Large raids can crowd the compass." },
	{ header, "Maps" },
	{ check, "minimap", "Show members on the minimap", "Members out of minimap range sit on its edge." },
	{ check, "worldmap", "Show members on the world map", "Hover an icon for the member's name and distance." },
	{ slider, "mapSize", "Map icon size", 10, 32 },
}

local function refreshAll()
	for _, r in ipairs(refreshers) do r() end
end

function ns.BuildOptions()
	local panel = CreateFrame("Frame")
	panel:Hide()

	-- A scrolling page, so it fits at any UI scale.
	local scroll = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(600, 720)
	scroll:SetScrollChild(page)
	panel:SetScript("OnSizeChanged", function(_, w) page:SetWidth(math.max(400, (w or 600) - 32)) end)

	local title = text(page, "Compass Crew", "GameFontHighlightHuge")
	title:SetPoint("TOPLEFT", LEFT, -16)
	local sub = text(page, "See your party on your Wayfinder compass, minimap and world map.", "GameFontHighlightSmall")
	sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	sub:SetTextColor(0.75, 0.75, 0.75)

	local y = -64
	for _, row in ipairs(LAYOUT) do
		y = row[1](page, y, unpack(row, 2))
	end
	local note = text(page, "Group members can't be shown inside dungeons and raids: the game hides their positions from addons there.", "GameFontDisableSmall")
	note:SetPoint("TOPLEFT", LEFT, y - 16)
	note:SetPoint("RIGHT", page, "RIGHT", -LEFT, 0)
	note:SetJustifyH("LEFT")
	page:SetHeight(-y + 60)

	-- Called by the Settings panel (through securecallfunction).
	panel.OnRefresh = refreshAll
	panel.OnDefault = function() ns.ResetToDefaults(); refreshAll() end
	panel:SetScript("OnShow", refreshAll)

	category = Settings.RegisterCanvasLayoutCategory(panel, "Compass Crew")
	Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
	if category then Settings.OpenToCategory(category:GetID()) end
end
