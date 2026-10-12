-- ASS drawing helpers, theme and icons.
local mp = require 'mp'

local D = {}

D.font = "Inter"
D.icon_font = "lucide"

-- Theme (hex RRGGBB). Sampled from the VLC redesign mockups.
D.T = {
    bar      = "1b1b1b",  -- top / bottom bars
    panel    = "141414",  -- side panels
    panel2   = "1b1b1b",  -- cards inside panels
    menu     = "181818",
    surface  = "222222",  -- hovered / selected rows
    input    = "0a0a0a",  -- tracks, inputs
    line     = "262626",
    knob     = "424242",
    text     = "d6d6d6",
    text2    = "9a9a9a",
    text3    = "666666",
    white    = "ffffff",
    green    = "7ba213",
    accent   = "d37918",
}

D.accents = {
    { "Orange", "d37918" }, { "Red", "c0462c" }, { "Olive", "a8891f" },
    { "Green", "1f9a39" },  { "Teal", "1a93b5" }, { "Blue", "2a62c9" },
    { "Purple", "7c43d6" }, { "Pink", "c9479a" }, { "Gray", "8a8a8a" },
}

local function hex2rgb(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1, 2), 16) or 0, tonumber(hex:sub(3, 4), 16) or 0, tonumber(hex:sub(5, 6), 16) or 0
end

function D.mix(a, b, t)
    local r1, g1, b1 = hex2rgb(a)
    local r2, g2, b2 = hex2rgb(b)
    local function m(x, y) return math.floor(x + (y - x) * t + 0.5) end
    return string.format("%02x%02x%02x", m(r1, r2), m(g1, g2), m(b1, b2))
end

function D.set_accent(hex)
    hex = (hex or "d37918"):gsub("#", ""):lower()
    if not hex:match("^%x%x%x%x%x%x$") then hex = "d37918" end
    D.T.accent = hex
    D.T.accent_dim = D.mix(hex, "000000", 0.74)   -- seekbar / slider fill
    D.T.accent_soft = D.mix(hex, "000000", 0.6)   -- selected segment background
end
D.set_accent(D.T.accent)

function D.c(hex)
    local r, g, b = hex2rgb(hex)
    return string.format("&H%02X%02X%02X&", b, g, r)
end

function D.a(opacity)
    opacity = math.max(0, math.min(1, opacity or 1))
    return string.format("&H%02X&", math.floor((1 - opacity) * 255 + 0.5))
end

function D.esc(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\239\187\191"):gsub("{", "\\{"):gsub("\n", " ")
    return s
end

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- Lucide icon codepoints
local icon_cp = {
    play = 0xe13c, pause = 0xe12e, ["skip-back"] = 0xe15f, ["skip-forward"] = 0xe160,
    ["chevron-right"] = 0xe06f, ["chevron-left"] = 0xe06e, ["chevron-down"] = 0xe06d, ["chevron-up"] = 0xe070,
    ellipsis = 0xe0b6, ["panel-left"] = 0xe12a, ["panel-right"] = 0xe431, folder = 0xe0d7, ["folder-open"] = 0xe247,
    minus = 0xe11c, square = 0xe167, copy = 0xe09e, maximize = 0xe112, minimize = 0xe11a, x = 0xe1b2,
    volume = 0xe1a9, ["volume-1"] = 0xe1aa, ["volume-2"] = 0xe1ab, ["volume-x"] = 0xe1ac,
    ["audio-lines"] = 0xe55a, captions = 0xe3a4, settings = 0xe154, list = 0xe106,
    ["list-music"] = 0xe2e0, ["list-video"] = 0xe2e2, pip = 0xe3af, stop = 0xe685, record = 0xe345,
    ["eye-off"] = 0xe0bb, eye = 0xe0ba, clapperboard = 0xe29b, sliders = 0xe29a, ["log-out"] = 0xe10e,
    ["file-video"] = 0xe321, ["file-plus"] = 0xe0c9, ["folder-plus"] = 0xe0d9, link = 0xe102,
    clipboard = 0xe085, history = 0xe1f5, keyboard = 0xe284, info = 0xe0f9, check = 0xe06c,
    plus = 0xe13d, trash = 0xe18e, ["repeat"] = 0xe146, ["repeat-1"] = 0xe1fd, shuffle = 0xe15e,
    bookmark = 0xe060, ["bookmark-plus"] = 0xe23d, gauge = 0xe1bf, timer = 0xe1e0, moon = 0xe11e,
    ["rotate-cw"] = 0xe149, ["flip-h"] = 0xe360, ["flip-v"] = 0xe35e, ["zoom-in"] = 0xe1b6,
    ["arrow-left"] = 0xe048, ["arrow-right"] = 0xe049, ["arrow-up-down"] = 0xe37d, search = 0xe151,
    grip = 0xe0eb, camera = 0xe064, film = 0xe0d0, house = 0xe0f5, music = 0xe122, radio = 0xe142,
    ["monitor-play"] = 0xe485, ["list-ordered"] = 0xe1d1, type = 0xe198, palette = 0xe1dd,
    sun = 0xe178, contrast = 0xe09d, headphones = 0xe0f1, rewind = 0xe147, ["fast-forward"] = 0xe0bd,
    undo = 0xe2a1, ["file-text"] = 0xe0cc, layers = 0xe529, sparkles = 0xe412, hourglass = 0xe296,
    speaker = 0xe166, ["settings-2"] = 0xe245,
}
D.icons = {}
for k, v in pairs(icon_cp) do D.icons[k] = utf8char(v) end

local function f(n) return string.format("%.1f", n) end

local function clip_tag(c, outer)
    if c and outer and c ~= outer then
        c = { math.max(c[1], outer[1]), math.max(c[2], outer[2]), math.min(c[3], outer[3]), math.min(c[4], outer[4]) }
        if c[3] < c[1] then c[3] = c[1] end
        if c[4] < c[2] then c[4] = c[2] end
    end
    c = c or outer
    if not c then return "" end
    if c[3] - c[1] < 0.5 or c[4] - c[2] < 0.5 then return nil end -- fully clipped: caller skips the event
    return string.format("\\clip(%d,%d,%d,%d)", math.floor(c[1]), math.floor(c[2]), math.ceil(c[3]), math.ceil(c[4]))
end
D.clip_tag = clip_tag

-- Rounded rectangle as an ASS drawing path (absolute coordinates).
function D.rrect_path(x, y, w, h, r)
    r = math.max(0, math.min(r or 0, w / 2, h / 2))
    if r < 0.5 then
        return string.format("m %s %s l %s %s %s %s %s %s", f(x), f(y), f(x + w), f(y), f(x + w), f(y + h), f(x), f(y + h))
    end
    local c = r * 0.5523
    local x2, y2 = x + w, y + h
    return table.concat({
        "m", f(x + r), f(y),
        "l", f(x2 - r), f(y),
        "b", f(x2 - r + c), f(y), f(x2), f(y + r - c), f(x2), f(y + r),
        "l", f(x2), f(y2 - r),
        "b", f(x2), f(y2 - r + c), f(x2 - r + c), f(y2), f(x2 - r), f(y2),
        "l", f(x + r), f(y2),
        "b", f(x + r - c), f(y2), f(x), f(y2 - r + c), f(x), f(y2 - r),
        "l", f(x), f(y + r),
        "b", f(x), f(y + r - c), f(x + r - c), f(y), f(x + r), f(y),
    }, " ")
end

function D.poly_path(pts)
    local out = { "m", f(pts[1][1]), f(pts[1][2]), "l" }
    for i = 2, #pts do
        out[#out + 1] = f(pts[i][1]); out[#out + 1] = f(pts[i][2])
    end
    return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Builder: collects ASS events for one frame.
---------------------------------------------------------------------------
local B = {}
B.__index = B

function D.builder()
    return setmetatable({ out = {}, n = 0, clip = nil, fade = 1 }, B)
end

function B:push(s)
    self.n = self.n + 1
    self.out[self.n] = s
end

function B:result() return table.concat(self.out, "\n") end

local function shape_tags(self, o)
    local op = (o.opacity or 1) * self.fade
    local t = "{\\an7\\pos(0,0)\\shad0\\bord" .. f(o.border or 0) .. "\\1c" .. D.c(o.color or "000000") .. "\\1a" .. D.a(op)
    if o.border and o.border > 0 then
        t = t .. "\\3c" .. D.c(o.border_color or D.T.line) .. "\\3a" .. D.a((o.border_opacity or 1) * self.fade)
    end
    if o.blur then t = t .. "\\blur" .. f(o.blur) end
    local ct = clip_tag(o.clip, self.clip)
    if not ct then return nil end
    return t .. ct .. "\\p1}"
end

function B:rect(x, y, w, h, o)
    o = o or {}
    if w <= 0 or h <= 0 then return end
    local t = shape_tags(self, o)
    if t then self:push(t .. D.rrect_path(x, y, w, h, o.r or 0) .. "{\\p0}") end
end

function B:poly(pts, o)
    local t = shape_tags(self, o or {})
    if t then self:push(t .. D.poly_path(pts) .. "{\\p0}") end
end

function B:path(path, o)
    local t = shape_tags(self, o or {})
    if t then self:push(t .. path .. "{\\p0}") end
end

-- Text. o.align uses ASS numpad alignment (default 4 = left / vertically centered).
function B:text(x, y, str, o)
    o = o or {}
    local op = (o.opacity or 1) * self.fade
    local ct = clip_tag(o.clip, self.clip)
    if not ct then return end
    self:push(string.format("{\\an%d\\pos(%s,%s)\\fn%s\\fs%s\\bord0\\shad0\\b%d\\q2\\1c%s\\1a%s%s}%s",
        o.align or 4, f(x), f(y), o.font or D.font, f(o.size or 14), o.bold and 1 or 0,
        D.c(o.color or D.T.text), D.a(op), ct, o.raw and str or D.esc(str)))
end

-- Lucide icon centered on (cx, cy).
function B:icon(cx, cy, name, o)
    o = o or {}
    local glyph = D.icons[name] or name
    local size = o.size or 18
    local ct = clip_tag(o.clip, self.clip)
    if not ct then return end
    self:push(string.format("{\\an5\\pos(%s,%s)\\fn%s\\fs%s\\bord0\\shad0\\1c%s\\1a%s%s}%s",
        f(cx), f(cy), D.icon_font, f(size * 1.32),
        D.c(o.color or D.T.text2), D.a((o.opacity or 1) * self.fade), ct, glyph))
end

-- Filled media glyphs (crisper than the outline font for the transport controls).
function B:glyph(kind, cx, cy, size, color, o)
    o = o or {}
    local s = size / 2
    local col = { color = color, opacity = o.opacity, clip = o.clip }
    if kind == "play" then
        self:poly({ { cx - s * 0.62, cy - s * 0.78 }, { cx + s * 0.82, cy }, { cx - s * 0.62, cy + s * 0.78 } }, col)
    elseif kind == "pause" then
        self:rect(cx - s * 0.62, cy - s * 0.75, s * 0.42, s * 1.5, { color = color, r = s * 0.08, opacity = o.opacity })
        self:rect(cx + s * 0.2, cy - s * 0.75, s * 0.42, s * 1.5, { color = color, r = s * 0.08, opacity = o.opacity })
    elseif kind == "prev" then
        self:rect(cx - s * 0.7, cy - s * 0.66, s * 0.26, s * 1.32, col)
        self:poly({ { cx + s * 0.62, cy - s * 0.66 }, { cx - s * 0.36, cy }, { cx + s * 0.62, cy + s * 0.66 } }, col)
    elseif kind == "next" then
        self:rect(cx + s * 0.44, cy - s * 0.66, s * 0.26, s * 1.32, col)
        self:poly({ { cx - s * 0.62, cy - s * 0.66 }, { cx + s * 0.36, cy }, { cx - s * 0.62, cy + s * 0.66 } }, col)
    elseif kind == "stop" then
        self:rect(cx - s * 0.6, cy - s * 0.6, s * 1.2, s * 1.2, { color = color, r = s * 0.12, opacity = o.opacity })
    end
end

-- The traffic cone logo.
function B:cone(cx, cy, size, color, o)
    o = o or {}
    local u = size / 24
    local x0, y0 = cx - 12 * u, cy - 12 * u
    local function P(x, y) return { x0 + x * u, y0 + y * u } end
    local function edge(y) -- cone silhouette x positions at height y
        local t = (y - 2) / 17.5
        return 10.3 - 4.6 * t, 13.7 + 4.6 * t
    end
    self:rect(x0 + 3 * u, y0 + 19 * u, 18 * u, 3 * u, { color = color, r = 0.8 * u, opacity = o.opacity })
    self:poly({ P(10.3, 2), P(13.7, 2), P(18.3, 19.5), P(5.7, 19.5) }, { color = color, opacity = o.opacity })
    local stripe = o.stripe or "f2f2f2"
    for _, band in ipairs({ { 7, 9.6 }, { 12.6, 15.2 } }) do
        local l1, r1 = edge(band[1])
        local l2, r2 = edge(band[2])
        self:poly({ P(l1, band[1]), P(r1, band[1]), P(r2, band[2]), P(l2, band[2]) }, { color = stripe, opacity = o.opacity })
    end
end

---------------------------------------------------------------------------
-- Text measurement (cached; uses a hidden overlay with compute_bounds).
---------------------------------------------------------------------------
local measure_ov
local mcache, mcache_n = {}, 0
local res_w, res_h = 1920, 1080

-- Measure in the same coordinate space as the main overlay (1 unit = 1 OSD pixel).
function D.set_res(w, h)
    if w > 0 and h > 0 and (w ~= res_w or h ~= res_h) then
        res_w, res_h = w, h
        if measure_ov then measure_ov.res_x, measure_ov.res_y = w, h end
    end
end

function D.text_width(str, size, bold, font)
    str = tostring(str or "")
    if str == "" then return 0 end
    local key = (font or "") .. "|" .. size .. "|" .. (bold and 1 or 0) .. "|" .. str
    local v = mcache[key]
    if v then return v end
    if not measure_ov then
        measure_ov = mp.create_osd_overlay("ass-events")
        measure_ov.compute_bounds = true
        measure_ov.hidden = true
        measure_ov.res_x, measure_ov.res_y = res_w, res_h
    end
    measure_ov.data = string.format("{\\an7\\pos(0,0)\\fn%s\\fs%s\\b%d\\bord0\\shad0\\q2}%s",
        font or D.font, f(size), bold and 1 or 0, D.esc(str))
    local r = measure_ov:update()
    if r and r.x1 and r.x0 then
        v = r.x1 - r.x0
    else
        v = #str * size * 0.5
    end
    if mcache_n > 4000 then mcache, mcache_n = {}, 0 end
    mcache[key] = v
    mcache_n = mcache_n + 1
    return v
end

-- Shorten a string with an ellipsis to fit max_w.
function D.ellipsize(str, size, max_w, bold)
    str = tostring(str or "")
    if D.text_width(str, size, bold) <= max_w then return str end
    local chars = {}
    for ch in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    local lo, hi = 0, #chars
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if D.text_width(table.concat(chars, "", 1, mid) .. "…", size, bold) <= max_w then lo = mid else hi = mid - 1 end
    end
    return table.concat(chars, "", 1, lo) .. "…"
end

return D
