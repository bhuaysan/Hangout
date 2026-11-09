local _, ns = ...

local Theme = {}
ns.Theme = Theme

local EXPORT_PREFIX = "Hangout1"

Theme.CUSTOMIZABLE = {
	{ token = "bg", label = "Background" },
	{ token = "sidebar", label = "Sidebar" },
	{ token = "text", label = "Text" },
	{ token = "muted", label = "Secondary text" },
	{ token = "accent", label = "Accent" },
}

-- Below this the window stops being readable over a bright game world.
Theme.MIN_OPACITY = 70

local MIN_NAME_CONTRAST = 4.5
local NAME_MIX_STEP = 0.05
local CREST_RING_ALPHA = 0.55
local GLANCE_ALPHA = 0.82
local MY_BUBBLE_ALPHA = 0.24
local MY_BUBBLE_HOVER_ALPHA = 0.34
local THEIR_BUBBLE_HOVER_ALPHA = 0.17

local DARK_OVERLAYS = {
	hover = { 1, 1, 1, 0.05 },
	selected = { 1, 1, 1, 0.10 },
	divider = { 1, 1, 1, 0.07 },
	outline = { 1, 1, 1, 0.30 },
	dock = { 0, 0, 0, 0.25 },
	raised = { 1, 1, 1, 0.05 },
	edge = { 0, 0, 0, 0.55 },
	field = { 1, 1, 1, 0.08 },
	notice = { 0.62, 0.42, 0.08, 0.45 },
}

local LIGHT_OVERLAYS = {
	hover = { 0, 0, 0, 0.05 },
	selected = { 0, 0, 0, 0.10 },
	divider = { 0, 0, 0, 0.12 },
	outline = { 0, 0, 0, 0.35 },
	dock = { 0, 0, 0, 0.07 },
	raised = { 1, 1, 1, 0.35 },
	edge = { 0, 0, 0, 0.18 },
	field = { 1, 1, 1, 0.55 },
	notice = { 0.95, 0.70, 0.20, 0.55 },
}

local PRESETS = {
	midnight = {
		label = "Midnight",
		overlays = DARK_OVERLAYS,
		colors = {
			bg = { 0.12, 0.125, 0.14 },
			sidebar = { 0.09, 0.095, 0.11 },
			text = { 0.86, 0.87, 0.89 },
			muted = { 0.58, 0.61, 0.64 },
			accent = { 0.96, 0.76, 0.26 },
		},
	},
	ember = {
		label = "Ember",
		overlays = DARK_OVERLAYS,
		colors = {
			bg = { 0.15, 0.12, 0.11 },
			sidebar = { 0.11, 0.09, 0.08 },
			text = { 0.91, 0.87, 0.82 },
			muted = { 0.65, 0.58, 0.52 },
			accent = { 0.90, 0.48, 0.18 },
		},
	},
	paper = {
		label = "Paper",
		overlays = LIGHT_OVERLAYS,
		colors = {
			bg = { 0.95, 0.94, 0.91 },
			sidebar = { 0.88, 0.86, 0.82 },
			text = { 0.16, 0.15, 0.14 },
			muted = { 0.42, 0.40, 0.37 },
			accent = { 0.48, 0.30, 0.04 },
		},
	},
}

Theme.PRESET_ORDER = { "midnight", "ember", "paper" }

local tokens = {}
local messageFont = CreateFont("HangoutMessageFont")

local function ActivePreset()
	return PRESETS[ns.db.theme.active or "midnight"] or PRESETS.midnight
end

local function BuildTokens()
	local preset = ActivePreset()
	local custom = ns.db.theme.custom
	local opacity = ns.Get("windowOpacity") / 100

	tokens = {}
	for token, color in pairs(preset.overlays) do
		tokens[token] = color
	end
	for token, color in pairs(preset.colors) do
		local override = custom[token] or color
		tokens[token] = { override[1], override[2], override[3], 1 }
	end
	-- A solid copy of the background, for layers that cover other content.
	tokens.panel = { tokens.bg[1], tokens.bg[2], tokens.bg[3], 1 }
	local field = tokens.field
	tokens.fieldSolid = {
		tokens.bg[1] + (field[1] - tokens.bg[1]) * field[4],
		tokens.bg[2] + (field[2] - tokens.bg[2]) * field[4],
		tokens.bg[3] + (field[3] - tokens.bg[3]) * field[4],
		1,
	}
	tokens.popup = { tokens.sidebar[1], tokens.sidebar[2], tokens.sidebar[3], 1 }
	tokens.glance = { tokens.sidebar[1], tokens.sidebar[2], tokens.sidebar[3], GLANCE_ALPHA }
	tokens.crestRing = { tokens.muted[1], tokens.muted[2], tokens.muted[3], CREST_RING_ALPHA }
	tokens.bubbleMine = { tokens.accent[1], tokens.accent[2], tokens.accent[3], MY_BUBBLE_ALPHA }
	tokens.bubbleMineHover = { tokens.accent[1], tokens.accent[2], tokens.accent[3], MY_BUBBLE_HOVER_ALPHA }
	tokens.bubbleTheirsHover = { tokens.selected[1], tokens.selected[2], tokens.selected[3], THEIR_BUBBLE_HOVER_ALPHA }
	tokens.bg[4] = opacity
	tokens.sidebar[4] = opacity
end

local function ApplyFont()
	local path, _, flags = ChatFontNormal:GetFont()
	messageFont:SetFont(path, ns.Get("messageSize"), flags)
end

function Theme.Apply()
	if ns.Get("windowOpacity") < Theme.MIN_OPACITY then
		ns.Set("windowOpacity", Theme.MIN_OPACITY)
	end
	BuildTokens()
	ApplyFont()
	ns.Widgets.Repaint()
	ns.Fire("THEME_CHANGED")
end

function Theme.Color(token)
	local color = tokens[token]
	return color[1], color[2], color[3], color[4]
end

local function LinearChannel(value)
	if value <= 0.03928 then
		return value / 12.92
	end
	return ((value + 0.055) / 1.055) ^ 2.4
end

local function Luminance(r, g, b)
	return 0.2126 * LinearChannel(r) + 0.7152 * LinearChannel(g) + 0.0722 * LinearChannel(b)
end

-- The game's fonts cast a black shadow, which smears dark text on a light surface.
function Theme.TextShadow()
	local text, bg = tokens.text, tokens.bg
	local isDarkText = Luminance(text[1], text[2], text[3]) < Luminance(bg[1], bg[2], bg[3])
	return 0, 0, 0, isDarkText and 0 or 1
end

local function Contrast(luminanceA, luminanceB)
	local lighter = math.max(luminanceA, luminanceB)
	local darker = math.min(luminanceA, luminanceB)
	return (lighter + 0.05) / (darker + 0.05)
end

-- The color of a surface token, with an optional overlay token on top of it.
local function SurfaceLuminance(surface, overlay)
	local base = tokens[surface]
	local r, g, b = base[1], base[2], base[3]
	local top = overlay and tokens[overlay]
	if top then
		r = r + (top[1] - r) * top[4]
		g = g + (top[2] - g) * top[4]
		b = b + (top[3] - b) * top[4]
	end
	return Luminance(r, g, b)
end

-- Mixes a color toward white or black until it can be read on the surface.
local function Readable(r, g, b, surfaceLuminance)
	local target = Contrast(1, surfaceLuminance) >= Contrast(0, surfaceLuminance) and 1 or 0
	local mix = 0
	while mix < 1 do
		local mixedR = r + (target - r) * mix
		local mixedG = g + (target - g) * mix
		local mixedB = b + (target - b) * mix
		if Contrast(Luminance(mixedR, mixedG, mixedB), surfaceLuminance) >= MIN_NAME_CONTRAST then
			return mixedR, mixedG, mixedB
		end
		mix = mix + NAME_MIX_STEP
	end
	return target, target, target
end

-- Class color when known, adjusted to be readable on the surface it sits on
-- ("bg" unless given), otherwise the normal text color.
function Theme.ClassColor(classToken, surface, overlay)
	local color = classToken and RAID_CLASS_COLORS[classToken]
	if not color then
		return Theme.Color("text")
	end
	local r, g, b = Readable(color.r, color.g, color.b, SurfaceLuminance(surface or "bg", overlay))
	return r, g, b, 1
end

function Theme.PresetLabel(name)
	return PRESETS[name].label
end

function Theme.ActiveName()
	local active = ns.db.theme.active
	return PRESETS[active or ""] and active or "midnight"
end

-- Choosing a preset starts fresh from its own colors.
function Theme.SetPreset(name)
	ns.db.theme.active = name
	ns.db.theme.custom = {}
	Theme.Apply()
end

function Theme.SetCustom(token, r, g, b)
	ns.db.theme.custom[token] = { r, g, b }
	Theme.Apply()
end

function Theme.ResetCustom()
	ns.db.theme.custom = {}
	Theme.Apply()
end

local function ToHex(color)
	return ("%02x%02x%02x"):format(
		math.floor(color[1] * 255 + 0.5),
		math.floor(color[2] * 255 + 0.5),
		math.floor(color[3] * 255 + 0.5))
end

function Theme.Export()
	local parts = {}
	for _, entry in ipairs(Theme.CUSTOMIZABLE) do
		parts[#parts + 1] = entry.token .. "=" .. ToHex(tokens[entry.token])
	end
	return EXPORT_PREFIX .. ":" .. Theme.ActiveName() .. ":" .. table.concat(parts, ",")
end

local function IsCustomizable(token)
	for _, entry in ipairs(Theme.CUSTOMIZABLE) do
		if entry.token == token then return true end
	end
	return false
end

-- Theme strings come from other players, so only known tokens and plain hex
-- colors are accepted. Returns true if the theme was applied.
function Theme.Import(text)
	local preset, body = ns.Util.Trim(text):match("^" .. EXPORT_PREFIX .. ":(%a+):(.+)$")
	if not preset or not PRESETS[preset] then return false end

	local custom = {}
	for part in body:gmatch("[^,]+") do
		local token, red, green, blue = part:match("^(%a+)=(%x%x)(%x%x)(%x%x)$")
		if not token or not IsCustomizable(token) then return false end
		custom[token] = { tonumber(red, 16) / 255, tonumber(green, 16) / 255, tonumber(blue, 16) / 255 }
	end
	if not next(custom) then return false end

	ns.db.theme.active = preset
	ns.db.theme.custom = custom
	Theme.Apply()
	return true
end
