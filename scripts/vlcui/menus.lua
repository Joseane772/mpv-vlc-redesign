-- Menus: right-click menu, dropdown lists and the track popovers. Supports nested submenus.
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'

local M = {}

-- item fields: label, icon, icon_color, hint, checked (true/false = check column), submenu (table|function),
--              action, keep_open, disabled, separator, header, button_icon, button_action, button_tooltip
-- opts: width, min_width, align ("left"|"right"), above (open upwards from y), check_col, id
function M.open(items, x, y, o)
    ctx.menus = { { items = items, ax = x, ay = y, o = o or {} } }
    ctx.request_render()
end

function M.close()
    if #ctx.menus > 0 then
        ctx.menus = {}
        ctx.request_render()
    end
end

function M.is_open(id)
    if #ctx.menus == 0 then return false end
    if id == nil then return true end
    return ctx.menus[1].o.id == id
end

local function resolve(items)
    if type(items) == "function" then return items() or {} end
    return items or {}
end

local function layout(lv, parent, parent_row_y)
    local s = ctx.s
    local items = lv.resolved
    local row_h, hdr_h, sep_h, pad = 34 * s, 30 * s, 9 * s, 6 * s
    local lw, hw = 0, 0
    local has_icon = lv.o.check_col or false
    for _, it in ipairs(items) do
        if not it.separator then
            if it.icon or it.checked ~= nil then has_icon = true end
            local size = it.header and 12 * s or 14 * s
            lw = math.max(lw, D.text_width(it.label or "", size, false) + (it.header and it.button_icon and 30 * s or 0))
            if it.hint then hw = math.max(hw, D.text_width(it.hint, 13 * s)) end
            if it.submenu then hw = math.max(hw, 12 * s) end
        end
    end
    local w = 14 * s + (has_icon and 30 * s or 0) + lw + (hw > 0 and (30 * s + hw) or 0) + 16 * s
    w = math.max(w, lv.o.width or 0, lv.o.min_width or 150 * s)
    w = math.min(w, lv.o.max_width or 400 * s, ctx.w - 16 * s)
    local h = pad * 2
    for _, it in ipairs(items) do
        h = h + (it.separator and sep_h or (it.header and hdr_h or row_h))
    end
    lv.content_h = h
    h = math.min(h, ctx.h - 16 * s)
    local x, y = lv.ax or 0, lv.ay or 0
    if parent then
        x = parent.x + parent.w - 4 * s
        y = parent_row_y - pad
        if x + w > ctx.w - 8 * s then x = parent.x - w + 4 * s end
    else
        if lv.o.align == "right" then x = x - w end
        if lv.o.above then y = y - h end
    end
    x = U.clamp(x, 8 * s, math.max(8 * s, ctx.w - w - 8 * s))
    y = U.clamp(y, 8 * s, math.max(8 * s, ctx.h - h - 8 * s))
    lv.x, lv.y, lv.w, lv.h = x, y, w, h
    lv.row_h, lv.hdr_h, lv.sep_h, lv.pad, lv.has_icon = row_h, hdr_h, sep_h, pad, has_icon
end

function M.activate(li, i)
    local lv = ctx.menus[li]
    if not lv or not lv.resolved then return end
    local it = lv.resolved[i]
    if not it or it.disabled or it.header or it.separator then return end
    if it.submenu then
        for k = #ctx.menus, li + 1, -1 do ctx.menus[k] = nil end
        ctx.menus[li + 1] = { items = it.submenu, parent_idx = i, o = {} }
        ctx.request_render()
        return
    end
    if not it.keep_open then M.close() end
    if it.action then it.action() end
    ctx.request_render()
end

-- Open/close submenus following the hovered row.
local function sync_hover()
    local h = ctx.hover
    if not h then return end
    local li, i = h:match("^menu:(%d+):(%d+)$")
    li, i = tonumber(li), tonumber(i)
    if not li then return end
    local lv = ctx.menus[li]
    if not lv or not lv.resolved then return end
    local it = lv.resolved[i]
    if not it then return end
    if it.submenu and not it.disabled then
        local child = ctx.menus[li + 1]
        if not child or child.parent_idx ~= i then
            for k = #ctx.menus, li + 1, -1 do ctx.menus[k] = nil end
            ctx.menus[li + 1] = { items = it.submenu, parent_idx = i, o = {} }
        end
    else
        for k = #ctx.menus, li + 1, -1 do ctx.menus[k] = nil end
    end
end

function M.render()
    if #ctx.menus == 0 then return end
    local s, b = ctx.s, ctx.b
    sync_hover()
    U.region("menu:blocker", 0, 0, ctx.w, ctx.h, {
        block = true, hover = false,
        click = M.close, rclick = M.close, wheel = function() end,
    })
    local parent_row_y
    for li, lv in ipairs(ctx.menus) do
        lv.resolved = resolve(lv.items)
        local parent = li > 1 and ctx.menus[li - 1] or nil
        layout(lv, parent, parent_row_y)
        local x, y, w, h = lv.x, lv.y, lv.w, lv.h
        b:rect(x, y + 4 * s, w, h, { color = "000000", opacity = 0.5, r = 8 * s, blur = 10 * s })
        b:rect(x, y, w, h, { color = D.T.menu, r = 8 * s, border = 1 * s, border_color = "2a2a2a" })
        local sid = "menu" .. li
        local cy = U.scroll_begin(sid, x, y, w, h) + lv.pad
        local child = ctx.menus[li + 1]
        for i, it in ipairs(lv.resolved) do
            if it.separator then
                b:rect(x + 10 * s, cy + lv.sep_h / 2, w - 20 * s, 1 * s, { color = "2c2c2c" })
                cy = cy + lv.sep_h
            elseif it.header then
                b:text(x + 14 * s, cy + lv.hdr_h / 2 + 2 * s, it.label or "", { size = 12 * s, color = D.T.text3 })
                if it.button_icon then
                    U.icon_button("menu:" .. li .. ":hb" .. i, x + w - 22 * s, cy + lv.hdr_h / 2 + 2 * s, it.button_icon, {
                        size = 15, box = 24, tooltip = it.button_tooltip,
                        on_click = function()
                            M.close()
                            if it.button_action then it.button_action() end
                        end,
                    })
                end
                cy = cy + lv.hdr_h
            else
                local id = "menu:" .. li .. ":" .. i
                local hov = ctx.hover == id or (child and child.parent_idx == i)
                if hov and not it.disabled then
                    b:rect(x + 4 * s, cy, w - 8 * s, lv.row_h, { color = D.T.surface, r = 5 * s })
                end
                local mid = cy + lv.row_h / 2
                local tx = x + 14 * s
                if lv.has_icon then
                    if it.icon then
                        b:icon(x + 24 * s, mid, it.icon, { size = 16 * s, color = it.disabled and D.T.text3 or (it.icon_color or D.T.accent) })
                    elseif it.checked then
                        b:icon(x + 24 * s, mid, "check", { size = 16 * s, color = D.T.accent })
                    end
                    tx = x + 44 * s
                end
                local tcol = it.disabled and D.T.text3 or ((hov or it.checked) and D.T.text or D.T.text2)
                local right = x + w - 14 * s
                if it.submenu then
                    b:icon(right - 4 * s, mid, "chevron-right", { size = 14 * s, color = D.T.text2 })
                    right = right - 18 * s
                end
                if it.hint then
                    b:text(right, mid, it.hint, { align = 6, size = 13 * s, color = D.T.text3 })
                    right = right - D.text_width(it.hint, 13 * s) - 12 * s
                end
                b:text(tx, mid, it.label or "", { size = 14 * s, color = tcol, clip = { tx, cy, math.max(tx, right), cy + lv.row_h } })
                U.region(id, x + 4 * s, cy, w - 8 * s, lv.row_h, {
                    click = function() M.activate(li, i) end,
                    tooltip = it.tooltip,
                })
                if child and child.parent_idx == i then parent_row_y = cy end
                cy = cy + lv.row_h
            end
        end
        U.scroll_end(sid, x, y, w, h, lv.content_h)
    end
end

return M
