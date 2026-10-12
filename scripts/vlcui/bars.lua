-- Top bar (title / window controls) and bottom bar (transport, seekbar, cone volume, quick toggles).
local mp = require 'mp'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'
local menus = require 'menus'

local Bars = {}

function Bars.top_h() return 40 * ctx.s end
function Bars.bot_h() return 54 * ctx.s end

local function p(name) return ctx.p[name] end

---------------------------------------------------------------------------
-- Menus opened from the bars
---------------------------------------------------------------------------
function Bars.audio_menu_items()
    local items = { { header = true, label = "Audio tracks" } }
    local cur = p("aid")
    local tracks = media.tracks("audio")
    items[#items + 1] = { label = "Disable", checked = (cur == "no" or cur == false), action = function() media.select_track("audio", nil) end }
    for _, t in ipairs(tracks) do
        items[#items + 1] = {
            label = media.track_label(t), checked = t.selected or false,
            action = function() media.select_track("audio", t.id) end,
        }
    end
    local devices = media.audio_devices()
    if #devices > 0 then
        local dev_items = {}
        local curdev = p("audio-device")
        for _, d in ipairs(devices) do
            dev_items[#dev_items + 1] = {
                label = d.label, checked = d.name == curdev,
                action = function() mp.set_property("audio-device", d.name) end,
            }
        end
        items[#items + 1] = { separator = true }
        items[#items + 1] = { label = "Output device", icon = "headphones", submenu = dev_items }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = "Audio settings", icon = "sliders", action = function() ctx.api.open_panel("settings", "audio") end }
    return items
end

function Bars.sub_menu_items()
    local items = {}
    local cur = p("sid")
    local embedded, external = {}, {}
    for _, t in ipairs(media.tracks("sub")) do
        if t.external then external[#external + 1] = t else embedded[#embedded + 1] = t end
    end
    items[#items + 1] = { header = true, label = "Embedded tracks" }
    items[#items + 1] = { label = "None", checked = (cur == "no" or cur == false), action = function() media.select_track("sub", nil) end }
    for _, t in ipairs(embedded) do
        items[#items + 1] = {
            label = media.track_label(t), checked = (t.selected and t["main-selection"] ~= 1) or false,
            action = function() media.select_track("sub", t.id) end,
        }
    end
    items[#items + 1] = {
        header = true, label = "External tracks", button_icon = "plus", button_tooltip = "Add subtitle file",
        button_action = media.add_subtitle_dialog,
    }
    if #external == 0 then
        items[#items + 1] = { label = "Add subtitle file…", icon = "file-plus", action = media.add_subtitle_dialog }
    end
    for _, t in ipairs(external) do
        items[#items + 1] = {
            label = media.track_label(t), checked = (t.selected and t["main-selection"] ~= 1) or false,
            action = function() media.select_track("sub", t.id) end,
        }
    end
    local sec = { { label = "None", checked = p("secondary-sid") == "no" or p("secondary-sid") == false,
        action = function() mp.set_property("secondary-sid", "no") end } }
    for _, t in ipairs(media.tracks("sub")) do
        sec[#sec + 1] = { label = media.track_label(t), checked = t["main-selection"] == 1,
            action = function() mp.set_property("secondary-sid", tostring(t.id)) end }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { label = "Secondary subtitle", icon = "layers", submenu = sec }
    items[#items + 1] = { label = "Subtitle settings", icon = "sliders", action = function() ctx.api.open_panel("settings", "subtitles") end }
    return items
end

---------------------------------------------------------------------------
-- Top bar
---------------------------------------------------------------------------
function Bars.draw_top()
    local s, b, W = ctx.s, ctx.b, ctx.w
    local h = Bars.top_h()
    local cy = h / 2
    b:rect(0, 0, W, h, { color = D.T.bar })
    U.region("top:bg", 0, 0, W, h, {
        block = true, hover = false, drag_window = true,
        dbl = function() if p("border") == false and not p("fullscreen") then mp.commandv("cycle", "window-maximized") end end,
    })

    -- left cluster
    local logo_hov = ctx.hover == "top:logo"
    b:cone(24 * s, cy, 20 * s, logo_hov and D.mix(D.T.accent, "ffffff", 0.15) or D.T.accent)
    U.region("top:logo", 10 * s, 4 * s, 28 * s, h - 8 * s, { click = function() ctx.api.main_menu(12 * s, h + 4 * s) end, tooltip = "Menu" })
    U.icon_button("top:menu", 62 * s, cy, "ellipsis", {
        tooltip = "Media", on_click = function() ctx.api.main_menu(46 * s, h + 4 * s) end,
        active = menus.is_open("main"),
    })
    U.icon_button("top:sidebar", 98 * s, cy, "panel-left", {
        tooltip = "Library (Ctrl+M)", active = ctx.library, on_click = function() ctx.api.toggle_library() end,
    })
    b:rect(120 * s, cy - 9 * s, 1 * s, 18 * s, { color = D.T.line })
    local path = p("path")
    local dir = path and media.dirname(media.abspath(path))
    local folder = dir and media.basename(dir) or (path and media.is_url(path) and "Network" or "Library")
    if folder == "" then folder = dir or "Library" end
    folder = D.ellipsize(folder, 14 * s, 180 * s)
    local fw = D.text_width(folder, 14 * s)
    local fhov = ctx.hover == "top:folder"
    if fhov then b:rect(128 * s, cy - 14 * s, fw + 40 * s, 28 * s, { color = D.T.surface, r = 4 * s }) end
    b:icon(146 * s, cy, ctx.library and "folder-open" or "folder", { size = 17 * s, color = (fhov or ctx.library) and D.T.text or D.T.text2 })
    b:text(162 * s, cy, folder, { size = 14 * s, color = (fhov or ctx.library) and D.T.text or D.T.text2 })
    U.region("top:folder", 128 * s, cy - 14 * s, fw + 40 * s, 28 * s, {
        click = function() ctx.api.toggle_library() end, tooltip = "Browse this folder",
    })
    local left_end = 128 * s + fw + 52 * s

    -- right cluster
    local x = W
    local show_wc = p("border") == false
    if show_wc then
        local close_hov = ctx.hover == "top:close"
        if close_hov then b:rect(x - 46 * s, 0, 46 * s, h, { color = "c42b1c" }) end
        b:icon(x - 23 * s, cy, "x", { size = 17 * s, color = close_hov and D.T.white or D.T.text2 })
        U.region("top:close", x - 46 * s, 0, 46 * s, h, { click = function() mp.commandv("quit") end, tooltip = "Close" })
        x = x - 46 * s
        if not p("fullscreen") then
            U.icon_button("top:max", x - 22 * s, cy, p("window-maximized") and "copy" or "square", {
                size = 14, box_w = 44, box_h = 40, tooltip = p("window-maximized") and "Restore" or "Maximize",
                on_click = function() mp.commandv("cycle", "window-maximized") end,
            })
            U.icon_button("top:min", x - 66 * s, cy, "minus", {
                size = 17, box_w = 44, box_h = 40, tooltip = "Minimize",
                on_click = function() mp.set_property_bool("window-minimized", true) end,
            })
            x = x - 88 * s
        end
        b:rect(x - 8 * s, cy - 9 * s, 1 * s, 18 * s, { color = D.T.line })
        x = x - 8 * s
    end
    U.icon_button("top:fs", x - 22 * s, cy, p("fullscreen") and "minimize" or "maximize", {
        size = 16, tooltip = p("fullscreen") and "Exit fullscreen (F)" or "Fullscreen (F)",
        on_click = function() mp.commandv("cycle", "fullscreen") end,
    })
    U.icon_button("top:pip", x - 58 * s, cy, "pip", {
        size = 17, active = media.mini ~= nil, tooltip = "Mini player",
        on_click = media.toggle_mini,
    })
    local right_start = x - 80 * s

    -- centered title
    local title = p("media-title") or (p("idle-active") and "Media Player" or "")
    local avail = math.max(0, math.min(W / 2 - left_end, right_start - W / 2) * 2 - 20 * s)
    if avail > 40 * s then
        title = D.ellipsize(title, 14 * s, avail)
        b:text(W / 2, cy, title, { align = 5, size = 14 * s, color = D.T.text2 })
    end
end

---------------------------------------------------------------------------
-- Bottom bar
---------------------------------------------------------------------------
local function seek_to(frac, exact)
    local dur = p("duration")
    if not dur or dur <= 0 then return end
    local t = U.clamp(frac, 0, 1) * dur
    mp.commandv("seek", tostring(t), exact and "absolute+exact" or "absolute+keyframes")
end

local thumb_shown = false
local function clear_thumb()
    if thumb_shown then
        mp.commandv("script-message-to", "thumbfast", "clear")
        thumb_shown = false
    end
end
Bars.clear_thumb = clear_thumb

function Bars.draw_bottom()
    local s, b, W, H = ctx.s, ctx.b, ctx.w, ctx.h
    local bh = Bars.bot_h()
    local y0 = H - bh
    local cy = y0 + bh / 2
    local idle = p("idle-active")
    b:rect(0, y0, W, bh, { color = D.T.bar })
    U.region("bot:bg", 0, y0, W, bh, { block = true, hover = false, drag_window = true })

    -- transport
    U.icon_button("bot:prev", 24 * s, cy, nil, {
        tooltip = "Previous (P)", box = 30,
        draw = function(cx, ccy, col) b:glyph("prev", cx, ccy, 14 * s, col) end,
        on_click = function() mp.commandv("playlist-prev") end,
    })
    local px, pw, ph = 44 * s, 56 * s, 28 * s
    local phov = ctx.hover == "bot:play"
    b:rect(px, cy - ph / 2, pw, ph, { color = phov and D.mix(D.T.accent, "ffffff", 0.14) or D.T.accent, r = 4 * s })
    b:glyph((p("pause") or idle) and "play" or "pause", px + pw / 2, cy, 14 * s, "121212")
    U.region("bot:play", px, cy - ph / 2, pw, ph, {
        click = function()
            if idle then ctx.api.open_dialog() else mp.commandv("cycle", "pause") end
        end,
        tooltip = p("pause") and "Play (Space)" or "Pause (Space)",
    })
    U.icon_button("bot:next", 120 * s, cy, nil, {
        tooltip = "Next (N)", box = 30,
        draw = function(cx, ccy, col) b:glyph("next", cx, ccy, 14 * s, col) end,
        on_click = function() mp.commandv("playlist-next") end,
    })

    local dur = p("duration") or 0
    local pos = p("time-pos") or 0
    local hours = dur >= 3600
    local tsize = 14 * s
    local tw = D.text_width(hours and "00:00:00" or "00:00", tsize) + 4 * s

    -- right cluster (right to left)
    U.icon_button("bot:queue", W - 30 * s, cy, "list", {
        tooltip = "Queue (Ctrl+L)", active = ctx.panel == "queue",
        on_click = function() ctx.api.toggle_panel("queue") end,
    })
    U.icon_button("bot:settings", W - 72 * s, cy, "settings", {
        tooltip = "Playback, video, audio & subtitle settings (Ctrl+E)", active = ctx.panel == "settings",
        on_click = function() ctx.api.toggle_panel("settings") end,
    })
    U.icon_button("bot:subs", W - 114 * s, cy, "captions", {
        tooltip = "Subtitles", active = menus.is_open("pop-subs"),
        on_click = function()
            menus.open(Bars.sub_menu_items, W - 98 * s, y0 - 6 * s, { align = "right", above = true, id = "pop-subs", min_width = 270 * s, check_col = true })
        end,
    })
    U.icon_button("bot:audio", W - 156 * s, cy, "audio-lines", {
        tooltip = "Audio", active = menus.is_open("pop-audio"),
        on_click = function()
            menus.open(Bars.audio_menu_items, W - 140 * s, y0 - 6 * s, { align = "right", above = true, id = "pop-audio", min_width = 270 * s, check_col = true })
        end,
    })

    -- cone volume
    local vw, vh = 88 * s, 22 * s
    local vx, vy = W - 190 * s - vw, cy - vh / 2
    local vol = p("volume") or 100
    local vmax = p("volume-max") or 130
    local muted = p("mute")
    b:rect(vx, vy, vw, vh, { color = D.T.input, r = 3 * s })
    local ins = 3 * s
    local pts = { { vx + ins, vy + vh - ins }, { vx + vw - ins, vy + ins }, { vx + vw - ins, vy + vh - ins } }
    b:poly(pts, { color = "262626" })
    local function vx_of(v) return vx + ins + (vw - 2 * ins) * U.clamp(v / vmax, 0, 1) end
    local fill_to = vx_of(vol)
    local x100 = vx_of(100)
    b:poly(pts, { color = muted and "4a4a4a" or D.T.green, clip = { vx, vy, math.min(fill_to, x100), vy + vh } })
    if vol > 100 and not muted then
        b:poly(pts, { color = D.T.accent, clip = { x100, vy, fill_to, vy + vh } })
    end
    if vmax > 100 then b:rect(x100, vy + ins, 1 * s, vh - 2 * ins, { color = D.T.bar }) end
    local function set_vol(mx)
        local v = math.floor(U.clamp((mx - vx - ins) / (vw - 2 * ins), 0, 1) * vmax + 0.5)
        if math.abs(v - 100) <= 2 then v = 100 end
        mp.set_property_number("volume", v)
        if muted then mp.set_property_bool("mute", false) end
    end
    U.region("bot:vol", vx, vy - 6 * s, vw, vh + 12 * s, {
        drag_start = set_vol, drag_move = set_vol,
        wheel = function(dir) mp.commandv("add", "volume", tostring(dir * 5)) end,
        tooltip = "Volume " .. math.floor(vol + 0.5) .. "%" .. (muted and " (muted)" or ""),
    })
    local vicon = muted and "volume-x" or (vol < 1 and "volume" or (vol < 60 and "volume-1" or "volume-2"))
    U.icon_button("bot:mute", vx - 20 * s, cy, vicon, {
        tooltip = muted and "Unmute (M)" or "Mute (M)",
        on_click = function() mp.commandv("cycle", "mute") end,
        on_wheel = function(dir) mp.commandv("add", "volume", tostring(dir * 5)) end,
    })

    -- duration / remaining
    local remaining = media.setting("remaining", false)
    local speed = p("speed") or 1
    local dur_text = remaining and ("-" .. media.fmt_time((dur - pos) / speed, hours)) or media.fmt_time(dur, hours)
    if idle or dur <= 0 then dur_text = hours and "--:--:--" or "--:--" end
    local dw = D.text_width(remaining and ("-" .. (hours and "00:00:00" or "00:00")) or (hours and "00:00:00" or "00:00"), tsize) + 4 * s
    local dx2 = vx - 44 * s
    b:text(dx2, cy, dur_text, { align = 6, size = tsize, color = ctx.hover == "bot:dur" and D.T.text or D.T.text2 })
    U.region("bot:dur", dx2 - dw, cy - 12 * s, dw, 24 * s, {
        click = function() media.set_setting("remaining", not remaining) end,
        tooltip = remaining and "Show duration" or "Show remaining time",
    })

    -- current time
    b:text(148 * s, cy, idle and (hours and "--:--:--" or "--:--") or media.fmt_time(pos, hours), { size = tsize, color = D.T.text2 })

    -- seekbar
    local sx1 = 148 * s + tw + 14 * s
    local sx2 = dx2 - dw - 14 * s
    local sw = sx2 - sx1
    if sw > 40 * s then Bars.draw_seek(sx1, cy, sw, dur, pos, y0) end
end

function Bars.draw_seek(sx, cy, sw, dur, pos, bar_top)
    local s, b = ctx.s, ctx.b
    local sh = 28 * s
    local sy = cy - sh / 2
    local r = 4 * s
    b:rect(sx, sy, sw, sh, { color = D.T.input, r = r })
    if dur <= 0 then
        U.region("bot:seek", sx, sy, sw, sh, { hover = false, block = true })
        clear_thumb()
        return
    end
    local function x_of(t) return sx + sw * U.clamp(t / dur, 0, 1) end

    -- buffered ranges (network streams)
    local cache = p("demuxer-cache-state")
    if cache and cache["seekable-ranges"] and p("demuxer-via-network") then
        for _, rg in ipairs(cache["seekable-ranges"]) do
            local a, z = x_of(rg.start or 0), x_of(rg["end"] or 0)
            if z - a > 1 then b:rect(a, sy + sh - 4 * s, z - a, 3 * s, { color = "2e2e2e" }) end
        end
    end

    local dragging = ctx.drag and ctx.drag.id == "bot:seek"
    local frac = U.clamp(pos / dur, 0, 1)
    if dragging and ctx.seek_frac then frac = ctx.seek_frac end
    local hx = sx + sw * frac

    -- waveform
    local wave = media.setting("waveform", false) and media.waveform() or nil
    if wave and #wave > 1 then
        local n = #wave
        local step = sw / n
        local played, rest = {}, {}
        local mid = cy
        local maxh = sh - 8 * s
        for i = 1, n do
            local x = sx + (i - 1) * step
            local hh = math.max(1 * s, wave[i] * maxh)
            local part = string.format("m %.1f %.1f l %.1f %.1f %.1f %.1f %.1f %.1f ", x, mid - hh / 2, x + math.max(1, step * 0.7), mid - hh / 2,
                x + math.max(1, step * 0.7), mid + hh / 2, x, mid + hh / 2)
            if x < hx then played[#played + 1] = part else rest[#rest + 1] = part end
        end
        if #played > 0 then b:path(table.concat(played), { color = D.T.accent, opacity = 0.85 }) end
        if #rest > 0 then b:path(table.concat(rest), { color = "3a3a3a" }) end
    else
        if hx - sx > 0.5 then
            b:rect(sx, sy, hx - sx, sh, { color = D.T.accent_dim, r = r })
        end
    end

    -- subtitle timeline
    if media.setting("sub_timeline", false) then
        local cues = media.sub_cues()
        if cues and #cues > 0 then
            local delay = p("sub-delay") or 0
            local parts = {}
            local lane_y, lane_h = sy + sh - 6 * s, 3 * s
            for _, c in ipairs(cues) do
                local a, z = x_of(c[1] + delay), x_of(c[2] + delay)
                if z - a < 1.5 * s then z = a + 1.5 * s end
                parts[#parts + 1] = string.format("m %.1f %.1f l %.1f %.1f %.1f %.1f %.1f %.1f ", a, lane_y, z, lane_y, z, lane_y + lane_h, a, lane_y + lane_h)
            end
            b:path(table.concat(parts), { color = "b8b8b8", opacity = 0.75 })
        end
    end

    -- chapters & bookmarks
    if media.setting("chapters", true) then
        for _, ch in ipairs(p("chapter-list") or {}) do
            if ch.time and ch.time > 0.5 and ch.time < dur - 0.5 then
                b:rect(x_of(ch.time) - 1 * s, sy, 2 * s, sh, { color = D.T.bar })
            end
        end
    end
    for _, bm in ipairs(media.bookmarks()) do
        local bx = x_of(bm.time)
        b:poly({ { bx - 4 * s, sy - 7 * s }, { bx + 4 * s, sy - 7 * s }, { bx, sy - 2 * s } }, { color = D.T.accent })
    end

    -- A-B loop markers
    local a, z = tonumber(p("ab-loop-a")), tonumber(p("ab-loop-b"))
    if a then b:rect(x_of(a) - 1 * s, sy - 3 * s, 2 * s, sh + 6 * s, { color = D.T.white }) end
    if z then b:rect(x_of(z) - 1 * s, sy - 3 * s, 2 * s, sh + 6 * s, { color = D.T.white }) end

    -- handle
    local hov = ctx.hover == "bot:seek" or dragging
    b:rect(hx - 3.5 * s, sy - 1 * s, 7 * s, sh + 2 * s, { color = hov and D.mix(D.T.accent, "ffffff", 0.15) or D.T.accent, r = 3 * s })

    U.region("bot:seek", sx, sy - 6 * s, sw, sh + 12 * s, {
        drag_start = function(mx)
            ctx.seek_frac = U.clamp((mx - sx) / sw, 0, 1)
            ctx.seek_was_paused = p("pause")
            seek_to(ctx.seek_frac, false)
        end,
        drag_move = function(mx)
            ctx.seek_frac = U.clamp((mx - sx) / sw, 0, 1)
            seek_to(ctx.seek_frac, false)
        end,
        drag_end = function(mx)
            seek_to(U.clamp((mx - sx) / sw, 0, 1), true)
            ctx.seek_frac = nil
        end,
        wheel = function(dir) mp.commandv("seek", tostring(dir * 5)) end,
    })

    -- hover preview: time, chapter name, thumbnail
    if hov and ctx.mouse.inside then
        local mx = U.clamp(ctx.mouse.x, sx, sx + sw)
        local t = (mx - sx) / sw * dur
        if not dragging then b:rect(mx - 0.5 * s, sy, 1 * s, sh, { color = D.T.white, opacity = 0.35 }) end
        local label = media.fmt_time(t, dur >= 3600)
        local chap
        for _, ch in ipairs(p("chapter-list") or {}) do
            if ch.time and ch.time <= t then chap = ch.title end
        end
        local tsz = 13 * s
        local lw = D.text_width(label, tsz) + 18 * s
        local chw = chap and math.min(260 * s, D.text_width(chap, tsz) + 18 * s) or 0
        local boxw = math.max(lw, chw)
        local boxh = chap and 44 * s or 26 * s
        local by = bar_top - boxh - 8 * s
        local bx = U.clamp(mx - boxw / 2, 6 * s, ctx.w - boxw - 6 * s)

        local tf = ctx.thumbfast
        if tf and tf.available and not tf.disabled and tf.width and tf.width > 0 then
            local tw_, th_ = tf.width, tf.height
            local tx = U.clamp(mx - tw_ / 2, 6 * s, ctx.w - tw_ - 6 * s)
            local ty = by - th_ - 6 * s
            b:rect(tx - 2 * s, ty - 2 * s, tw_ + 4 * s, th_ + 4 * s, { color = D.T.bar, r = 4 * s })
            mp.commandv("script-message-to", "thumbfast", "thumb", tostring(t), tostring(math.floor(tx)), tostring(math.floor(ty)))
            thumb_shown = true
        end
        b:rect(bx, by, boxw, boxh, { color = D.T.bar, r = 4 * s, border = 1 * s, border_color = "2a2a2a" })
        if chap then
            b:text(bx + boxw / 2, by + 13 * s, D.ellipsize(chap, tsz, boxw - 14 * s), { align = 5, size = tsz, color = D.T.text2 })
            b:text(bx + boxw / 2, by + 31 * s, label, { align = 5, size = tsz, color = D.T.text, bold = true })
        else
            b:text(bx + boxw / 2, by + boxh / 2, label, { align = 5, size = tsz, color = D.T.text })
        end
    else
        clear_thumb()
    end
end

return Bars
