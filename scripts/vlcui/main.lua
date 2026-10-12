-- vlcui: a VLC-redesign inspired user interface for mpv.
-- Design: "I Redesigned VLC After 25 Years" by Juxtopposed (community Figma file).
local script_dir = mp.get_script_directory()
package.path = script_dir .. "/?.lua;" .. package.path

local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'
local menus = require 'menus'
local Bars = require 'bars'
local Sidebar = require 'sidebar'
local Queue = require 'queue'
local Library = require 'library'
local Settings = require 'settings'
local SubSearch = require 'subsearch'
local Rename = require 'rename'

local opts = {
    scale = 1.0,              -- base UI scale (multiplied by the display HiDPI scale)
    scale_fullscreen = 1.0,   -- extra scale in fullscreen
    accent = "",              -- default accent color (hex); the settings window overrides it
    hide_delay = 2.5,         -- seconds without mouse movement before the bars hide (mouse still near them)
    side_width = 380,         -- right sidebar width
    library_width = 360,      -- left library width
    shrink_video = true,      -- move the video aside when a side panel is open (instead of covering it)
    debug_size = "1280x720",  -- OSD size to assume when there is no window (headless testing)
    opensubtitles_api_key = "",   -- or set it in Settings → Subtitle downloads
    opensubtitles_username = "",  -- optional, raises the daily download limit
    opensubtitles_password = "",
    opensubtitles_api_url = "https://api.opensubtitles.com/api/v1",
}
options.read_options(opts, "vlcui", function() ctx.request_render() end)
ctx.opts = opts

media.load_store()
D.set_accent(media.setting("accent", opts.accent ~= "" and opts.accent or "d37918"))
ctx.version_line = (mp.get_property("mpv-version") or "mpv") .. "  ·  " .. (_VERSION or "Lua")

local overlay = mp.create_osd_overlay("ass-events")
local last_ass = ""

---------------------------------------------------------------------------
-- Render scheduling
---------------------------------------------------------------------------
local render -- forward
local render_pending = false

function ctx.request_render()
    if render_pending then return end
    render_pending = true
    mp.add_timeout(0, function()
        render_pending = false
        render()
    end)
end

local wake_timer
local function wake_at(t)
    local now = mp.get_time()
    local delay = math.max(0.02, t - now)
    if wake_timer then wake_timer:kill() end
    wake_timer = mp.add_timeout(delay, ctx.request_render)
end

---------------------------------------------------------------------------
-- Toasts ("Shift+R  Recording…")
---------------------------------------------------------------------------
local function pretty_key(k)
    if not k or k == "" then return nil end
    k = k:gsub("(%w+)", function(w)
        if #w == 1 then return w:upper() end
        local map = { ctrl = "Ctrl", shift = "Shift", alt = "Alt", meta = "Meta", space = "Space", right = "→", left = "←",
            up = "↑", down = "↓", esc = "Esc", enter = "Enter", pgup = "PgUp", pgdwn = "PgDn", bs = "Backspace", del = "Del",
            home = "Home", ["end"] = "End", tab = "Tab", menu = "Menu", sharp = "#", kp_add = "Num+", kp_subtract = "Num-" }
        return map[w:lower()] or (w:sub(1, 1):upper() .. w:sub(2))
    end)
    return k
end

ctx.pretty_key = pretty_key

function ctx.toast(key, msg, dur)
    if key and not media.setting("toasts", true) then return end
    ctx.toast_state = { key = pretty_key(key), msg = msg, untl = mp.get_time() + (dur or 1.6) }
    wake_at(ctx.toast_state.untl + 0.01)
    ctx.request_render()
end

---------------------------------------------------------------------------
-- Observed properties
---------------------------------------------------------------------------
local last_pos_draw = -1
local function on_prop(name, value)
    ctx.p[name] = value
    if name == "time-pos" then
        if not (ctx.show_bot or ctx.show_info) then return end
        local dur = ctx.p.duration or 0
        local v = value or 0
        local px = dur > 0 and math.floor(v / dur * ctx.w * 2) or 0
        local key = math.floor(v) * 100000 + px
        if key == last_pos_draw then return end
        last_pos_draw = key
    end
    ctx.request_render()
end

for _, pr in ipairs({
    { "pause", "bool" }, { "time-pos", "number" }, { "duration", "number" }, { "volume", "number" }, { "volume-max", "number" },
    { "mute", "bool" }, { "media-title", "string" }, { "path", "string" }, { "idle-active", "bool" }, { "fullscreen", "bool" },
    { "window-maximized", "bool" }, { "border", "bool" }, { "ontop", "bool" }, { "playlist", "native" }, { "playlist-pos", "number" },
    { "track-list", "native" }, { "chapter-list", "native" }, { "chapter", "number" }, { "aid", "native" }, { "sid", "native" },
    { "vid", "native" }, { "secondary-sid", "native" }, { "sub-delay", "number" }, { "audio-delay", "number" }, { "speed", "number" },
    { "sub-speed", "number" }, { "sub-scale", "number" }, { "sub-font-size", "number" }, { "sub-font", "string" },
    { "sub-color", "string" }, { "sub-outline-color", "string" }, { "sub-outline-size", "number" }, { "sub-pos", "number" },
    { "sub-back-color", "string" }, { "sub-border-style", "string" }, { "sub-bold", "bool" }, { "sub-ass-override", "string" },
    { "slang", "native" }, { "loop-file", "native" }, { "loop-playlist", "native" }, { "ab-loop-a", "native" }, { "ab-loop-b", "native" },
    { "video-rotate", "number" }, { "video-zoom", "number" }, { "video-aspect-override", "native" }, { "panscan", "number" },
    { "deinterlace", "native" }, { "tone-mapping", "string" }, { "brightness", "number" }, { "contrast", "number" },
    { "saturation", "number" }, { "gamma", "number" }, { "hue", "number" }, { "audio-device", "string" },
    { "audio-device-list", "native" }, { "demuxer-cache-state", "native" }, { "demuxer-via-network", "bool" },
    { "play-direction", "string" }, { "audio-pitch-correction", "bool" }, { "stream-record", "string" },
    { "save-position-on-quit", "bool" }, { "keep-open", "native" }, { "hwdec", "string" }, { "display-hidpi-scale", "number" },
    { "osd-dimensions", "native" }, { "focused", "bool" },
}) do
    mp.observe_property(pr[1], pr[2], on_prop)
end

---------------------------------------------------------------------------
-- API used by the components
---------------------------------------------------------------------------
local api = {}
ctx.api = api

function api.open_menu(items, x, y, o) menus.open(items, x, y, o) end

local function set_panel(name, tab)
    ctx.panel = name
    if tab then ctx.tab = tab end
    ctx.request_render()
end

function api.toggle_panel(name)
    if ctx.panel == name then set_panel(nil) else set_panel(name) end
end

function api.open_panel(name, tab) set_panel(name, tab) end

function api.toggle_library()
    ctx.library = not ctx.library
    if ctx.library then Library.on_open() end
    ctx.request_render()
end

function api.open_settings(page)
    menus.close()
    ctx.modal = "settings"
    if page then Settings.page = page end
    ctx.request_render()
end

function api.set_accent(hex)
    D.set_accent(hex)
    media.set_setting("accent", hex)
end

function api.open_dialog() media.open_dialog("replace") end

function api.open_subtitles(target, source) menus.close(); SubSearch.open(target, source) end
function api.rename_file(path) Rename.rename_file(path) end
function api.rename_folder(dir) menus.close(); Rename.open(dir) end

function api.add_bookmark()
    local t = media.add_bookmark()
    if t then ctx.toast("Ctrl+B", "Bookmark added at " .. media.fmt_time(t)) end
end

local function recent_items()
    local items = {}
    for i, e in ipairs(media.store.history) do
        if i > 12 then break end
        items[#items + 1] = {
            label = e.title or media.basename(e.path), hint = (e.dur and e.dur > 0) and media.fmt_time(e.dur) or nil,
            action = function() mp.commandv("loadfile", e.path, "replace") end,
        }
    end
    if #items == 0 then items[1] = { label = "Nothing yet", disabled = true } end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = "Clear recent", icon = "trash", action = media.clear_history }
    return items
end

local function open_items()
    return {
        { label = "Open file…", icon = "file-video", hint = "Ctrl+O", action = function() media.open_dialog("replace") end },
        { label = "Open folder…", icon = "folder-open", hint = "Ctrl+F", action = function() media.open_folder_dialog("replace") end },
        { label = "Open network stream…", icon = "radio", hint = "Ctrl+N", action = media.open_url },
        { label = "Play from clipboard", icon = "clipboard", hint = "Ctrl+V", action = media.paste_and_play },
        { label = "Open recent", icon = "history", submenu = recent_items },
        { separator = true },
        { label = "Add files to queue…", icon = "plus", action = function() media.open_dialog("append") end },
        { label = "Add subtitles…", icon = "captions", action = function() SubSearch.open("file", "local") end },
        { label = "Search subtitles online…", icon = "search", hint = "Alt+S", action = function() SubSearch.open("file", "online") end },
        { separator = true },
        { label = "Rename file…", icon = "type", hint = "F2", action = function() Rename.rename_file() end },
        { label = "Rename files in this folder…", icon = "folder", hint = "Shift+F2", action = function() Rename.open() end },
    }
end

function api.main_menu(x, y)
    local items = open_items()
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = "Library", icon = "panel-left", hint = "Ctrl+M", action = api.toggle_library }
    items[#items + 1] = { label = "Keyboard shortcuts", icon = "keyboard", hint = "F1", action = function() api.open_settings("controls") end }
    items[#items + 1] = { label = "Settings", icon = "settings", hint = "Ctrl+P", action = function() api.open_settings("general") end }
    items[#items + 1] = { label = "About", icon = "info", action = function() api.open_settings("about") end }
    menus.open(items, x, y, { id = "main", min_width = 250 * ctx.s })
end

local function speed_items()
    local items = {}
    for _, v in ipairs({ 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 }) do
        items[#items + 1] = {
            label = (v == 1) and "Normal" or (v .. "x"), checked = math.abs((ctx.p.speed or 1) - v) < 0.001,
            action = function() mp.set_property_number("speed", v) end,
        }
    end
    return items
end

local function sleep_items()
    local items = {}
    for _, it in ipairs({ { "Off", "off" }, { "15 minutes", "15" }, { "30 minutes", "30" }, { "1 hour", "60" }, { "End of current file", "eof" } }) do
        items[#items + 1] = { label = it[1], checked = media.sleep.mode == it[2], action = function() media.set_sleep(it[2]) end }
    end
    return items
end

local function jump_to_time()
    media.prompt("Jump to time (hh:mm:ss or seconds):", media.fmt_time(ctx.p["time-pos"] or 0), function(t)
        local total, n = 0, 0
        for part in (t or ""):gmatch("[%d%.]+") do total = total * 60 + (tonumber(part) or 0); n = n + 1 end
        if n > 0 then mp.commandv("seek", tostring(total), "absolute+exact") end
    end)
end

local function playback_items()
    local items = {
        { label = "Speed", icon = "gauge", submenu = speed_items },
        { label = "Jump forward", icon = "fast-forward", hint = "→", action = function() mp.commandv("seek", tostring(media.setting("jump", 10))) end },
        { label = "Jump backward", icon = "rewind", hint = "←", action = function() mp.commandv("seek", tostring(-media.setting("jump", 10))) end },
        { label = "Jump to time…", icon = "timer", hint = "Ctrl+T", action = jump_to_time },
        { label = "Next frame", icon = "skip-forward", hint = "E", action = function() mp.commandv("frame-step") end },
        { separator = true },
        { label = "Loop file", checked = ctx.p["loop-file"] ~= "no" and ctx.p["loop-file"] ~= false,
            action = function() mp.set_property("loop-file", (ctx.p["loop-file"] ~= "no" and ctx.p["loop-file"] ~= false) and "no" or "inf") end },
        { label = "A-B repeat", icon = "repeat-1", hint = "Shift+L", action = function() mp.commandv("ab-loop") end },
        { label = "Sleep timer", icon = "moon", submenu = sleep_items },
        { separator = true },
        { label = "Add bookmark", icon = "bookmark-plus", hint = "Ctrl+B", action = api.add_bookmark },
    }
    local chapters = ctx.p["chapter-list"] or {}
    if #chapters > 0 then
        local ch = {}
        for i, c in ipairs(chapters) do
            ch[#ch + 1] = { label = c.title or ("Chapter " .. i), hint = media.fmt_time(c.time), checked = (ctx.p.chapter == i - 1),
                action = function() mp.set_property_number("chapter", i - 1) end }
        end
        items[#items + 1] = { label = "Chapters", icon = "list-ordered", submenu = ch }
    end
    return items
end

local function video_items()
    local vt = { { label = "Disable", checked = ctx.p.vid == "no" or ctx.p.vid == false, action = function() mp.set_property("vid", "no") end } }
    for _, t in ipairs(media.tracks("video")) do
        vt[#vt + 1] = { label = media.track_label(t), checked = t.selected or false, action = function() media.select_track("video", t.id) end }
    end
    local aspects = {}
    for _, a in ipairs({ "no", "16:9", "4:3", "21:9", "2.35:1", "1:1" }) do
        aspects[#aspects + 1] = { label = a == "no" and "Default" or a, action = function() mp.set_property("video-aspect-override", a) end }
    end
    local rot = {}
    for _, r in ipairs({ 0, 90, 180, 270 }) do
        rot[#rot + 1] = { label = r .. "°", checked = (ctx.p["video-rotate"] or 0) == r, action = function() mp.set_property_number("video-rotate", r) end }
    end
    return {
        { label = "Video track", icon = "film", submenu = vt },
        { label = "Fullscreen", checked = ctx.p.fullscreen == true, hint = "F", action = function() mp.commandv("cycle", "fullscreen") end },
        { label = "Always on top", checked = ctx.p.ontop == true, action = function() mp.commandv("cycle", "ontop") end },
        { label = "Mini player", checked = media.mini ~= nil, action = media.toggle_mini },
        { separator = true },
        { label = "Aspect ratio", icon = "scan", hint = "A", submenu = aspects },
        { label = "Rotate", icon = "rotate-cw", submenu = rot },
        { label = "Zoom in", icon = "zoom-in", hint = "Z", action = function() mp.commandv("add", "video-zoom", "0.1") end },
        { label = "Reset zoom", action = function() mp.set_property_number("video-zoom", 0); mp.set_property_number("panscan", 0) end },
        { label = "Deinterlace", checked = ctx.p.deinterlace == true or ctx.p.deinterlace == "yes", hint = "D", action = function() mp.commandv("cycle", "deinterlace") end },
        { separator = true },
        { label = "Take snapshot", icon = "camera", hint = "Shift+S", action = function() mp.commandv("screenshot") end },
    }
end

local function playlist_items()
    local lp = ctx.p["loop-playlist"]
    local looping = lp and lp ~= "no" and lp ~= false
    return {
        { label = "Show queue", icon = "list", hint = "Ctrl+L", action = function() api.open_panel("queue") end },
        { label = "Show library", icon = "panel-left", action = api.toggle_library },
        { separator = true },
        { label = "Shuffle", icon = "shuffle", hint = "R", action = function() mp.commandv("playlist-shuffle") end },
        { label = "Repeat queue", checked = looping, action = function() mp.set_property("loop-playlist", looping and "no" or "inf") end },
        { label = "Save queue as playlist…", icon = "list-music", action = media.save_queue_as_playlist },
        { label = "Clear queue", icon = "trash", action = function() mp.commandv("playlist-clear") end },
    }
end

local function settings_items()
    return {
        { label = "Playback", icon = "play", action = function() api.open_panel("settings", "playback") end },
        { label = "Video", icon = "clapperboard", action = function() api.open_panel("settings", "video") end },
        { label = "Audio", icon = "audio-lines", action = function() api.open_panel("settings", "audio") end },
        { label = "Subtitles", icon = "captions", action = function() api.open_panel("settings", "subtitles") end },
        { separator = true },
        { label = "Media info", icon = "info", hint = "I", checked = ctx.show_info or false, action = function() ctx.show_info = not ctx.show_info end },
        { label = "Keyboard shortcuts", icon = "keyboard", hint = "F1", action = function() api.open_settings("controls") end },
        { label = "Advanced settings", icon = "settings", hint = "Ctrl+P", action = function() api.open_settings("general") end },
    }
end

local function toggle_ui()
    ctx.ui_hidden = not ctx.ui_hidden
    menus.close()
    if ctx.ui_hidden then
        ctx.panel, ctx.library, ctx.modal = nil, false, nil
        ctx.toast("Ctrl+\\", "Interface hidden. Press Ctrl+\\ to bring it back", 2.5)
    else
        ctx.toast("Ctrl+\\", "Interface visible")
    end
end

function api.context_menu(x, y)
    local paused = ctx.p.pause
    local recording = (ctx.p["stream-record"] or "") ~= ""
    menus.open({
        { label = paused and "Play" or "Pause", icon = paused and "play" or "pause", hint = "Space", action = function() mp.commandv("cycle", "pause") end },
        { label = "Stop", icon = "stop", hint = "S", action = function() mp.commandv("stop", "keep-playlist") end },
        { label = "Previous item", icon = "skip-back", hint = "P", action = function() mp.commandv("playlist-prev") end },
        { label = "Next item", icon = "skip-forward", hint = "N", action = function() mp.commandv("playlist-next") end },
        { label = recording and "Stop recording" or "Record", icon = "record", icon_color = recording and "e8504a" or nil, hint = "Shift+R", action = media.toggle_record },
        { label = ctx.ui_hidden and "Show UI" or "Hide UI", icon = "eye-off", hint = "Ctrl+\\", action = toggle_ui },
        { separator = true },
        { label = "Playback", icon = "gauge", submenu = playback_items },
        { label = "Video", icon = "clapperboard", submenu = video_items },
        { label = "Audio", icon = "audio-lines", submenu = Bars.audio_menu_items },
        { label = "Subtitle", icon = "captions", submenu = Bars.sub_menu_items },
        { label = "More settings", icon = "settings", submenu = settings_items },
        { label = "Playlist", icon = "list", submenu = playlist_items },
        { label = "Open media", icon = "folder-open", submenu = open_items },
        { separator = true },
        { label = "Quit", icon = "log-out", hint = "Ctrl+Q", action = function() mp.commandv("quit") end },
    }, x, y, { id = "context", min_width = 250 * ctx.s })
end

---------------------------------------------------------------------------
-- Overlays: home screen, resume prompt, media info, toast, tooltip
---------------------------------------------------------------------------
local function draw_home(x, y, w, h)
    local s, b = ctx.s, ctx.b
    b:rect(x, y, w, h, { color = "0b0b0b" })
    U.region("home:bg", x, y, w, h, { hover = false })
    local cx = x + w / 2
    local hist = media.store.history
    local list_n = math.min(#hist, 4)
    local block_h = 250 * s + (list_n > 0 and (50 * s + list_n * 52 * s) or 0)
    local top = y + math.max(20 * s, (h - block_h) / 2)
    b:cone(cx, top + 50 * s, 92 * s, D.T.accent)
    b:text(cx, top + 122 * s, "Drop media here, or", { align = 5, size = 15 * s, color = D.T.text2 })
    local bw, bh, gap = 150 * s, 38 * s, 10 * s
    local bx = cx - (bw * 3 + gap * 2) / 2
    U.button("home:file", bx, top + 148 * s, bw, bh, "Open file", { icon = "file-video", on_click = function() media.open_dialog("replace") end, primary = true })
    U.button("home:folder", bx + bw + gap, top + 148 * s, bw, bh, "Open folder", { icon = "folder-open", on_click = function() media.open_folder_dialog("replace") end })
    U.button("home:url", bx + 2 * (bw + gap), top + 148 * s, bw, bh, "Network stream", { icon = "radio", on_click = media.open_url })
    if list_n > 0 then
        local ly = top + 220 * s
        local lw = math.min(560 * s, w - 40 * s)
        local lx = cx - lw / 2
        b:text(lx, ly + 10 * s, "Continue watching", { size = 15 * s, color = D.T.text, bold = true })
        ly = ly + 34 * s
        for i = 1, list_n do
            local e = hist[i]
            local id = "home:h:" .. i
            local hov = ctx.hover == id
            b:rect(lx, ly, lw, 46 * s, { color = hov and D.T.surface or "141414", r = 6 * s })
            b:icon(lx + 22 * s, ly + 23 * s, media.is_url(e.path) and "link" or "film", { size = 17 * s, color = hov and D.T.accent or D.T.text2 })
            b:text(lx + 44 * s, ly + 17 * s, e.title or media.basename(e.path), { size = 14 * s, color = D.T.text, clip = { lx, ly, lx + lw - 90 * s, ly + 46 * s } })
            local dir = media.dirname(e.path)
            b:text(lx + 44 * s, ly + 33 * s, dir and media.basename(dir) or e.path, { size = 12 * s, color = D.T.text3, clip = { lx, ly, lx + lw - 90 * s, ly + 46 * s } })
            if e.dur and e.dur > 0 then
                b:text(lx + lw - 14 * s, ly + 23 * s, media.fmt_time(e.pos or 0) .. " / " .. media.fmt_time(e.dur), { align = 6, size = 12 * s, color = D.T.text3 })
                b:rect(lx + 8 * s, ly + 46 * s - 3 * s, (lw - 16 * s) * U.clamp((e.pos or 0) / e.dur, 0, 1), 2 * s, { color = D.T.accent })
            end
            U.region(id, lx, ly, lw, 46 * s, { click = function() mp.commandv("loadfile", e.path, "replace") end, tooltip = e.path })
            ly = ly + 52 * s
        end
    end
end

local function draw_resume(bottom_y)
    local r = ctx.resume
    if not r then return end
    local now = mp.get_time()
    if now > r.untl and ctx.hover ~= "resume:start" and ctx.hover ~= "resume:x" then ctx.resume = nil; return end
    local s, b = ctx.s, ctx.b
    local msg = "Continuing from " .. media.fmt_time(r.t)
    local tw = D.text_width(msg, 14 * s)
    local w, h = tw + 190 * s, 46 * s
    local x, y = (ctx.w - w) / 2, bottom_y - h - 16 * s
    b:rect(x, y + 3 * s, w, h, { color = "000000", opacity = 0.45, r = 8 * s, blur = 8 * s })
    b:rect(x, y, w, h, { color = D.T.bar, r = 8 * s, border = 1 * s, border_color = "2c2c2c" })
    b:icon(x + 22 * s, y + h / 2, "history", { size = 16 * s, color = D.T.accent })
    b:text(x + 40 * s, y + h / 2, msg, { size = 14 * s, color = D.T.text })
    U.button("resume:start", x + w - 140 * s, y + 8 * s, 98 * s, h - 16 * s, "Start over", {
        size = 13, primary = true, on_click = function() mp.commandv("seek", "0", "absolute"); ctx.resume = nil end,
    })
    U.icon_button("resume:x", x + w - 22 * s, y + h / 2, "x", { size = 14, box = 24, on_click = function() ctx.resume = nil end })
    wake_at(math.min(r.untl, now + 1))
end

local function draw_info(top_y)
    local s, b = ctx.s, ctx.b
    local lines = media.media_info_lines()
    if #lines == 0 then return end
    local kw, vw = 0, 0
    for _, l in ipairs(lines) do
        kw = math.max(kw, D.text_width(l[1], 13 * s))
        vw = math.max(vw, math.min(420 * s, D.text_width(l[2], 13 * s)))
    end
    local w = kw + vw + 44 * s
    local h = #lines * 22 * s + 20 * s
    local x, y = 16 * s, top_y + 16 * s
    b:rect(x, y, w, h, { color = D.T.bar, opacity = 0.92, r = 8 * s })
    for i, l in ipairs(lines) do
        local ly = y + 10 * s + (i - 0.5) * 22 * s
        b:text(x + 14 * s, ly, l[1], { size = 13 * s, color = D.T.text3 })
        b:text(x + 30 * s + kw, ly, l[2], { size = 13 * s, color = D.T.text, clip = { x, y, x + w - 10 * s, y + h } })
    end
    U.region("info:card", x, y, w, h, { block = true, hover = false })
end

local function draw_toast(top_y)
    local t = ctx.toast_state
    if not t then return end
    if mp.get_time() > t.untl then ctx.toast_state = nil; return end
    local s, b = ctx.s, ctx.b
    local ksz, msz = 12 * s, 14 * s
    local kw = t.key and (D.text_width(t.key, ksz, true) + 16 * s) or 0
    local mw = D.text_width(t.msg, msz)
    local w = mw + 28 * s + (t.key and kw + 10 * s or 0)
    local h = 36 * s
    local x, y = (ctx.w - w) / 2, top_y + 18 * s
    b:rect(x, y + 3 * s, w, h, { color = "000000", opacity = 0.4, r = 7 * s, blur = 6 * s })
    b:rect(x, y, w, h, { color = D.T.bar, opacity = 0.97, r = 7 * s, border = 1 * s, border_color = "2c2c2c" })
    local tx = x + 14 * s
    if t.key then
        b:rect(x + 7 * s, y + 7 * s, kw, h - 14 * s, { color = D.T.accent_dim, r = 4 * s })
        b:text(x + 7 * s + kw / 2, y + h / 2, t.key, { align = 5, size = ksz, color = D.T.accent, bold = true })
        tx = x + 17 * s + kw
    end
    b:text(tx, y + h / 2, t.msg, { size = msz, color = D.T.text })
end

local function draw_tooltip()
    local r = ctx.hover_region
    if not r or not r.tooltip or ctx.drag or not ctx.mouse.inside then return end
    local now = mp.get_time()
    local since = ctx.hover_since or now
    if now - since < 0.5 then
        wake_at(since + 0.5)
        return
    end
    local s, b = ctx.s, ctx.b
    local size = 13 * s
    local text = D.ellipsize(r.tooltip, size, 460 * s)
    local w, h = D.text_width(text, size) + 18 * s, 28 * s
    local cx = (r.x1 + r.x2) / 2
    local y
    if r.y1 > ctx.h / 2 then y = r.y1 - h - 8 * s else y = r.y2 + 8 * s end
    if r.y2 - r.y1 > 60 * s then y = ctx.mouse.y + 22 * s end
    local x = U.clamp(cx - w / 2, 6 * s, ctx.w - w - 6 * s)
    y = U.clamp(y, 4 * s, ctx.h - h - 4 * s)
    b:rect(x, y, w, h, { color = "262626", r = 5 * s, border = 1 * s, border_color = "333333" })
    b:text(x + w / 2, y + h / 2, text, { align = 5, size = size, color = D.T.text })
end

---------------------------------------------------------------------------
-- Visibility + layout
---------------------------------------------------------------------------
local margins_key = ""
local function set_margins(l, r, t, bm)
    local key = string.format("%.4f|%.4f|%.4f|%.4f", l, r, t, bm)
    if key == margins_key then return end
    margins_key = key
    mp.set_property_number("video-margin-ratio-left", l)
    mp.set_property_number("video-margin-ratio-right", r)
    mp.set_property_number("video-margin-ratio-top", t)
    mp.set_property_number("video-margin-ratio-bottom", bm)
end

local function compute_scale()
    local hidpi = ctx.p["display-hidpi-scale"] or 1
    if hidpi <= 0 then hidpi = 1 end
    local base = ctx.pending_scale or media.setting("scale", opts.scale)
    local s = base * hidpi * (ctx.p.fullscreen and opts.scale_fullscreen or 1)
    -- shrink a little on small windows so the bars still fit
    local fit = ctx.w / (760 * s)
    if fit < 1 then s = s * math.max(0.6, fit) end
    return s
end

local function compute_visibility()
    local m, s = ctx.mouse, ctx.s
    local now = mp.get_time()
    local idle = ctx.p["idle-active"]
    local pinned = ctx.panel or ctx.library or ctx.modal or #ctx.menus > 0 or ctx.drag ~= nil or idle
    local recent = (now - (ctx.last_move or 0)) < opts.hide_delay
    local over_bar = m.inside and (m.y < Bars.top_h() or m.y > ctx.h - Bars.bot_h())
    local top_zone = m.inside and m.y < Bars.top_h() + 50 * s and (recent or over_bar)
    local bot_zone = m.inside and m.y > ctx.h - Bars.bot_h() - 80 * s and (recent or over_bar)
    local reveal = now < (ctx.reveal_until or 0)
    ctx.show_top = not ctx.ui_hidden and (pinned or top_zone or reveal) and true or false
    ctx.show_bot = not ctx.ui_hidden and (pinned or bot_zone or reveal or ctx.resume ~= nil
        or (ctx.p.pause and media.setting("show_paused", false))) and true or false
    if m.inside and recent and (top_zone or bot_zone) and not over_bar then
        wake_at((ctx.last_move or now) + opts.hide_delay + 0.05)
    end
    if reveal then wake_at(ctx.reveal_until + 0.05) end
end

local esc_bound = false
local function sync_esc()
    local need = #ctx.menus > 0 or ctx.modal or ctx.panel or ctx.library
    if need and not esc_bound then
        mp.add_forced_key_binding("ESC", "vlcui-esc", function()
            if #ctx.menus > 0 then menus.close()
            elseif ctx.modal then ctx.modal = nil
            elseif ctx.panel then ctx.panel = nil
            elseif ctx.library then ctx.library = false end
            ctx.request_render()
        end)
        esc_bound = true
    elseif not need and esc_bound then
        mp.remove_key_binding("vlcui-esc")
        esc_bound = false
    end
end

local function update_hover()
    local m = ctx.mouse
    local r = m.inside and U.hit(m.x, m.y) or nil
    if r and r.hover == false then r = nil end
    local id = r and r.id or nil
    if id ~= ctx.hover then
        ctx.hover = id
        ctx.hover_region = r
        ctx.hover_since = mp.get_time()
        return true
    end
    ctx.hover_region = r
    return false
end

local hover_rerenders = 0
render = function()
    local dims = ctx.p["osd-dimensions"]
    local w, h = dims and dims.w or 0, dims and dims.h or 0
    if w <= 0 or h <= 0 then
        local dw, dh = opts.debug_size:match("(%d+)x(%d+)")
        w, h = tonumber(dw) or 0, tonumber(dh) or 0
        if w <= 0 then return end
    end
    ctx.w, ctx.h = w, h
    D.set_res(w, h)
    ctx.s = compute_scale()
    ctx.b = D.builder()
    ctx.regions = {}
    ctx.clip_stack = {}
    local s = ctx.s
    compute_visibility()

    local top_h = ctx.show_top and Bars.top_h() or 0
    local bot_h = ctx.show_bot and Bars.bot_h() or 0
    local lw = ctx.library and math.min(opts.library_width * s, w * 0.45) or 0
    local rw = ctx.panel and math.min(opts.side_width * s, w * 0.48) or 0
    if (ctx.panel or ctx.library) and opts.shrink_video then
        set_margins(lw / w, rw / w, top_h / h, bot_h / h)
    else
        set_margins(0, 0, 0, 0)
    end

    if not ctx.ui_hidden then
        if ctx.p["idle-active"] then draw_home(lw, top_h, w - lw - rw, h - top_h - bot_h) end
        if ctx.show_info and not ctx.p["idle-active"] then draw_info(top_h) end
        if ctx.library then Library.draw(0, top_h, lw, h - top_h - bot_h) end
        if ctx.panel == "settings" then Sidebar.draw(w - rw, top_h, rw, h - top_h - bot_h)
        elseif ctx.panel == "queue" then Queue.draw(w - rw, top_h, rw, h - top_h - bot_h) end
        if ctx.show_top then Bars.draw_top() end
        if ctx.show_bot then Bars.draw_bottom() else Bars.clear_thumb() end
        draw_resume(h - bot_h)
        if ctx.modal == "settings" then Settings.draw()
        elseif ctx.modal == "subs" then SubSearch.draw()
        elseif ctx.modal == "rename" then Rename.draw() end
    else
        Bars.clear_thumb()
    end
    menus.render()
    draw_toast(top_h)
    draw_tooltip()

    last_ass = ctx.b:result()
    overlay.res_x, overlay.res_y = w, h
    overlay.data = last_ass
    overlay:update()
    sync_esc()

    if update_hover() then
        hover_rerenders = hover_rerenders + 1
        if hover_rerenders < 3 then ctx.request_render() end
    else
        hover_rerenders = 0
    end
end

---------------------------------------------------------------------------
-- Mouse input
---------------------------------------------------------------------------
local function begin_window_drag()
    if not ctx.p.fullscreen then mp.commandv("begin-vo-dragging") end
end

local function mouse_down()
    local m = ctx.mouse
    local r = U.hit(m.x, m.y, nil)
    while r and not (r.click or r.drag_start or r.block or r.drag_window or r.rclick) do
        -- skip passive regions (hover-only) by looking further down the stack
        local idx
        for i = #ctx.regions, 1, -1 do if ctx.regions[i] == r then idx = i end end
        r = nil
        for i = (idx or 1) - 1, 1, -1 do
            local q = ctx.regions[i]
            if m.x >= q.x1 and m.x < q.x2 and m.y >= q.y1 and m.y < q.y2 and (q.click or q.drag_start or q.block or q.drag_window) then r = q; break end
        end
    end
    if r and r.drag_start then
        ctx.drag = r
        if r.drag_threshold then
            r.pending = true
            r.x0, r.y0 = m.x, m.y
        else
            r.drag_start(m.x, m.y)
        end
        ctx.request_render()
        return
    end
    if r and r.click then
        ctx.pressed = r.id
        return
    end
    if r and r.drag_window then
        begin_window_drag()
        return
    end
    if r then return end -- blocking region (panel background etc.)
    -- plain video area
    if media.setting("click", "none") == "pause" and not ctx.p["idle-active"] then mp.commandv("cycle", "pause") end
    begin_window_drag()
end

local function mouse_up()
    local m = ctx.mouse
    if ctx.drag then
        local r = ctx.drag
        ctx.drag = nil
        if r.pending then
            r.pending = false
            if r.click then r.click() end
        elseif r.drag_end then
            r.drag_end(m.x, m.y)
        end
        ctx.request_render()
        return
    end
    if ctx.pressed then
        local id = ctx.pressed
        ctx.pressed = nil
        local r = U.hit(m.x, m.y, "click")
        if r and r.id == id and r.click then
            r.click()
            ctx.request_render()
        end
    end
end

mp.add_forced_key_binding("mbtn_left", "vlcui-mbtn-left", function(e)
    if e.event == "down" then mouse_down()
    elseif e.event == "up" then mouse_up()
    elseif e.event == "press" then mouse_down(); mouse_up() end
end, { complex = true })

mp.add_forced_key_binding("mbtn_left_dbl", "vlcui-mbtn-left-dbl", function()
    local m = ctx.mouse
    local r = U.hit(m.x, m.y, nil)
    if r then
        if r.dbl then r.dbl() end
        return
    end
    mp.commandv("cycle", "fullscreen")
end)

mp.add_forced_key_binding("mbtn_right", "vlcui-mbtn-right", function()
    local m = ctx.mouse
    local r = U.hit(m.x, m.y, "rclick")
    if r and r.rclick then
        r.rclick()
        ctx.request_render()
        return
    end
    if r and r.block and r.id ~= "home:bg" then return end
    menus.close()
    api.context_menu(m.x, m.y)
end)

local function wheel(dir)
    local m = ctx.mouse
    local r = U.hit(m.x, m.y, "wheel")
    if r then
        if r.wheel then r.wheel(dir) end
        ctx.request_render()
        return
    end
    local mode = media.setting("wheel", "volume")
    if mode == "volume" then
        mp.commandv("add", "volume", tostring(dir * 5))
        ctx.toast(nil, "Volume " .. math.floor((mp.get_property_number("volume") or 0) + 0.5) .. "%", 0.9)
    elseif mode == "seek" then
        mp.commandv("seek", tostring(dir * 5))
    end
end
mp.add_forced_key_binding("wheel_up", "vlcui-wheel-up", function() wheel(1) end, { repeatable = true })
mp.add_forced_key_binding("wheel_down", "vlcui-wheel-down", function() wheel(-1) end, { repeatable = true })

mp.observe_property("mouse-pos", "native", function(_, mp_)
    if not mp_ or ctx.mouse_locked then return end
    local m = ctx.mouse
    local moved = math.abs((mp_.x or 0) - m.x) > 0.5 or math.abs((mp_.y or 0) - m.y) > 0.5
    m.x, m.y = mp_.x or -1, mp_.y or -1
    m.inside = mp_.hover ~= false
    if moved then ctx.last_move = mp.get_time() end
    local r = ctx.drag
    if r then
        if r.pending then
            if math.abs(m.x - r.x0) + math.abs(m.y - r.y0) > (r.drag_threshold or 0) then
                r.pending = false
                if r.drag_start then r.drag_start(m.x, m.y) end
            end
        elseif r.drag_move then
            r.drag_move(m.x, m.y)
        end
    end
    ctx.request_render()
end)

---------------------------------------------------------------------------
-- Key bindings (keys live in input.conf as "script-binding vlcui/<name>")
---------------------------------------------------------------------------
local function bind(name, fn)
    mp.add_key_binding(nil, name, function(e)
        if e and e.event == "up" then return end
        fn(e and e.key_name or nil, e)
    end, { complex = true, repeatable = true })
end

local function reveal(sec)
    ctx.reveal_until = mp.get_time() + (sec or 1.5)
    ctx.request_render()
end

bind("play-pause", function(k)
    if ctx.p["idle-active"] then return media.open_dialog("replace") end
    mp.commandv("cycle", "pause")
    ctx.toast(k, mp.get_property_bool("pause") and "Paused" or "Playing")
end)
bind("stop", function(k) mp.commandv("stop", "keep-playlist"); ctx.toast(k, "Stopped") end)
bind("next", function(k) mp.commandv("playlist-next"); ctx.toast(k, "Next item") end)
bind("prev", function(k) mp.commandv("playlist-prev"); ctx.toast(k, "Previous item") end)
bind("fullscreen", function() mp.commandv("cycle", "fullscreen") end)
bind("mute", function(k) mp.commandv("cycle", "mute"); ctx.toast(k, mp.get_property_bool("mute") and "Muted" or "Unmuted") end)
bind("volume-up", function(k) mp.commandv("add", "volume", "5"); ctx.toast(k, "Volume " .. math.floor(mp.get_property_number("volume", 0) + 0.5) .. "%", 0.9) end)
bind("volume-down", function(k) mp.commandv("add", "volume", "-5"); ctx.toast(k, "Volume " .. math.floor(mp.get_property_number("volume", 0) + 0.5) .. "%", 0.9) end)
local function jump(k, sec)
    mp.commandv("seek", tostring(sec))
    ctx.toast(k, (sec > 0 and "Forward " or "Back ") .. math.abs(sec) .. " s", 0.9)
    reveal()
end
bind("jump-forward", function(k) jump(k, media.setting("jump", 10)) end)
bind("jump-back", function(k) jump(k, -media.setting("jump", 10)) end)
bind("jump-forward-short", function(k) jump(k, 3) end)
bind("jump-back-short", function(k) jump(k, -3) end)
bind("jump-forward-long", function(k) jump(k, 60) end)
bind("jump-back-long", function(k) jump(k, -60) end)
bind("speed-up", function(k) mp.commandv("multiply", "speed", "1.1"); ctx.toast(k, string.format("Speed %.2fx", mp.get_property_number("speed", 1))) end)
bind("speed-down", function(k) mp.commandv("multiply", "speed", "1/1.1"); ctx.toast(k, string.format("Speed %.2fx", mp.get_property_number("speed", 1))) end)
bind("speed-reset", function(k) mp.set_property_number("speed", 1); ctx.toast(k, "Speed 1.00x") end)
bind("frame-step", function(k) mp.commandv("frame-step"); ctx.toast(k, "Next frame") end)
bind("frame-back-step", function(k) mp.commandv("frame-back-step"); ctx.toast(k, "Previous frame") end)
bind("show-time", function(k)
    ctx.toast(k, media.fmt_time(mp.get_property_number("time-pos", 0)) .. " / " .. media.fmt_time(mp.get_property_number("duration", 0)), 2)
    reveal(2)
end)
local function delay_toast(k, prop, label)
    ctx.toast(k, string.format("%s %+d ms", label, math.floor(mp.get_property_number(prop, 0) * 1000 + 0.5)))
end
bind("sub-delay-down", function(k) mp.commandv("add", "sub-delay", "-0.05"); delay_toast(k, "sub-delay", "Subtitle delay") end)
bind("sub-delay-up", function(k) mp.commandv("add", "sub-delay", "0.05"); delay_toast(k, "sub-delay", "Subtitle delay") end)
bind("audio-delay-down", function(k) mp.commandv("add", "audio-delay", "-0.05"); delay_toast(k, "audio-delay", "Audio delay") end)
bind("audio-delay-up", function(k) mp.commandv("add", "audio-delay", "0.05"); delay_toast(k, "audio-delay", "Audio delay") end)
local function cycle_track(k, kind, prop)
    mp.commandv("cycle", prop)
    local t = media.current_track(kind)
    ctx.toast(k, (kind == "sub" and "Subtitles: " or "Audio: ") .. (t and media.track_label(t) or "Off"))
end
bind("cycle-sub", function(k) cycle_track(k, "sub", "sid") end)
bind("cycle-audio", function(k) cycle_track(k, "audio", "aid") end)
bind("cycle-aspect", function(k)
    local list = { "no", "16:9", "4:3", "21:9", "2.35:1", "1:1" }
    ctx.aspect_i = ((ctx.aspect_i or 1) % #list) + 1
    mp.set_property("video-aspect-override", list[ctx.aspect_i])
    ctx.toast(k, "Aspect ratio: " .. (list[ctx.aspect_i] == "no" and "Default" or list[ctx.aspect_i]))
end)
bind("zoom-in", function(k) mp.commandv("add", "video-zoom", "0.1"); ctx.toast(k, string.format("Zoom %.2fx", 2 ^ mp.get_property_number("video-zoom", 0))) end)
bind("zoom-out", function(k) mp.commandv("add", "video-zoom", "-0.1"); ctx.toast(k, string.format("Zoom %.2fx", 2 ^ mp.get_property_number("video-zoom", 0))) end)
bind("deinterlace", function(k) mp.commandv("cycle", "deinterlace"); ctx.toast(k, "Deinterlace " .. (mp.get_property_bool("deinterlace") and "on" or "off")) end)
bind("snapshot", function(k) mp.commandv("screenshot"); ctx.toast(k, "Snapshot saved") end)
bind("loop", function(k)
    local lf = mp.get_property("loop-file")
    local lp = mp.get_property("loop-playlist")
    if lf ~= "no" then
        mp.set_property("loop-file", "no"); mp.set_property("loop-playlist", "no"); ctx.toast(k, "Repeat off")
    elseif lp ~= "no" then
        mp.set_property("loop-playlist", "no"); mp.set_property("loop-file", "inf"); ctx.toast(k, "Repeat this file")
    else
        mp.set_property("loop-playlist", "inf"); ctx.toast(k, "Repeat queue")
    end
end)
bind("ab-loop", function(k)
    mp.commandv("ab-loop")
    local a, z = mp.get_property_number("ab-loop-a"), mp.get_property_number("ab-loop-b")
    ctx.toast(k, (a and z) and ("A-B repeat " .. media.fmt_time(a) .. " → " .. media.fmt_time(z)) or (a and "A-B repeat: A set" or "A-B repeat off"))
    reveal()
end)
bind("shuffle", function(k) mp.commandv("playlist-shuffle"); ctx.toast(k, "Queue shuffled") end)
bind("record", function() media.toggle_record() end)
bind("bookmark", function() api.add_bookmark() end)
bind("jump-to-time", function() jump_to_time() end)
bind("media-info", function(k) ctx.show_info = not ctx.show_info; ctx.toast(k, ctx.show_info and "Media info on" or "Media info off") end)
bind("toggle-ui", function() toggle_ui() end)
bind("toggle-library", function() api.toggle_library() end)
bind("toggle-queue", function() api.toggle_panel("queue") end)
bind("toggle-sidebar", function() api.toggle_panel("settings") end)
bind("settings", function() if ctx.modal then ctx.modal = nil; ctx.request_render() else api.open_settings("general") end end)
bind("shortcuts", function() if ctx.modal then ctx.modal = nil; ctx.request_render() else api.open_settings("controls") end end)
bind("open-file", function() media.open_dialog("replace") end)
bind("open-folder", function() media.open_folder_dialog("replace") end)
bind("open-url", function() media.open_url() end)
bind("paste", function() media.paste_and_play() end)
bind("add-subtitle", function() SubSearch.open("file", "local") end)
bind("search-subtitles", function() SubSearch.open("file", "online") end)
bind("rename-file", function() Rename.rename_file() end)
bind("rename-folder", function() Rename.open() end)
bind("mini-player", function() media.toggle_mini() end)
bind("context-menu", function() api.context_menu(ctx.w / 2 - 120 * ctx.s, ctx.h / 3) end)
bind("main-menu", function() api.main_menu(46 * ctx.s, Bars.top_h() + 4 * ctx.s) end)
bind("quit", function() mp.commandv("quit") end)

---------------------------------------------------------------------------
-- File events
---------------------------------------------------------------------------
local history_timer = mp.add_periodic_timer(15, function()
    if not ctx.p["idle-active"] and not ctx.p.pause then media.update_history() end
end)

local pause_next = false
mp.register_event("file-loaded", function()
    ctx.active_preset = nil
    media.autoload()
    local fp = media.folder_preset()
    if fp then media.apply_preset(fp) end
    if pause_next then
        pause_next = false
        mp.set_property_bool("pause", true)
    end
    if not ctx.library then Library.dir = nil end
    -- watch_later resume → show the "Start over" prompt
    mp.add_timeout(0.25, function()
        local t = mp.get_property_number("time-pos", 0)
        local start = mp.get_property("start", "none")
        if t > 10 and (start == "none" or start == "") and media.setting("resume_prompt", true) then
            ctx.resume = { t = t, untl = mp.get_time() + 7 }
            ctx.request_render()
        end
    end)
    media.update_history()
    ctx.request_render()
end)

mp.add_hook("on_unload", 50, function()
    media.update_history()
end)

mp.register_event("end-file", function(e)
    -- sleep timer "end of current file": pause as soon as the next file starts
    if e and e.reason == "eof" and media.sleep.mode == "eof" then
        pause_next = true
        media.sleep.mode = "off"
    end
end)

mp.register_event("shutdown", function()
    media.save_store(true)
end)

mp.register_script_message("thumbfast-info", function(json)
    local data = utils.parse_json(json)
    if type(data) == "table" then ctx.thumbfast = data end
end)

-- periodic refresh for countdowns / media info while those are visible
mp.add_periodic_timer(1, function()
    if ctx.show_info or (ctx.panel == "settings" and ctx.tab == "playback" and media.sleep.ends) then ctx.request_render() end
end)

---------------------------------------------------------------------------
-- Debug helpers (used for headless screenshots)
---------------------------------------------------------------------------
mp.register_script_message("vlcui-debug", function(cmd, a, b_)
    if cmd == "dump" then
        render()
        local f = io.open(a, "w")
        if f then
            f:write("[Script Info]\nScriptType: v4.00+\nPlayResX: " .. ctx.w .. "\nPlayResY: " .. ctx.h ..
                "\nScaledBorderAndShadow: yes\nWrapStyle: 2\n\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n" ..
                "Style: Default,Inter,20,&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1\n\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
            for line in last_ass:gmatch("[^\n]+") do
                f:write("Dialogue: 0,0:00:00.00,0:01:00.00,Default,,0,0,0,," .. line .. "\n")
            end
            f:close()
        end
    elseif cmd == "mouse" then
        ctx.mouse_locked = true
        ctx.mouse.x, ctx.mouse.y, ctx.mouse.inside = tonumber(a), tonumber(b_), true
        ctx.last_move = mp.get_time()
        render()
        render()
    elseif cmd == "click" then
        ctx.mouse.x, ctx.mouse.y, ctx.mouse.inside = tonumber(a), tonumber(b_), true
        ctx.last_move = mp.get_time()
        render()
        mouse_down(); mouse_up()
        render()
    elseif cmd == "rclick" then
        ctx.mouse.x, ctx.mouse.y, ctx.mouse.inside = tonumber(a), tonumber(b_), true
        render()
        api.context_menu(ctx.mouse.x, ctx.mouse.y)
        render()
    elseif cmd == "eval" then
        local fn = loadstring(a)
        if fn then fn() end
        render()
    end
end)

ctx.request_render()

-- exposed for the debug "eval" message
vlcui_debug = { ctx = ctx, api = api, media = media, menus = menus, Settings = Settings, Library = Library,
    SubSearch = SubSearch, Rename = Rename, render = function() render() end }
