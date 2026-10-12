-- Right sidebar: Playback / Video / Audio / Subtitles tabs (the "Pandora's box" turned into a panel).
local mp = require 'mp'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'

local S = {}

S.tabs = {
    { "playback", "Playback", "play" },
    { "video", "Video", "clapperboard" },
    { "audio", "Audio", "audio-lines" },
    { "subtitles", "Subtitles", "captions" },
}

local function p(name) return ctx.p[name] end
local function num(name, d) local v = tonumber(ctx.p[name]); if v == nil then return d end return v end

---------------------------------------------------------------------------
-- Layout helpers (a simple vertical cursor)
---------------------------------------------------------------------------
local L = {}

local function section(title, first)
    local s = ctx.s
    if not first then
        L.y = L.y + 10 * s
        ctx.b:rect(L.px, L.y, L.pw, 1 * s, { color = "202020" })
        L.y = L.y + 12 * s
    end
    U.header(L.x, L.y + 16 * s, title)
    L.y = L.y + 40 * s
end

local function label(text, cy, info_id, info)
    U.label(L.x, cy, text)
    if info then
        U.info(info_id, L.x + D.text_width(text, 14 * ctx.s) + 14 * ctx.s, cy, info)
    end
end

local function value_row(id, text, value, on_click, o)
    local s = ctx.s
    o = o or {}
    local h = 40 * s
    local cy = L.y + h / 2
    label(text, cy, id .. ":i", o.info)
    local bw = o.box_w or 140 * s
    U.box(id, L.x + L.w - bw, cy - 16 * s, bw, 32 * s, value, { on_click = on_click, swatch = o.swatch, tooltip = o.tooltip })
    L.y = L.y + h + 4 * s
end

local function slider_row(id, value, min, max, o)
    local s = ctx.s
    o.no_wheel = true
    U.slider(id, L.x, L.y + 4 * s, L.w, 16 * s, value, min, max, o)
    L.y = L.y + 30 * s
    if o.scale then
        local cy = L.y + 2 * s
        local st = { size = 12 * s, color = D.T.text3 }
        ctx.b:text(L.x, cy, o.scale[1], st)
        if o.scale[2] then
            local mx = L.x + L.w * ((o.scale_mid or (min + max) / 2) - min) / (max - min)
            ctx.b:text(mx, cy, o.scale[2], { align = 5, size = 12 * s, color = D.T.text3 })
        end
        ctx.b:text(L.x + L.w, cy, o.scale[3], { align = 6, size = 12 * s, color = D.T.text3 })
        L.y = L.y + 20 * s
    end
    L.y = L.y + 6 * s
end

local function toggle_row(id, text, on, cb, info)
    local s = ctx.s
    local h = 40 * s
    local cy = L.y + h / 2
    label(text, cy, id .. ":i", info)
    U.toggle(id, L.x + L.w, cy, on, cb)
    L.y = L.y + h + 2 * s
end

local function dropdown_row(id, text, items, current, cb, o)
    local s = ctx.s
    o = o or {}
    local h = 40 * s
    local cy = L.y + h / 2
    label(text, cy, id .. ":i", o.info)
    local bw = o.box_w or 180 * s
    U.dropdown(id, L.x + L.w - bw, cy - 16 * s, bw, 32 * s, items, current, cb, { label = o.label })
    L.y = L.y + h + 4 * s
end

local function segmented_row(id, text, options, current, cb, o)
    local s = ctx.s
    o = o or {}
    if text then
        local h = 40 * s
        local cy = L.y + h / 2
        label(text, cy, id .. ":i", o.info)
        local bw = o.box_w or 190 * s
        U.segmented(id, L.x + L.w - bw, cy - 15 * s, bw, 30 * s, options, current, cb)
        L.y = L.y + h + 4 * s
    else
        U.segmented(id, L.x, L.y, L.w, 30 * s, options, current, cb)
        L.y = L.y + 38 * s
    end
end

local function expander(id, text, open, cb)
    local s = ctx.s
    local h = 36 * s
    local hov = ctx.hover == id
    ctx.b:rect(L.x, L.y, L.w, h, { color = hov and D.T.surface or D.T.panel2, r = 5 * s })
    ctx.b:text(L.x + 14 * s, L.y + h / 2, text, { size = 13 * s, color = hov and D.T.text or D.T.text2 })
    ctx.b:icon(L.x + L.w - 18 * s, L.y + h / 2, open and "chevron-up" or "chevron-down", { size = 15 * s, color = D.T.text2 })
    U.region(id, L.x, L.y, L.w, h, { click = cb })
    L.y = L.y + h + 8 * s
end

local function button_row(id, text, icon, cb)
    local s = ctx.s
    U.button(id, L.x, L.y, L.w, 34 * s, text, { icon = icon, on_click = cb, size = 13 })
    L.y = L.y + 42 * s
end

local function prompt_number(title, cur, cb)
    media.prompt(title, cur, function(text)
        local v = tonumber((text or ""):match("[-+]?%d*%.?%d+"))
        if v then cb(v) end
    end)
end

local function track_items(kind, with_none)
    local items = {}
    if with_none then items[#items + 1] = { label = kind == "audio" and "Disabled" or "None", value = "no" } end
    for _, t in ipairs(media.tracks(kind)) do
        items[#items + 1] = { label = media.track_label(t), value = t.id }
    end
    return items
end

local function color_hex(prop)
    local v = p(prop) or "#FFFFFFFF"
    local hex = tostring(v):match("#%x%x(%x%x%x%x%x%x)$") or tostring(v):match("#(%x%x%x%x%x%x)$") or "FFFFFF"
    return hex:upper()
end

local palette = {
    { "White", "FFFFFF" }, { "Light gray", "B8B8B8" }, { "Gray", "808080" }, { "Black", "0C0C0C" },
    { "Yellow", "FFE14D" }, { "Orange", "F2A541" }, { "Cyan", "6FE3F2" }, { "Green", "8BE07A" },
    { "Pink", "F28CC5" }, { "Red", "E8504A" },
}

local function color_menu(prop, x, y, w)
    local cur = color_hex(prop)
    local items = {}
    for _, c in ipairs(palette) do
        items[#items + 1] = {
            label = c[1] .. "  #" .. c[2], checked = c[2] == cur,
            action = function() mp.set_property(prop, "#" .. c[2]) end,
        }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = {
        label = "Custom hex…", icon = "palette",
        action = function()
            media.prompt("Color (#RRGGBB):", "#" .. cur, function(t)
                local h = (t or ""):match("#?(%x%x%x%x%x%x)")
                if h then mp.set_property(prop, "#" .. h) end
            end)
        end,
    }
    ctx.api.open_menu(items, x, y, { width = w, check_col = true })
end

local function color_row(id, text, prop)
    local s = ctx.s
    local h = 40 * s
    local cy = L.y + h / 2
    label(text, cy)
    local bw = 140 * s
    local bx, by = L.x + L.w - bw, cy - 16 * s
    local hex = color_hex(prop)
    U.box(id, bx, by, bw, 32 * s, "#" .. hex, {
        swatch = hex,
        on_click = function() color_menu(prop, bx, by + 36 * s, bw + 60 * s) end,
    })
    L.y = L.y + h + 4 * s
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function tab_playback()
    local s = ctx.s
    section("Speed", true)
    local speed = num("speed", 1)
    value_row("pb:speed", "Playback speed", string.format("%.2fx", speed), function()
        prompt_number("Playback speed:", string.format("%.2f", speed), function(v) mp.set_property_number("speed", U.clamp(v, 0.01, 100)) end)
    end)
    slider_row("pb:speed-s", speed, 0.25, 2, {
        step = 0.05, default = 1, origin = 1, marks = { 0.5, 1, 1.5 },
        on_change = function(v) mp.set_property_number("speed", v) end,
        scale = { "0.25x", "1x", "2x" }, scale_mid = 1,
    })
    toggle_row("pb:pitch", "Keep audio pitch", p("audio-pitch-correction") ~= false, function()
        mp.commandv("cycle", "audio-pitch-correction")
    end, "Corrects the pitch of the audio when playing faster or slower")
    toggle_row("pb:reverse", "Reverse playback", p("play-direction") == "-", function()
        mp.set_property("play-direction", p("play-direction") == "-" and "+" or "-")
    end, "Plays backwards. Uses a lot of memory on long jumps.")

    section("Repeat")
    local loop = (p("loop-file") and p("loop-file") ~= "no" and p("loop-file") ~= false) and "file"
        or ((p("loop-playlist") and p("loop-playlist") ~= "no" and p("loop-playlist") ~= false) and "queue" or "off")
    segmented_row("pb:loop", "Loop", {
        { label = "Off", value = "off" }, { label = "File", value = "file" }, { label = "Queue", value = "queue" },
    }, loop, function(v)
        mp.set_property("loop-file", v == "file" and "inf" or "no")
        mp.set_property("loop-playlist", v == "queue" and "inf" or "no")
    end)
    local a, z = tonumber(p("ab-loop-a")), tonumber(p("ab-loop-b"))
    local ab = (a and z) and (media.fmt_time(a) .. " → " .. media.fmt_time(z)) or (a and ("A: " .. media.fmt_time(a)) or "Off")
    value_row("pb:ab", "A-B repeat", ab, function() mp.commandv("ab-loop") end, {
        info = "Click once to set A, again to set B, a third time to clear. Shortcut: Shift+L",
    })

    section("Sleep timer")
    local sl = media.sleep
    local sl_label
    if sl.ends then
        sl_label = "Pause in " .. media.fmt_time(math.max(0, sl.ends - mp.get_time()))
    end
    dropdown_row("pb:sleep", "Pause playback", {
        { label = "Off", value = "off" }, { label = "15 minutes", value = "15" }, { label = "30 minutes", value = "30" },
        { label = "45 minutes", value = "45" }, { label = "1 hour", value = "60" }, { label = "1.5 hours", value = "90" },
        { label = "End of current file", value = "eof" },
    }, sl.mode, media.set_sleep, { label = sl_label })

    section("Seekbar")
    toggle_row("pb:subtl", "Show subtitle timeline", media.setting("sub_timeline", false), function()
        media.set_setting("sub_timeline", not media.setting("sub_timeline", false))
    end, "Marks where subtitle lines appear, so you can line them up with the audio")
    toggle_row("pb:wave", "Show waveform", media.setting("waveform", false), function()
        media.set_setting("waveform", not media.setting("waveform", false))
    end, "Draws the audio waveform inside the seekbar (computed with ffmpeg)")
    toggle_row("pb:chap", "Show chapters", media.setting("chapters", true), function()
        media.set_setting("chapters", not media.setting("chapters", true))
    end)
    toggle_row("pb:meta", "Show media info", ctx.show_info or false, function()
        ctx.show_info = not ctx.show_info
    end, "Shows metadata, codecs and resolution in the corner (I)")

    -- Bookmarks
    L.y = L.y + 10 * s
    ctx.b:rect(L.px, L.y, L.pw, 1 * s, { color = "202020" })
    L.y = L.y + 12 * s
    U.header(L.x, L.y + 16 * s, "Bookmarks")
    U.button("pb:bm-add", L.x + L.w - 96 * s, L.y + 2 * s, 96 * s, 28 * s, "Add", {
        icon = "bookmark-plus", size = 13,
        on_click = function() ctx.api.add_bookmark() end, tooltip = "Ctrl+B",
    })
    L.y = L.y + 42 * s
    local bms = media.bookmarks()
    if #bms == 0 then
        ctx.b:text(L.x, L.y + 10 * s, "No bookmarks yet. Press Ctrl+B while watching.", { size = 13 * s, color = D.T.text3 })
        L.y = L.y + 30 * s
    end
    for i, bm in ipairs(bms) do
        local id = "pb:bm:" .. i
        local hov = ctx.hover == id or ctx.hover == id .. ":x"
        local rh = 34 * s
        if hov then ctx.b:rect(L.x - 8 * s, L.y, L.w + 16 * s, rh, { color = D.T.surface, r = 4 * s }) end
        ctx.b:icon(L.x + 8 * s, L.y + rh / 2, "bookmark", { size = 15 * s, color = D.T.accent })
        ctx.b:text(L.x + 26 * s, L.y + rh / 2, media.fmt_time(bm.time), { size = 13 * s, color = D.T.text2 })
        ctx.b:text(L.x + 90 * s, L.y + rh / 2, bm.name, { size = 14 * s, color = D.T.text, clip = { L.x, L.y, L.x + L.w - 34 * s, L.y + rh } })
        U.region(id, L.x - 8 * s, L.y, L.w + 16 * s, rh, {
            click = function() mp.commandv("seek", tostring(bm.time), "absolute+exact") end,
            rclick = function() media.rename_bookmark(i) end,
            tooltip = "Click to jump, right-click to rename",
        })
        if hov then
            U.icon_button(id .. ":x", L.x + L.w - 10 * s, L.y + rh / 2, "x", { size = 14, box = 24, on_click = function() media.remove_bookmark(i) end })
        end
        L.y = L.y + rh
    end

    -- Chapters
    local chapters = p("chapter-list") or {}
    if #chapters > 0 then
        section("Chapters")
        local cur = p("chapter") or -1
        for i, ch in ipairs(chapters) do
            local id = "pb:ch:" .. i
            local hov = ctx.hover == id
            local rh = 34 * s
            local active = (i - 1) == cur
            if hov or active then ctx.b:rect(L.x - 8 * s, L.y, L.w + 16 * s, rh, { color = active and D.T.accent_dim or D.T.surface, r = 4 * s }) end
            ctx.b:text(L.x + 4 * s, L.y + rh / 2, media.fmt_time(ch.time), { size = 13 * s, color = active and D.T.accent or D.T.text2 })
            ctx.b:text(L.x + 70 * s, L.y + rh / 2, ch.title or ("Chapter " .. i), {
                size = 14 * s, color = active and D.T.text or D.T.text2, clip = { L.x, L.y, L.x + L.w, L.y + rh } })
            U.region(id, L.x - 8 * s, L.y, L.w + 16 * s, rh, { click = function() mp.set_property_number("chapter", i - 1) end })
            L.y = L.y + rh
        end
    end
end

local function tab_video()
    local s = ctx.s
    section("Picture", true)
    local vtracks = media.tracks("video")
    if #vtracks > 1 then
        dropdown_row("vd:track", "Video track", track_items("video", true), p("vid"), function(v) mp.set_property("vid", tostring(v)) end)
    end
    segmented_row("vd:flip", "Flip", {
        { label = "None", value = "none" }, { icon = "flip-h", value = "h", tooltip = "Horizontal" }, { icon = "flip-v", value = "v", tooltip = "Vertical" },
    }, media.video.flip, media.set_flip)
    segmented_row("vd:rot", "Rotate", {
        { label = "0°", value = 0 }, { label = "90°", value = 90 }, { label = "180°", value = 180 }, { label = "270°", value = 270 },
    }, num("video-rotate", 0), function(v) mp.set_property_number("video-rotate", v) end, { box_w = 210 * s })
    local zoom = num("video-zoom", 0)
    value_row("vd:zoom", "Zoom", string.format("%.2fx", 2 ^ zoom), function()
        prompt_number("Zoom factor:", string.format("%.2f", 2 ^ zoom), function(v)
            if v > 0 then mp.set_property_number("video-zoom", math.log(v) / math.log(2)) end
        end)
    end)
    slider_row("vd:zoom-s", zoom, -1, 1.585, {
        step = 0.01, default = 0, origin = 0,
        on_change = function(v) mp.set_property_number("video-zoom", v) end,
        scale = { "0.5x", "1x", "3x" }, scale_mid = 0,
    })
    local aspect = p("video-aspect-override")
    if aspect == nil or aspect == "no" or (tonumber(aspect) and tonumber(aspect) <= 0) then aspect = "no" end
    local aspects = {
        { label = "Default", value = "no" }, { label = "16:9", value = "16:9" }, { label = "4:3", value = "4:3" },
        { label = "21:9", value = "21:9" }, { label = "2.35:1", value = "2.35:1" }, { label = "1.85:1", value = "1.85:1" },
        { label = "5:4", value = "5:4" }, { label = "1:1", value = "1:1" },
    }
    local alabel
    for _, it in ipairs(aspects) do
        if it.value ~= "no" then
            local a1, a2 = it.value:match("([%d%.]+):([%d%.]+)")
            if tonumber(aspect) and math.abs(tonumber(aspect) - a1 / a2) < 0.01 then alabel = it.label end
        end
    end
    if aspect == "no" then alabel = "Default" end
    dropdown_row("vd:aspect", "Aspect ratio", aspects, aspect, function(v) mp.set_property("video-aspect-override", v) end, { label = alabel or tostring(aspect) })
    toggle_row("vd:fill", "Crop to fill window", num("panscan", 0) > 0, function()
        mp.set_property_number("panscan", num("panscan", 0) > 0 and 0 or 1)
    end, "Zooms in to remove black bars (pan & scan)")
    toggle_row("vd:deint", "Deinterlace", p("deinterlace") == true or p("deinterlace") == "yes", function()
        mp.commandv("cycle", "deinterlace")
    end)
    dropdown_row("vd:tone", "HDR tone mapping", {
        { label = "Auto", value = "auto" }, { label = "BT.2390", value = "bt.2390" }, { label = "Spline", value = "spline" },
        { label = "Hable", value = "hable" }, { label = "Reinhard", value = "reinhard" }, { label = "Mobius", value = "mobius" },
        { label = "Clip", value = "clip" },
    }, p("tone-mapping") or "auto", function(v) mp.set_property("tone-mapping", v) end, {
        info = "How HDR video is converted for an SDR screen",
    })

    section("Adjustments")
    for _, adj in ipairs({ { "brightness", "Brightness" }, { "contrast", "Contrast" }, { "saturation", "Saturation" }, { "gamma", "Gamma" }, { "hue", "Hue" } }) do
        local v = num(adj[1], 0)
        local h = 26 * s
        U.label(L.x, L.y + h / 2, adj[2])
        ctx.b:text(L.x + L.w, L.y + h / 2, string.format("%d", v), { align = 6, size = 13 * s, color = D.T.text2 })
        L.y = L.y + h
        slider_row("vd:" .. adj[1], v, -100, 100, {
            step = 1, default = 0, origin = 0,
            on_change = function(nv) mp.set_property_number(adj[1], nv) end,
        })
    end
    button_row("vd:reset", "Reset adjustments", "undo", function()
        for _, k in ipairs({ "brightness", "contrast", "saturation", "gamma", "hue" }) do mp.set_property_number(k, 0) end
    end)

    section("Filters")
    toggle_row("vd:negate", "Negate colors", media.video.negate, function() media.video_fx("negate", not media.video.negate) end)
    toggle_row("vd:gray", "Grayscale", media.video.gray, function() media.video_fx("gray", not media.video.gray) end)
    toggle_row("vd:sepia", "Sepia", media.video.sepia, function() media.video_fx("sepia", not media.video.sepia) end)
    toggle_row("vd:sharpen", "Sharpen", media.video.sharpen, function() media.video_fx("sharpen", not media.video.sharpen) end)
    toggle_row("vd:denoise", "Denoise", media.video.denoise, function() media.video_fx("denoise", not media.video.denoise) end)
    L.y = L.y + 6 * s
    button_row("vd:shot", "Take snapshot", "camera", function() mp.commandv("screenshot") end)
end

local function band_slider(id, text, value, min, max, unit, on_change, default)
    local s = ctx.s
    local h = 34 * s
    U.label(L.x, L.y + h / 2, text)
    local bw = 96 * s
    U.box(id .. ":b", L.x + L.w - bw, L.y + 2 * s, bw, h - 4 * s, string.format("%.1f %s", value, unit), {
        on_click = function()
            prompt_number(text .. " (" .. unit .. "):", string.format("%.1f", value), function(v) on_change(U.clamp(v, min, max), true) end)
        end,
    })
    L.y = L.y + h + 4 * s
    slider_row(id, value, min, max, { step = 0.1, default = default, origin = default, on_change = on_change })
end

local function tab_audio()
    local s = ctx.s
    section("Defaults", true)
    dropdown_row("au:track", "Audio track", track_items("audio", true), p("aid"), function(v) mp.set_property("aid", tostring(v)) end)
    local devs = {}
    for _, d in ipairs(media.audio_devices()) do
        devs[#devs + 1] = { label = d.label, value = d.name }
    end
    if #devs > 0 then
        dropdown_row("au:dev", "Output device", devs, p("audio-device"), function(v) mp.set_property("audio-device", v) end)
    end
    local vol = num("volume", 100)
    value_row("au:vol", "Volume", string.format("%d%%", vol), function()
        prompt_number("Volume (%):", tostring(math.floor(vol)), function(v) mp.set_property_number("volume", U.clamp(v, 0, num("volume-max", 130))) end)
    end)
    slider_row("au:vol-s", vol, 0, num("volume-max", 130), {
        step = 1, default = 100, on_change = function(v) mp.set_property_number("volume", v) end,
        marks = { 100 }, scale = { "0%", "100%", math.floor(num("volume-max", 130)) .. "%" }, scale_mid = 100,
    })

    section("Synchronization")
    local ad = num("audio-delay", 0)
    value_row("au:delay", "Audio track delay", string.format("%.3f s", ad), function()
        prompt_number("Audio delay (seconds):", string.format("%.3f", ad), function(v) mp.set_property_number("audio-delay", v) end)
    end, { info = "Positive values delay the audio. Shortcuts: J / K" })
    slider_row("au:delay-s", ad, -10, 10, {
        step = 0.05, default = 0, origin = 0,
        on_change = function(v) mp.set_property_number("audio-delay", v) end,
        scale = { "-10 s", "0 s", "+10 s" },
    })

    section("Effects")
    local a = media.audio
    toggle_row("au:eq", "Equalizer", a.eq, function() a.eq = not a.eq; media.eq_apply() end, "10-band graphic equalizer")
    local presets = {}
    for _, pr in ipairs(media.eq_presets) do presets[#presets + 1] = { label = pr[1], value = pr[1] } end
    dropdown_row("au:eqp", "Equalizer preset", presets, a.eq_preset, function(v) media.eq_set_preset(v) end, {
        label = a.eq_preset, info = "Pick a preset, then fine-tune the bands below",
    })
    expander("au:eqx", ctx.eq_open and "Close equalizer" or "Open equalizer", ctx.eq_open, function() ctx.eq_open = not ctx.eq_open end)
    if ctx.eq_open then
        local function on_band(i)
            return function(v, final)
                if i == 0 then a.preamp = v else a.bands[i] = v end
                a.eq_preset = "Custom"
                if final then a.eq = true; media.eq_apply() end
            end
        end
        band_slider("au:pre", "Preamp", a.preamp, -20, 20, "dB", on_band(0), 0)
        for i, lbl in ipairs(media.eq_labels) do
            band_slider("au:b" .. i, lbl, a.bands[i], -20, 20, "dB", on_band(i), 0)
        end
    end
    toggle_row("au:comp", "Compressor", a.comp, function() a.comp = not a.comp; media.comp_apply() end,
        "Evens out loud and quiet parts (dynamic range compression)")
    expander("au:compx", ctx.comp_open and "Collapse settings" or "Expand settings", ctx.comp_open, function() ctx.comp_open = not ctx.comp_open end)
    if ctx.comp_open then
        local function on_c(key)
            return function(v, final)
                a[key] = v
                if final then a.comp = true; media.comp_apply() end
            end
        end
        band_slider("au:c1", "Threshold", a.comp_threshold, -60, 0, "dB", on_c("comp_threshold"), -18)
        band_slider("au:c2", "Ratio", a.comp_ratio, 1, 20, ": 1", on_c("comp_ratio"), 4)
        band_slider("au:c3", "Attack", a.comp_attack, 1, 200, "ms", on_c("comp_attack"), 25)
        band_slider("au:c4", "Release", a.comp_release, 10, 1000, "ms", on_c("comp_release"), 100)
        band_slider("au:c5", "Knee radius", a.comp_knee, 0, 18, "dB", on_c("comp_knee"), 5)
        band_slider("au:c6", "Makeup gain", a.comp_makeup, 0, 24, "dB", on_c("comp_makeup"), 4)
    end
    toggle_row("au:norm", "Normalize volume", a.normalize, function() media.simple_audio("normalize", not a.normalize) end,
        "Makes quiet scenes louder and loud scenes quieter")
    toggle_row("au:widen", "Stereo widening", a.widen, function() media.simple_audio("widen", not a.widen) end)
    toggle_row("au:mono", "Mono", a.mono, function() media.simple_audio("mono", not a.mono) end, "Mixes both channels together")
end

local function tab_subtitles()
    local s = ctx.s
    section("Defaults", true)
    dropdown_row("sb:track", "Subtitle track", track_items("sub", true), p("sid"), function(v) mp.set_property("sid", tostring(v)) end)
    dropdown_row("sb:track2", "Secondary track", track_items("sub", true), p("secondary-sid"), function(v) mp.set_property("secondary-sid", tostring(v)) end)
    local slang = p("slang")
    if type(slang) == "table" then slang = table.concat(slang, ",") end
    value_row("sb:lang", "Preferred language", (slang and slang ~= "") and slang or "Auto", function()
        media.prompt("Preferred subtitle languages (e.g. en,eng):", slang or "", function(t) mp.set_property("slang", t or "") end)
    end, { info = "Auto-selects this language on every file. Save it in a preset to keep it per show." })
    button_row("sb:add", "Add subtitle file…", "file-plus", media.add_subtitle_dialog)

    section("Synchronization")
    local sd = num("sub-delay", 0)
    value_row("sb:delay", "Subtitle track delay", string.format("%.3f s", sd), function()
        prompt_number("Subtitle delay (seconds):", string.format("%.3f", sd), function(v) mp.set_property_number("sub-delay", v) end)
    end, { info = "Positive values show subtitles later. Shortcuts: G / H" })
    slider_row("sb:delay-s", sd, -10, 10, {
        step = 0.05, default = 0, origin = 0,
        on_change = function(v) mp.set_property_number("sub-delay", v) end,
        scale = { "-10 s", "0 s", "+10 s" },
    })
    local sp = num("sub-speed", 1)
    value_row("sb:speed", "Subtitle speed", string.format("%.3f", sp), function()
        prompt_number("Subtitle speed factor:", string.format("%.3f", sp), function(v) if v > 0 then mp.set_property_number("sub-speed", v) end end)
    end, { info = "Stretches subtitle timing. Use when subtitles drift further out of sync over time." })
    slider_row("sb:speed-s", sp, 0.5, 2, {
        step = 0.001, default = 1, origin = 1,
        on_change = function(v) mp.set_property_number("sub-speed", v) end,
    })

    section("Appearance")
    toggle_row("sb:override", "Override embedded style", p("sub-ass-override") == "force", function()
        mp.set_property("sub-ass-override", p("sub-ass-override") == "force" and "scale" or "force")
    end, "Apply the settings below to styled (ASS) subtitles too")
    local fonts = { "Inter", "sans-serif", "serif", "Noto Sans", "Roboto", "Open Sans", "Arial", "Helvetica", "Verdana", "Trebuchet MS", "Georgia" }
    local cur_font = p("sub-font") or "sans-serif"
    local fitems = {}
    local found = false
    for _, f in ipairs(fonts) do
        fitems[#fitems + 1] = { label = f, value = f }
        if f == cur_font then found = true end
    end
    if not found then table.insert(fitems, 1, { label = cur_font, value = cur_font }) end
    fitems[#fitems + 1] = { label = "Other…", value = "__other" }
    dropdown_row("sb:font", "Subtitle font", fitems, cur_font, function(v)
        if v == "__other" then
            media.prompt("Font family name:", cur_font, function(t) if t and t ~= "" then mp.set_property("sub-font", t) end end)
        else
            mp.set_property("sub-font", v)
        end
    end, { box_w = 160 * s })
    color_row("sb:color", "Text color", "sub-color")
    color_row("sb:ocolor", "Outline color", "sub-outline-color")
    toggle_row("sb:bold", "Bold", p("sub-bold") == true, function() mp.commandv("cycle", "sub-bold") end)

    local mode = media.setting("sub_size_mode", "relative")
    segmented_row("sb:mode", "Size values", { { label = "Relative", value = "relative" }, { label = "Pixels", value = "pixels" } },
        mode, function(v) media.set_setting("sub_size_mode", v) end, { box_w = 170 * s })
    if mode == "pixels" then
        local fs = num("sub-font-size", 55)
        value_row("sb:fs", "Font size", string.format("%dpx", fs), function()
            prompt_number("Font size (px at 720p):", tostring(math.floor(fs)), function(v) mp.set_property_number("sub-font-size", U.clamp(v, 4, 300)) end)
        end)
        slider_row("sb:fs-s", fs, 10, 120, { step = 1, default = 55, on_change = function(v) mp.set_property_number("sub-font-size", v) end })
    else
        local sc = num("sub-scale", 1)
        value_row("sb:scale", "Text scale", string.format("%.2fx", sc), function()
            prompt_number("Subtitle scale:", string.format("%.2f", sc), function(v) mp.set_property_number("sub-scale", U.clamp(v, 0.1, 10)) end)
        end)
        slider_row("sb:scale-s", sc, 0.3, 3, { step = 0.05, default = 1, origin = 1, on_change = function(v) mp.set_property_number("sub-scale", v) end })
    end
    local ol = num("sub-outline-size", 3)
    value_row("sb:ol", "Outline thickness", string.format("%.1fpx", ol), function()
        prompt_number("Outline thickness:", string.format("%.1f", ol), function(v) mp.set_property_number("sub-outline-size", U.clamp(v, 0, 20)) end)
    end)
    slider_row("sb:ol-s", ol, 0, 8, { step = 0.5, default = 2.5, on_change = function(v) mp.set_property_number("sub-outline-size", v) end })

    local back = tostring(p("sub-back-color") or "#00000000")
    local back_alpha = tonumber(back:match("^#(%x%x)%x%x%x%x%x%x$") or "00", 16) or 0
    local opacity = (p("sub-border-style") == "background-box" or p("sub-border-style") == "opaque-box") and math.floor(back_alpha / 255 * 100 + 0.5) or 0
    value_row("sb:bg", "Background opacity", opacity .. "%", nil)
    slider_row("sb:bg-s", opacity, 0, 100, {
        step = 5, default = 0,
        on_change = function(v)
            if v <= 0 then
                mp.set_property("sub-border-style", "outline-and-shadow")
            else
                mp.set_property("sub-border-style", "background-box")
                mp.set_property("sub-back-color", string.format("#%02X000000", math.floor(v / 100 * 255 + 0.5)))
            end
        end,
    })
    local pos = num("sub-pos", 100)
    value_row("sb:pos", "Vertical position", string.format("%d%%", pos), nil, { info = "100% is the bottom of the video" })
    slider_row("sb:pos-s", pos, 0, 150, { step = 1, default = 100, on_change = function(v) mp.set_property_number("sub-pos", v) end })
end

---------------------------------------------------------------------------
-- Preset footer
---------------------------------------------------------------------------
local function preset_menu(x, y, w)
    local items = {}
    local names = media.preset_names()
    local cur = ctx.active_preset
    local folder_p = media.folder_preset()
    items[#items + 1] = { header = true, label = "Presets" }
    if #names == 0 then
        items[#items + 1] = { label = "No presets yet", disabled = true }
    end
    for _, n in ipairs(names) do
        items[#items + 1] = {
            label = n, checked = n == cur, hint = (n == folder_p) and "this folder" or nil,
            action = function() media.apply_preset(n) end,
        }
    end
    items[#items + 1] = { separator = true }
    local function ask(link)
        local dir = media.dirname(media.abspath(mp.get_property("path")))
        media.prompt("Preset name:", cur or (dir and media.basename(dir)) or "", function(t)
            if t and t ~= "" then media.save_preset(t, link) end
        end)
    end
    items[#items + 1] = { label = "Save as preset for this folder…", icon = "folder", action = function() ask(true) end,
        tooltip = "Every file in this folder will open with these settings" }
    items[#items + 1] = { label = "Save as preset…", icon = "plus", action = function() ask(false) end }
    if cur then
        items[#items + 1] = { label = "Update \"" .. cur .. "\"", icon = "check", action = function() media.save_preset(cur, folder_p == cur) end }
        items[#items + 1] = { label = "Delete \"" .. cur .. "\"", icon = "trash", icon_color = "c0462c", action = function() media.delete_preset(cur) end }
    end
    ctx.api.open_menu(items, x, y, { width = w, above = true, check_col = true })
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
function S.draw(x, y, w, h)
    local s, b = ctx.s, ctx.b
    b:rect(x, y, w, h, { color = D.T.panel })
    U.region("side:bg", x, y, w, h, { block = true, hover = false })

    -- tabs
    local th = 48 * s
    b:rect(x, y, w, th, { color = "0f0f0f" })
    local tw = w / #S.tabs
    for i, t in ipairs(S.tabs) do
        local tx = x + (i - 1) * tw
        local id = "side:tab:" .. t[1]
        local active = ctx.tab == t[1]
        local hov = ctx.hover == id
        local col = active and D.T.text or (hov and D.T.text or D.T.text2)
        local lw = D.text_width(t[2], 13 * s)
        local total = lw + 22 * s
        local sx = tx + (tw - total) / 2
        if total > tw - 8 * s then
            b:icon(tx + tw / 2, y + th / 2, t[3], { size = 16 * s, color = active and D.T.accent or col })
        else
            b:icon(sx + 8 * s, y + th / 2, t[3], { size = 15 * s, color = active and D.T.accent or col })
            b:text(sx + 22 * s, y + th / 2, t[2], { size = 13 * s, color = col })
        end
        if active then b:rect(tx + 8 * s, y + th - 2 * s, tw - 16 * s, 2 * s, { color = D.T.accent }) end
        U.region(id, tx, y, tw, th, { click = function() ctx.tab = t[1] end, tooltip = t[2] })
    end

    -- footer
    local fh = 96 * s
    local fy = y + h - fh
    b:rect(x, fy, w, fh, { color = "0f0f0f" })
    local pad = 20 * s
    local pbx, pby, pbw, pbh = x + pad, fy + 12 * s, w - 2 * pad, 38 * s
    local phov = ctx.hover == "side:preset"
    b:rect(pbx, pby, pbw, pbh, { color = phov and D.T.surface or D.T.input, r = 6 * s })
    local preset_label = ctx.active_preset and ("Preset: " .. ctx.active_preset) or "Default preset"
    b:text(pbx + 14 * s, pby + pbh / 2, preset_label, { size = 14 * s, color = D.T.text, clip = { pbx, pby, pbx + pbw - 30 * s, pby + pbh } })
    b:icon(pbx + pbw - 18 * s, pby + pbh / 2, "chevron-up", { size = 15 * s, color = D.T.text2 })
    U.region("side:preset", pbx, pby, pbw, pbh, {
        click = function() preset_menu(pbx, pby - 4 * s, pbw) end,
        tooltip = "Save subtitle/audio settings for a show and reuse them on every episode",
    })
    local ahov = ctx.hover == "side:adv"
    local adv = "Open Advanced Settings"
    local aw = D.text_width(adv, 13 * s) + 22 * s
    local ax = x + (w - aw) / 2
    b:icon(ax + 7 * s, fy + 72 * s, "settings", { size = 14 * s, color = ahov and D.T.text or D.T.text2 })
    b:text(ax + 22 * s, fy + 72 * s, adv, { size = 13 * s, color = ahov and D.T.text or D.T.text2 })
    U.region("side:adv", ax - 6 * s, fy + 60 * s, aw + 12 * s, 24 * s, { click = function() ctx.api.open_settings() end })

    -- content
    local cy0 = y + th
    local ch = fh and (fy - cy0) or (h - th)
    local sid = "side:" .. ctx.tab
    local top = U.scroll_begin(sid, x, cy0, w, ch)
    L.px, L.pw = x, w
    L.x, L.w = x + pad, w - 2 * pad
    L.y = top + 14 * s
    if ctx.tab == "playback" then tab_playback()
    elseif ctx.tab == "video" then tab_video()
    elseif ctx.tab == "audio" then tab_audio()
    else tab_subtitles() end
    local content_h = L.y - top + 16 * s
    U.scroll_end(sid, x, cy0, w, ch, content_h)
end

return S
