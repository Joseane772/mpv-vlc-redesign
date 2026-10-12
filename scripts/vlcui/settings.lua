-- Global settings window (modal) with categories, plus the keyboard shortcuts list.
local mp = require 'mp'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'

local St = { page = "general" }

St.pages = {
    { group = "App" },
    { "general", "General", "sliders" },
    { "interface", "Interface", "monitor-play" },
    { "controls", "Keyboard shortcuts", "keyboard" },
    { group = "Media" },
    { "playback", "Playback", "play" },
    { "seekbar", "Seekbar", "gauge" },
    { "media", "Video, audio & subtitles", "clapperboard" },
    { group = "System" },
    { "about", "About", "info" },
}

local L = {}

local function heading(text)
    local s = ctx.s
    L.y = L.y + 8 * s
    U.header(L.x, L.y + 14 * s, text, { size = 17 })
    L.y = L.y + 40 * s
end

local function row_label(text, cy, info, id)
    U.label(L.x, cy, text, { size = 15 })
    if info then U.info(id .. ":i", L.x + D.text_width(text, 15 * ctx.s) + 14 * ctx.s, cy, info) end
end

local function toggle(id, text, on, cb, info)
    local s = ctx.s
    local cy = L.y + 22 * s
    row_label(text, cy, info, id)
    U.toggle(id, L.x + L.w, cy, on, cb)
    L.y = L.y + 46 * s
end

local function seg(id, text, options, cur, cb, w, info)
    local s = ctx.s
    local cy = L.y + 22 * s
    row_label(text, cy, info, id)
    local bw = w or 300 * s
    U.segmented(id, L.x + L.w - bw, cy - 17 * s, bw, 34 * s, options, cur, cb)
    L.y = L.y + 50 * s
end

local function slider(id, text, value, min, max, fmt, cb, o)
    local s = ctx.s
    local cy = L.y + 22 * s
    row_label(text, cy, o and o.info, id)
    ctx.b:text(L.x + L.w, cy, string.format(fmt, value), { align = 6, size = 14 * s, color = D.T.text2 })
    local sw = 260 * s
    o = o or {}
    o.on_change = cb
    o.no_wheel = true
    U.slider(id, L.x + L.w - sw - 70 * s, cy - 8 * s, sw, 16 * s, value, min, max, o)
    L.y = L.y + 50 * s
end

local function page_general()
    local s, b = ctx.s, ctx.b
    heading("Appearance")
    -- accent swatches
    local cy = L.y + 22 * s
    row_label("Accent color", cy)
    local n = #D.accents
    local sz, gap = 30 * s, 8 * s
    local total = n * sz + (n - 1) * gap + 12 * s
    local x0 = L.x + L.w - total
    b:rect(x0, cy - sz / 2 - 6 * s, total, sz + 12 * s, { color = D.T.input, r = 6 * s })
    for i, a in ipairs(D.accents) do
        local sx = x0 + 6 * s + (i - 1) * (sz + gap)
        local id = "set:acc:" .. i
        local sel = a[2] == D.T.accent
        if sel then b:rect(sx - 3 * s, cy - sz / 2 - 3 * s, sz + 6 * s, sz + 6 * s, { color = D.mix(a[2], "000000", 0.65), r = 5 * s }) end
        local hov = ctx.hover == id
        local pad = hov and 4 * s or 6 * s
        b:rect(sx + pad, cy - sz / 2 + pad, sz - 2 * pad, sz - 2 * pad, { color = a[2], r = 2 * s })
        U.region(id, sx, cy - sz / 2, sz, sz, { click = function() ctx.api.set_accent(a[2]) end, tooltip = a[1] })
    end
    L.y = L.y + 54 * s
    slider("set:scale", "Interface size", media.setting("scale", 1), 0.75, 2, "%.2fx", function(v, final)
        if final then media.set_setting("scale", v) else ctx.pending_scale = v end
    end, { step = 0.05, default = 1, info = "Applied when you release the slider" })

    heading("Startup")
    toggle("set:resume", "Remember playback position", ctx.p["save-position-on-quit"] == true, function()
        mp.commandv("cycle", "save-position-on-quit")
    end, "Continue where you left off when reopening a file")
    toggle("set:resumep", "Show \"continue\" prompt", media.setting("resume_prompt", true), function()
        media.set_setting("resume_prompt", not media.setting("resume_prompt", true))
    end, "Shows a small prompt with a Start over button after resuming")
    toggle("set:autoload", "Queue the rest of the folder", media.setting("autoload", true), function()
        media.set_setting("autoload", not media.setting("autoload", true))
    end, "Opening one episode adds the other files in its folder to the queue")
end

local function page_interface()
    local s = ctx.s
    heading("Controls")
    toggle("set:paused", "Show controls while paused", media.setting("show_paused", false), function()
        media.set_setting("show_paused", not media.setting("show_paused", false))
    end)
    toggle("set:toasts", "Show keyboard shortcut messages", media.setting("toasts", true), function()
        media.set_setting("toasts", not media.setting("toasts", true))
    end, "Shows which key you pressed and what it did")
    toggle("set:remaining", "Show remaining time", media.setting("remaining", false), function()
        media.set_setting("remaining", not media.setting("remaining", false))
    end)
    seg("set:wheel", "Mouse wheel over video", {
        { label = "Volume", value = "volume" }, { label = "Seek", value = "seek" }, { label = "Nothing", value = "none" },
    }, media.setting("wheel", "volume"), function(v) media.set_setting("wheel", v) end)
    seg("set:click", "Click on video", {
        { label = "Nothing", value = "none" }, { label = "Play / Pause", value = "pause" },
    }, media.setting("click", "none"), function(v) media.set_setting("click", v) end, 240 * s)
    heading("Window")
    toggle("set:border", "Use system title bar", ctx.p.border == true, function() mp.commandv("cycle", "border") end,
        "Off = the redesigned title bar with its own window buttons")
    toggle("set:ontop", "Always on top", ctx.p.ontop == true, function() mp.commandv("cycle", "ontop") end)
end

local function page_playback()
    heading("Playback")
    toggle("set:keepopen", "Keep last frame when finished", ctx.p["keep-open"] ~= "no" and ctx.p["keep-open"] ~= false, function()
        mp.set_property("keep-open", (ctx.p["keep-open"] ~= "no" and ctx.p["keep-open"] ~= false) and "no" or "yes")
    end)
    toggle("set:hwdec", "Hardware decoding", (ctx.p.hwdec or "no") ~= "no", function()
        mp.set_property("hwdec", (ctx.p.hwdec or "no") ~= "no" and "no" or "auto-safe")
    end, "Uses the GPU to decode video. Turned off automatically when video filters need it.")
    toggle("set:pitch", "Keep audio pitch when changing speed", ctx.p["audio-pitch-correction"] ~= false, function()
        mp.commandv("cycle", "audio-pitch-correction")
    end)
    heading("Jumps")
    seg("set:jump", "Arrow key jump", {
        { label = "5 s", value = 5 }, { label = "10 s", value = 10 }, { label = "30 s", value = 30 },
    }, media.setting("jump", 10), function(v) media.set_setting("jump", v) end, 240 * ctx.s,
        "Used by the Left / Right arrow keys")
end

local function page_seekbar()
    heading("Seekbar")
    toggle("set:chap", "Show chapters", media.setting("chapters", true), function()
        media.set_setting("chapters", not media.setting("chapters", true))
    end)
    toggle("set:subtl", "Show subtitle timeline", media.setting("sub_timeline", false), function()
        media.set_setting("sub_timeline", not media.setting("sub_timeline", false))
    end, "Marks where subtitle lines appear")
    toggle("set:wave", "Show waveform", media.setting("waveform", false), function()
        media.set_setting("waveform", not media.setting("waveform", false))
    end, "Needs ffmpeg. Works best for music.")
    local tf = ctx.thumbfast
    local s = ctx.s
    local cy = L.y + 22 * s
    row_label("Thumbnail previews", cy)
    ctx.b:text(L.x + L.w, cy, (tf and tf.available) and "Enabled (thumbfast)" or "Install thumbfast.lua to enable",
        { align = 6, size = 14 * s, color = (tf and tf.available) and D.T.accent or D.T.text3 })
    L.y = L.y + 46 * s
end

local function page_media()
    local s = ctx.s
    heading("Per-file settings live in the sidebar")
    ctx.b:text(L.x, L.y + 10 * s, "Subtitle timing, fonts, audio delay, equalizer, video filters and more", { size = 14 * s, color = D.T.text2 })
    ctx.b:text(L.x, L.y + 32 * s, "are in the sidebar next to the video, so you can see what you change.", { size = 14 * s, color = D.T.text2 })
    L.y = L.y + 60 * s
    local tabs = { { "playback", "Playback", "play" }, { "video", "Video", "clapperboard" }, { "audio", "Audio", "audio-lines" }, { "subtitles", "Subtitles", "captions" } }
    for i, t in ipairs(tabs) do
        U.button("set:open:" .. t[1], L.x + (i - 1) * (L.w / 4), L.y, L.w / 4 - 8 * s, 40 * s, t[2], {
            icon = t[3], on_click = function() ctx.modal = nil; ctx.api.open_panel("settings", t[1]) end,
        })
    end
    L.y = L.y + 60 * s
    heading("Presets")
    local names = media.preset_names()
    if #names == 0 then
        ctx.b:text(L.x, L.y + 10 * s, "No presets saved yet. Use the preset menu at the bottom of the sidebar.", { size = 14 * s, color = D.T.text3 })
        L.y = L.y + 34 * s
    end
    for i, n in ipairs(names) do
        local folders = {}
        for dir, pn in pairs(media.store.folder_presets) do if pn == n then folders[#folders + 1] = media.basename(dir) end end
        local cy = L.y + 20 * s
        U.label(L.x, cy, n, { size = 15, color = D.T.text })
        if #folders > 0 then
            ctx.b:text(L.x + 200 * s, cy, "used in: " .. table.concat(folders, ", "), { size = 13 * s, color = D.T.text3, clip = { L.x, L.y, L.x + L.w - 50 * s, L.y + 40 * s } })
        end
        U.icon_button("set:pdel:" .. i, L.x + L.w - 14 * s, cy, "trash", { size = 15, tooltip = "Delete preset", on_click = function() media.delete_preset(n) end })
        L.y = L.y + 40 * s
    end
end

local function page_controls()
    local s, b = ctx.s, ctx.b
    heading("Keyboard shortcuts")
    -- user input.conf bindings (not mpv's built-in defaults); highest priority wins per key
    local best, order = {}, {}
    for _, bnd in ipairs(mp.get_property_native("input-bindings") or {}) do
        if not bnd.is_weak and bnd.section == "default" then
            local cur = best[bnd.key]
            if not cur then order[#order + 1] = bnd.key end
            if not cur or (bnd.priority or 0) >= (cur.priority or 0) then best[bnd.key] = bnd end
        end
    end
    local rows = {}
    for _, key in ipairs(order) do
        local bnd = best[key]
        if bnd.comment and bnd.comment ~= "" then rows[#rows + 1] = { ctx.pretty_key(key) or key, bnd.comment } end
    end
    if #rows == 0 then
        b:text(L.x, L.y + 10 * s, "No documented bindings found in input.conf", { size = 14 * s, color = D.T.text3 })
        L.y = L.y + 30 * s
    end
    for i, r in ipairs(rows) do
        local cy = L.y + 17 * s
        if i % 2 == 0 then b:rect(L.x - 8 * s, L.y, L.w + 16 * s, 34 * s, { color = "151515", r = 4 * s }) end
        local kw = D.text_width(r[1], 13 * s) + 16 * s
        b:rect(L.x, cy - 12 * s, kw, 24 * s, { color = D.T.surface, r = 4 * s, border = 1 * s, border_color = "333333" })
        b:text(L.x + kw / 2, cy, r[1], { align = 5, size = 13 * s, color = D.T.text })
        b:text(L.x + 170 * s, cy, r[2], { size = 14 * s, color = D.T.text2, clip = { L.x, L.y, L.x + L.w, L.y + 34 * s } })
        L.y = L.y + 34 * s
    end
    L.y = L.y + 10 * s
    b:text(L.x, L.y + 10 * s, "Edit input.conf in your mpv config folder to change them.", { size = 13 * s, color = D.T.text3 })
    L.y = L.y + 30 * s
end

local function page_about()
    local s, b = ctx.s, ctx.b
    b:cone(L.x + 30 * s, L.y + 40 * s, 56 * s, D.T.accent)
    b:text(L.x + 76 * s, L.y + 28 * s, "VLC Redesign for mpv", { size = 20 * s, color = D.T.text, bold = true })
    b:text(L.x + 76 * s, L.y + 54 * s, ctx.version_line or "", { size = 13 * s, color = D.T.text2 })
    L.y = L.y + 100 * s
    local lines = {
        "An mpv user interface based on the community VLC redesign by Juxtopposed",
        "(\"I Redesigned VLC After 25 Years\"). Not affiliated with VideoLAN.",
        "",
        "Icons: Lucide (ISC). Font: Inter (SIL OFL 1.1).",
        "Optional seekbar thumbnails: thumbfast by po5.",
    }
    for _, l in ipairs(lines) do
        b:text(L.x, L.y + 10 * s, l, { size = 14 * s, color = D.T.text2 })
        L.y = L.y + 24 * s
    end
end

function St.draw()
    local s, b = ctx.s, ctx.b
    local W, H = ctx.w, ctx.h
    b:rect(0, 0, W, H, { color = "000000", opacity = 0.55 })
    U.region("set:backdrop", 0, 0, W, H, { block = true, hover = false, click = function() ctx.modal = nil end, wheel = function() end })
    local w = math.min(940 * s, W - 32 * s)
    local h = math.min(660 * s, H - 32 * s)
    local x, y = (W - w) / 2, (H - h) / 2
    b:rect(x, y + 6 * s, w, h, { color = "000000", opacity = 0.6, r = 14 * s, blur = 18 * s })
    b:rect(x, y, w, h, { color = "0e0e0e", r = 12 * s, border = 1 * s, border_color = "262626" })
    U.region("set:win", x, y, w, h, { block = true, hover = false })

    -- nav
    local nw = math.min(260 * s, w * 0.34)
    b:rect(x + 10 * s, y + 10 * s, nw - 10 * s, h - 20 * s, { color = "161616", r = 8 * s })
    local ny = y + 22 * s
    for _, pg in ipairs(St.pages) do
        if pg.group then
            b:text(x + 30 * s, ny + 14 * s, pg.group, { size = 13 * s, color = D.T.text3 })
            ny = ny + 34 * s
        else
            local id = "set:nav:" .. pg[1]
            local active = St.page == pg[1]
            local hov = ctx.hover == id
            if active or hov then b:rect(x + 18 * s, ny, nw - 26 * s, 38 * s, { color = active and D.T.surface or "1c1c1c", r = 6 * s }) end
            b:icon(x + 40 * s, ny + 19 * s, pg[3], { size = 17 * s, color = active and D.T.accent or D.T.text2 })
            b:text(x + 62 * s, ny + 19 * s, pg[2], { size = 14 * s, color = (active or hov) and D.T.text or D.T.text2, clip = { x, ny, x + nw - 10 * s, ny + 38 * s } })
            U.region(id, x + 18 * s, ny, nw - 26 * s, 38 * s, { click = function() St.page = pg[1] end })
            ny = ny + 42 * s
        end
    end

    -- header
    local cx = x + nw + 20 * s
    local cw = w - nw - 40 * s
    local title
    for _, pg in ipairs(St.pages) do if pg[1] == St.page then title = pg[2] end end
    b:rect(x + nw + 1 * s, y + 1 * s, w - nw - 2 * s, 58 * s, { color = "090909", r = 0 })
    b:text(cx, y + 30 * s, (title or "") .. (St.page == "general" and " settings" or ""), { size = 17 * s, color = D.T.text })
    U.icon_button("set:close", x + w - 30 * s, y + 30 * s, "x", { size = 18, tooltip = "Close (Esc)", on_click = function() ctx.modal = nil end })

    -- page
    local py, ph = y + 60 * s, h - 70 * s
    local top = U.scroll_begin("set:page:" .. St.page, x + nw, py, w - nw, ph)
    L.x, L.w, L.y = cx, cw, top + 12 * s
    local page = ({
        general = page_general, interface = page_interface, playback = page_playback, seekbar = page_seekbar,
        media = page_media, controls = page_controls, about = page_about,
    })[St.page] or page_general
    page()
    U.scroll_end("set:page:" .. St.page, x + nw, py, w - nw, ph, L.y - top + 20 * s)
end

return St
