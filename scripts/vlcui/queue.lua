-- Queue panel: what plays next. Click to play, drag to reorder, x to remove.
local mp = require 'mp'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'

local Q = {}

local function item_name(it)
    if it.title and it.title ~= "" then return it.title end
    return media.basename(it.filename or "")
end

function Q.draw(x, y, w, h)
    local s, b = ctx.s, ctx.b
    b:rect(x, y, w, h, { color = D.T.panel })
    U.region("q:bg", x, y, w, h, { block = true, hover = false })
    local pad = 20 * s
    local list = ctx.p.playlist or {}

    -- header
    local hh = 56 * s
    local cy = y + hh / 2
    local total, known = 0, 0
    for _, it in ipairs(list) do
        local e = media.history_entry(media.abspath(it.filename))
        local d = (it.current and ctx.p.duration) or (e and e.dur)
        if d and d > 0 then total = total + d; known = known + 1 end
    end
    local info = #list .. (#list == 1 and " item" or " items")
    if known > 0 then
        local hrs = math.floor(total / 3600)
        info = info .. "  ·  " .. (hrs > 0 and (hrs .. "h " .. math.floor(total / 60) % 60 .. "m") or (math.floor(total / 60) .. "m"))
        if known < #list then info = info .. "+" end
    end
    b:text(x + pad, cy, info, { size = 13 * s, color = D.T.text2 })
    local lp = ctx.p["loop-playlist"]
    local looping = lp and lp ~= "no" and lp ~= false
    local bx = x + w - pad - 12 * s
    U.icon_button("q:add", bx, cy, "plus", { size = 17, tooltip = "Add files to the queue", on_click = function() media.open_dialog("append") end })
    U.icon_button("q:clear", bx - 34 * s, cy, "trash", {
        size = 16, tooltip = "Clear queue (keeps the current item)",
        on_click = function() mp.commandv("playlist-clear"); ctx.toast(nil, "Queue cleared") end,
    })
    U.icon_button("q:shuffle", bx - 68 * s, cy, "shuffle", {
        size = 16, tooltip = "Shuffle", on_click = function() mp.commandv("playlist-shuffle"); ctx.toast("R", "Queue shuffled") end,
    })
    U.icon_button("q:repeat", bx - 102 * s, cy, "repeat", {
        size = 16, active = looping, tooltip = looping and "Repeat queue: on" or "Repeat queue: off",
        on_click = function() mp.set_property("loop-playlist", looping and "no" or "inf") end,
    })
    b:rect(x + pad, y + hh, w - 2 * pad, 1 * s, { color = D.T.line })

    -- footer
    local fh = 56 * s
    local fy = y + h - fh
    U.button("q:save", x + pad, fy + 10 * s, w - 2 * pad, 36 * s, "Save queue as playlist", {
        icon = "list-music", size = 13, on_click = media.save_queue_as_playlist,
    })

    -- list
    local ly, lh = y + hh + 6 * s, fy - (y + hh + 6 * s)
    local top = U.scroll_begin("q:list", x, ly, w, lh)
    local rh = 40 * s
    local drag = ctx.drag and ctx.drag.id and ctx.drag.id:match("^q:item:") and ctx.drag or nil
    local drop_idx
    if drag then
        drop_idx = math.floor((ctx.mouse.y - top) / rh + 0.5)
        drop_idx = U.clamp(drop_idx, 0, #list)
    end
    if #list == 0 then
        b:text(x + w / 2, ly + 60 * s, "The queue is empty", { align = 5, size = 14 * s, color = D.T.text2 })
        b:text(x + w / 2, ly + 84 * s, "Drop files on the window or press +", { align = 5, size = 13 * s, color = D.T.text3 })
    end
    for i, it in ipairs(list) do
        local ry = top + (i - 1) * rh
        local id = "q:item:" .. i
        local hov = ctx.hover == id or ctx.hover == id .. ":x"
        local cur = it.current or it.playing
        if cur then
            b:rect(x + 8 * s, ry + 2 * s, w - 16 * s, rh - 4 * s, { color = D.T.accent_dim, r = 5 * s })
        elseif hov then
            b:rect(x + 8 * s, ry + 2 * s, w - 16 * s, rh - 4 * s, { color = D.T.surface, r = 5 * s })
        end
        if drag and drag.index == i then
            b:rect(x + 8 * s, ry + 2 * s, w - 16 * s, rh - 4 * s, { color = D.T.line, r = 5 * s })
        end
        b:icon(x + pad + 2 * s, ry + rh / 2, cur and "play" or "grip", { size = 15 * s, color = cur and D.T.accent or D.T.text3 })
        local e = media.history_entry(media.abspath(it.filename))
        local d = (cur and ctx.p.duration) or (e and e.dur)
        local right = x + w - pad
        if hov and not drag then
            U.icon_button(id .. ":x", right - 8 * s, ry + rh / 2, "x", {
                size = 14, box = 26, tooltip = "Remove",
                on_click = function() mp.commandv("playlist-remove", tostring(i - 1)) end,
            })
            right = right - 30 * s
        elseif d and d > 0 then
            b:text(right, ry + rh / 2, media.fmt_time(d), { align = 6, size = 13 * s, color = D.T.text3 })
            right = right - 52 * s
        end
        b:text(x + pad + 24 * s, ry + rh / 2, item_name(it), {
            size = 14 * s, color = cur and D.T.text or D.T.text2,
            clip = { x + pad + 24 * s, ry, right - 6 * s, ry + rh },
        })
        if e and e.dur and e.dur > 0 and e.pos and e.pos > 5 and not cur then
            local pw = (right - (x + pad + 24 * s) - 6 * s)
            b:rect(x + pad + 24 * s, ry + rh - 7 * s, pw * U.clamp(e.pos / e.dur, 0, 1), 2 * s, { color = D.T.accent, opacity = 0.8 })
        end
        U.region(id, x + 8 * s, ry, w - 16 * s, rh, {
            click = function() mp.commandv("playlist-play-index", tostring(i - 1)) end,
            drag_start = function() ctx.drag.index = i end,
            drag_move = function() end,
            drag_end = function(_, my)
                local to = U.clamp(math.floor((my - top) / rh + 0.5), 0, #list)
                if to ~= i - 1 and to ~= i then mp.commandv("playlist-move", tostring(i - 1), tostring(to)) end
            end,
            drag_threshold = 6 * s,
            tooltip = it.filename,
        })
    end
    if drag and drop_idx then
        b:rect(x + 12 * s, top + drop_idx * rh - 1 * s, w - 24 * s, 2 * s, { color = D.T.accent })
    end
    U.scroll_end("q:list", x, ly, w, lh, #list * rh + 10 * s)
end

return Q
