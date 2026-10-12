-- Immediate-mode widgets: every render pass draws widgets and registers hit regions.
local ctx = require 'ctx'
local D = require 'draw'

local U = {}

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
U.clamp = clamp

---------------------------------------------------------------------------
-- Clipping and hit regions
---------------------------------------------------------------------------
function U.push_clip(x1, y1, x2, y2)
    local c = ctx.clip_stack[#ctx.clip_stack]
    if c then
        x1, y1 = math.max(x1, c[1]), math.max(y1, c[2])
        x2, y2 = math.min(x2, c[3]), math.min(y2, c[4])
    end
    local nc = { x1, y1, math.max(x1, x2), math.max(y1, y2) }
    ctx.clip_stack[#ctx.clip_stack + 1] = nc
    ctx.b.clip = nc
end

function U.pop_clip()
    ctx.clip_stack[#ctx.clip_stack] = nil
    ctx.b.clip = ctx.clip_stack[#ctx.clip_stack]
end

-- Register a hit region. Handlers: click, rclick, wheel(dir), drag_start/drag_move/drag_end(mx, my),
-- tooltip (string), block (swallow events), hover (false = no hover state).
function U.region(id, x, y, w, h, hd)
    hd = hd or {}
    local x1, y1, x2, y2 = x, y, x + w, y + h
    local c = ctx.clip_stack[#ctx.clip_stack]
    if c then
        x1, y1 = math.max(x1, c[1]), math.max(y1, c[2])
        x2, y2 = math.min(x2, c[3]), math.min(y2, c[4])
    end
    if x2 <= x1 or y2 <= y1 then return nil end
    hd.id, hd.x1, hd.y1, hd.x2, hd.y2 = id, x1, y1, x2, y2
    ctx.regions[#ctx.regions + 1] = hd
    return hd
end

-- Top-most region under (x, y). With `field`, only regions having that handler (or blocking) count.
function U.hit(x, y, field)
    for i = #ctx.regions, 1, -1 do
        local r = ctx.regions[i]
        if x >= r.x1 and x < r.x2 and y >= r.y1 and y < r.y2 then
            if not field or r[field] or r.block then return r end
        end
    end
    return nil
end

function U.hovered(id) return ctx.hover == id end

---------------------------------------------------------------------------
-- Basic widgets
---------------------------------------------------------------------------
function U.icon_button(id, cx, cy, icon, o)
    o = o or {}
    local s, b = ctx.s, ctx.b
    local box_w = (o.box_w or o.box or 32) * s
    local box_h = (o.box_h or o.box or 32) * s
    local hov = ctx.hover == id
    if hov and not o.no_bg then
        b:rect(cx - box_w / 2, cy - box_h / 2, box_w, box_h, { color = o.hover_bg or D.T.surface, r = 4 * s })
    end
    local col = o.color or (o.active and D.T.accent) or (hov and D.T.text or D.T.text2)
    if o.draw then
        o.draw(cx, cy, col, hov)
    else
        b:icon(cx, cy, icon, { size = (o.size or 18) * s, color = col })
    end
    U.region(id, cx - box_w / 2, cy - box_h / 2, box_w, box_h, {
        click = o.on_click, rclick = o.on_rclick, wheel = o.on_wheel, tooltip = o.tooltip,
        tooltip_pos = o.tooltip_pos,
    })
end

function U.button(id, x, y, w, h, label, o)
    o = o or {}
    local s, b = ctx.s, ctx.b
    local hov = ctx.hover == id
    local bg = o.primary and (hov and D.mix(D.T.accent, "ffffff", 0.1) or D.T.accent)
        or (hov and D.T.line or (o.bg or D.T.surface))
    b:rect(x, y, w, h, { color = bg, r = 5 * s })
    local tc = o.primary and "111111" or (hov and D.T.white or D.T.text)
    local size = (o.size or 14) * s
    if o.icon then
        local tw = D.text_width(label, size, o.bold)
        local total = tw + 26 * s
        local sx = x + (w - total) / 2
        b:icon(sx + 9 * s, y + h / 2, o.icon, { size = 15 * s, color = o.primary and "111111" or (o.icon_color or D.T.text2) })
        b:text(sx + 26 * s, y + h / 2, label, { size = size, color = tc, bold = o.bold })
    else
        b:text(x + w / 2, y + h / 2, label, { align = 5, size = size, color = tc, bold = o.bold })
    end
    U.region(id, x, y, w, h, { click = o.on_click, tooltip = o.tooltip })
end

function U.header(x, cy, text, o)
    o = o or {}
    ctx.b:text(x, cy, text, { size = (o.size or 16) * ctx.s, color = D.T.text, bold = true })
end

function U.label(x, cy, text, o)
    o = o or {}
    ctx.b:text(x, cy, text, { size = (o.size or 14) * ctx.s, color = o.color or D.T.text2, clip = o.clip })
end

-- Horizontal slider. o: on_change(value, final), origin, step, default, wheel_step, no_wheel, marks
function U.slider(id, x, y, w, h, value, min, max, o)
    o = o or {}
    local s, b = ctx.s, ctx.b
    value = tonumber(value) or min
    local function v2x(v) return x + (clamp(v, min, max) - min) / (max - min) * w end
    local function x2v(px)
        local v = min + clamp((px - x) / w, 0, 1) * (max - min)
        if o.step then v = math.floor(v / o.step + 0.5) * o.step end
        return clamp(v, min, max)
    end
    local active = ctx.drag and ctx.drag.id == id
    local hov = ctx.hover == id or active
    b:rect(x, y, w, h, { color = D.T.input, r = h * 0.4 })
    if o.marks then
        for _, mv in ipairs(o.marks) do
            local mx = v2x(mv)
            b:rect(mx - 1 * s, y + h * 0.3, 2 * s, h * 0.4, { color = D.T.line })
        end
    end
    local hx = v2x(value)
    local ox = v2x(o.origin or min)
    local pad = 3 * s
    local fx1, fx2 = math.min(ox, hx), math.max(ox, hx)
    if fx2 - fx1 > 1 then
        b:rect(fx1, y + pad, fx2 - fx1, h - 2 * pad, { color = o.disabled and D.T.surface or D.T.accent_dim, r = (h - 2 * pad) * 0.35 })
    end
    local hw = math.max(6 * s, h * 0.5)
    local hh = h * 1.4
    b:rect(hx - hw / 2, y + h / 2 - hh / 2, hw, hh, {
        color = o.disabled and D.T.knob or (hov and D.mix(D.T.accent, "ffffff", 0.15) or D.T.accent), r = hw / 2 })
    local function emit(v, final)
        if o.on_change then o.on_change(v, final) end
    end
    U.region(id, x - hw, y - 6 * s, w + 2 * hw, h + 12 * s, {
        drag_start = function(mx) emit(x2v(mx), false) end,
        drag_move = function(mx) emit(x2v(mx), false) end,
        drag_end = function(mx) emit(x2v(mx), true) end,
        wheel = (not o.no_wheel) and function(dir)
            emit(clamp(value + dir * (o.wheel_step or o.step or (max - min) / 50), min, max), true)
        end or nil,
        rclick = o.default ~= nil and function() emit(o.default, true) end or nil,
        tooltip = o.tooltip,
    })
end

-- ON/OFF switch (right-aligned at rx, vertically centered at cy). Returns its width.
function U.toggle(id, rx, cy, on, on_click)
    local s, b = ctx.s, ctx.b
    local w, h = 62 * s, 28 * s
    local x, y = rx - w, cy - h / 2
    local hov = ctx.hover == id
    local pad = 3 * s
    local kw = 24 * s
    b:rect(x, y, w, h, { color = D.T.input, r = 5 * s })
    if on then
        b:rect(x + pad, y + pad, w - 3 * pad - kw, h - 2 * pad, { color = D.T.accent_dim, r = 3 * s })
        b:text(x + pad + (w - 3 * pad - kw) / 2, cy, "ON", { align = 5, size = 12 * s, color = D.T.accent })
        b:rect(x + w - pad - kw, y + pad, kw, h - 2 * pad, { color = hov and D.mix(D.T.accent, "ffffff", 0.15) or D.T.accent, r = 3 * s })
    else
        b:rect(x + pad, y + pad, kw, h - 2 * pad, { color = hov and "555555" or D.T.knob, r = 3 * s })
        b:rect(x + 2 * pad + kw, y + pad, w - 3 * pad - kw, h - 2 * pad, { color = "1e1e1e", r = 3 * s })
        b:text(x + 2 * pad + kw + (w - 3 * pad - kw) / 2, cy, "OFF", { align = 5, size = 12 * s, color = D.T.text3 })
    end
    U.region(id, x, y, w, h, { click = on_click })
    return w
end

-- Segmented control. options = { {label=, value=, icon=}, ... }
function U.segmented(id, x, y, w, h, options, current, on_select)
    local s, b = ctx.s, ctx.b
    b:rect(x, y, w, h, { color = D.T.input, r = 5 * s })
    local n = #options
    local pad = 3 * s
    local sw = (w - pad * 2) / n
    for i, opt in ipairs(options) do
        local sx = x + pad + (i - 1) * sw
        local sel = tostring(opt.value) == tostring(current)
        local rid = id .. ":" .. i
        local hov = ctx.hover == rid
        if sel then
            b:rect(sx + 1 * s, y + pad, sw - 2 * s, h - 2 * pad, { color = D.T.accent_dim, r = 4 * s })
        elseif hov then
            b:rect(sx + 1 * s, y + pad, sw - 2 * s, h - 2 * pad, { color = D.T.surface, r = 4 * s })
        end
        local col = sel and D.T.accent or (hov and D.T.text or D.T.text2)
        if opt.icon then
            b:icon(sx + sw / 2, y + h / 2, opt.icon, { size = 15 * s, color = col })
        else
            b:text(sx + sw / 2, y + h / 2, opt.label, { align = 5, size = 13 * s, color = col })
        end
        U.region(rid, sx, y, sw, h, { click = function() on_select(opt.value) end, tooltip = opt.tooltip })
    end
end

-- A dark input-like box. o: on_click, swatch (hex), placeholder, chevron
function U.box(id, x, y, w, h, text, o)
    o = o or {}
    local s, b = ctx.s, ctx.b
    local hov = ctx.hover == id
    b:rect(x, y, w, h, { color = D.T.input, r = 5 * s, border = hov and 1 * s or 0, border_color = D.T.line })
    local tx_max = x + w - (o.chevron and 34 or (o.swatch and 40 or 12)) * s
    b:text(x + 12 * s, y + h / 2, text ~= "" and text or (o.placeholder or ""), {
        size = 14 * s, color = text ~= "" and (o.color or D.T.text) or D.T.text3,
        clip = { x, y, tx_max, y + h } })
    if o.chevron then
        b:icon(x + w - 18 * s, y + h / 2, "chevron-down", { size = 15 * s, color = D.T.text2 })
    end
    if o.swatch then
        local sz = h - 12 * s
        b:rect(x + w - sz - 6 * s, y + 6 * s, sz, sz, { color = o.swatch, r = 3 * s, border = 1 * s, border_color = "555555" })
    end
    U.region(id, x, y, w, h, { click = o.on_click, tooltip = o.tooltip, wheel = o.on_wheel })
end

-- Dropdown box: items is a list of {label=, value=} ; on_select(value)
function U.dropdown(id, x, y, w, h, items, current, on_select, o)
    o = o or {}
    if current == false or current == nil then current = "no" end
    local label = o.label
    if not label then
        for _, it in ipairs(items) do
            if tostring(it.value) == tostring(current) then label = it.label end
        end
    end
    U.box(id, x, y, w, h, label or tostring(current or ""), {
        chevron = true,
        on_click = function()
            local mitems = {}
            for _, it in ipairs(items) do
                mitems[#mitems + 1] = {
                    label = it.label, hint = it.hint, checked = tostring(it.value) == tostring(current),
                    action = function() on_select(it.value) end,
                }
            end
            ctx.api.open_menu(mitems, x, y + h + 4 * ctx.s, { width = w, check_col = true })
        end,
    })
end

-- Info icon with a tooltip (like the (i) in the mockups)
function U.info(id, cx, cy, text)
    ctx.b:icon(cx, cy, "info", { size = 14 * ctx.s, color = ctx.hover == id and D.T.text or D.T.text3 })
    U.region(id, cx - 9 * ctx.s, cy - 9 * ctx.s, 18 * ctx.s, 18 * ctx.s, { tooltip = text, hover = true })
end

---------------------------------------------------------------------------
-- Scroll containers
---------------------------------------------------------------------------
function U.scroll_begin(id, x, y, w, h)
    local off = ctx.scroll[id] or 0
    U.region(id .. ":scroll", x, y, w, h, {
        hover = false,
        wheel = function(dir)
            ctx.scroll[id] = (ctx.scroll[id] or 0) - dir * 70 * ctx.s
            ctx.request_render()
        end,
    })
    U.push_clip(x, y, x + w, y + h)
    return y - off
end

function U.scroll_end(id, x, y, w, h, content_h)
    U.pop_clip()
    local max_off = math.max(0, content_h - h)
    local off = ctx.scroll[id] or 0
    local c = clamp(off, 0, max_off)
    if c ~= off then
        ctx.scroll[id] = c
        ctx.request_render()
    end
    if max_off > 0 then
        local s = ctx.s
        local th = math.max(30 * s, h * h / content_h)
        local ty = y + (h - th) * (c / max_off)
        ctx.b:rect(x + w - 5 * s, ty, 3 * s, th, { color = "3a3a3a", r = 1.5 * s })
    end
end

function U.scroll_to_show(id, item_y, item_h, view_y, view_h)
    local off = ctx.scroll[id] or 0
    if item_y < view_y then
        ctx.scroll[id] = off - (view_y - item_y)
    elseif item_y + item_h > view_y + view_h then
        ctx.scroll[id] = off + (item_y + item_h - view_y - view_h)
    end
end

return U
