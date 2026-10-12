-- Library panel (left, compact): browse the current show's folder, recent files and saved playlists
-- without leaving the video.
local mp = require 'mp'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'

local Lib = {
    view = "browse",   -- browse | recent | playlists
    dir = nil,
    back = {}, fwd = {},
    filter = nil,
    listing = nil, listing_dir = nil,
}

function Lib.set_dir(dir, from_history)
    if not dir or dir == Lib.dir then return end
    if Lib.dir and not from_history then
        Lib.back[#Lib.back + 1] = Lib.dir
        Lib.fwd = {}
    end
    Lib.dir = dir
    Lib.listing = nil
    Lib.filter = nil
    ctx.scroll["lib:list"] = 0
end

function Lib.on_open()
    if not Lib.dir then
        local path = media.abspath(mp.get_property("path"))
        Lib.dir = (path and media.dirname(path)) or mp.get_property("working-directory") or os.getenv("HOME")
    end
    Lib.listing = nil
end

function Lib.follow_current()
    local path = media.abspath(mp.get_property("path"))
    local dir = path and media.dirname(path)
    if dir then Lib.dir = dir; Lib.listing = nil end
end

local function listing()
    if Lib.listing and Lib.listing_dir == Lib.dir and Lib.listing_ver == (ctx.fs_version or 0) then return Lib.listing end
    Lib.listing = media.list_dir(Lib.dir)
    Lib.listing_dir = Lib.dir
    Lib.listing_ver = ctx.fs_version or 0
    return Lib.listing
end

local function parent(dir)
    if not dir or dir == "/" then return nil end
    local pdir = dir:match("^(.*)[/\\][^/\\]+$")
    if pdir == "" then pdir = "/" end
    return pdir
end

local function matches(name)
    return not Lib.filter or name:lower():find(Lib.filter:lower(), 1, true) ~= nil
end

local rail = {
    { "browse", "folder", "Browse folder" },
    { "recent", "history", "Recent" },
    { "playlists", "list-music", "Playlists" },
}

local function row(id, x, y, w, rh, icon, text, o)
    local s, b = ctx.s, ctx.b
    o = o or {}
    local hov = ctx.hover == id or ctx.hover == id .. ":add"
    if o.current then
        b:rect(x, y + 1 * s, w, rh - 2 * s, { color = D.T.accent_dim, r = 5 * s })
    elseif hov then
        b:rect(x, y + 1 * s, w, rh - 2 * s, { color = D.T.surface, r = 5 * s })
    end
    b:icon(x + 16 * s, y + rh / 2 - (o.sub and 7 * s or 0), icon, { size = 16 * s, color = o.current and D.T.accent or (o.icon_color or D.T.text2) })
    local right = x + w - 10 * s
    if hov and o.on_add then
        U.icon_button(id .. ":add", right - 10 * s, y + rh / 2, "plus", { size = 15, box = 26, tooltip = "Add to queue", on_click = o.on_add })
        right = right - 32 * s
    elseif o.hint then
        b:text(right, y + rh / 2, o.hint, { align = 6, size = 12 * s, color = D.T.text3 })
        right = right - D.text_width(o.hint, 12 * s) - 10 * s
    end
    local ty = o.sub and (y + rh / 2 - 8 * s) or (y + rh / 2)
    b:text(x + 36 * s, ty, text, { size = 14 * s, color = (o.current or hov) and D.T.text or D.T.text2, clip = { x, y, right, y + rh } })
    if o.sub then
        b:text(x + 36 * s, y + rh / 2 + 10 * s, o.sub, { size = 12 * s, color = D.T.text3, clip = { x, y, right, y + rh } })
    end
    if o.progress then
        local px, pw = x + 36 * s, right - x - 44 * s
        b:rect(px, y + rh - 6 * s, pw, 2 * s, { color = D.T.line })
        b:rect(px, y + rh - 6 * s, pw * U.clamp(o.progress, 0, 1), 2 * s, { color = D.T.accent })
    end
    U.region(id, x, y, w, rh, { click = o.on_click, rclick = o.on_rclick, tooltip = o.tooltip })
end

local function draw_browse(x, y, w, h)
    local s, b = ctx.s, ctx.b
    local pad = 14 * s
    -- header: back / forward / folder name / actions
    local cy = y + 26 * s
    U.icon_button("lib:back", x + pad + 10 * s, cy, "arrow-left", {
        size = 17, tooltip = "Back",
        color = (#Lib.back == 0 and not parent(Lib.dir)) and D.T.text3 or nil,
        on_click = function()
            if #Lib.back > 0 then
                Lib.fwd[#Lib.fwd + 1] = Lib.dir
                Lib.set_dir(table.remove(Lib.back), true)
            elseif parent(Lib.dir) then
                Lib.fwd[#Lib.fwd + 1] = Lib.dir
                Lib.set_dir(parent(Lib.dir), true)
            end
        end,
    })
    U.icon_button("lib:fwd", x + pad + 42 * s, cy, "arrow-right", {
        size = 17, tooltip = "Forward", color = #Lib.fwd == 0 and D.T.text3 or nil,
        on_click = function()
            if #Lib.fwd > 0 then
                Lib.back[#Lib.back + 1] = Lib.dir
                Lib.set_dir(table.remove(Lib.fwd), true)
            end
        end,
    })
    -- breadcrumb: parent › current (click parent to go up)
    local name = media.basename(Lib.dir or "") ~= "" and media.basename(Lib.dir) or (Lib.dir or "")
    local par = parent(Lib.dir)
    local bx = x + pad + 64 * s
    local avail = x + w - pad - 70 * s - bx
    if par then
        local pname = media.basename(par) ~= "" and media.basename(par) or par
        pname = D.ellipsize(pname, 14 * s, avail * 0.4)
        local pw = D.text_width(pname, 14 * s)
        local phov = ctx.hover == "lib:parent"
        b:text(bx, cy, pname, { size = 14 * s, color = phov and D.T.text or D.T.text3 })
        U.region("lib:parent", bx - 4 * s, cy - 12 * s, pw + 8 * s, 24 * s, { click = function() Lib.set_dir(par) end, tooltip = par })
        b:icon(bx + pw + 10 * s, cy, "chevron-right", { size = 12 * s, color = D.T.text3 })
        bx = bx + pw + 20 * s
    end
    b:text(bx, cy, D.ellipsize(name, 15 * s, x + w - pad - 70 * s - bx), { size = 15 * s, color = D.T.text, bold = true })
    U.icon_button("lib:more", x + w - pad - 12 * s, cy, "ellipsis", {
        size = 17, tooltip = "More",
        on_click = function()
            local l = listing()
            ctx.api.open_menu({
                { label = "Play all", icon = "play", action = function()
                    local paths = {}
                    for _, f in ipairs(l.files) do paths[#paths + 1] = f.path end
                    if #paths > 0 then media.open_paths(paths, "replace") end
                end },
                { label = "Add all to queue", icon = "list", action = function()
                    for _, f in ipairs(l.files) do mp.commandv("loadfile", f.path, "append-play") end
                    ctx.toast(nil, #l.files .. " files added to the queue")
                end },
                { separator = true },
                { label = "Find subtitles for this folder…", icon = "captions", action = function()
                    ctx.api.open_subtitles("folder", "online")
                end },
                { label = "Rename files…", icon = "type", action = function() ctx.api.rename_folder(Lib.dir) end },
                { separator = true },
                { label = "Go to playing file", icon = "monitor-play", action = Lib.follow_current },
                { label = "Open another folder…", icon = "folder-open", action = function()
                    media.pick("folder", function(list) Lib.set_dir(list[1]) end)
                end },
                { label = "Home folder", icon = "house", action = function() Lib.set_dir(os.getenv("HOME")) end },
            }, x + w - pad - 24 * s, cy + 18 * s, { align = "right" })
        end,
    })
    U.icon_button("lib:popout", x + w - pad - 44 * s, cy, "search", {
        size = 16, active = Lib.filter ~= nil, tooltip = "Filter",
        on_click = function()
            media.prompt("Filter:", Lib.filter or "", function(t)
                Lib.filter = (t and t ~= "") and t or nil
                ctx.request_render()
            end)
        end,
    })

    local l = listing()
    local dirs, files = {}, {}
    for _, d in ipairs(l.dirs) do if matches(d.name) then dirs[#dirs + 1] = d end end
    for _, f in ipairs(l.files) do if matches(f.name) then files[#files + 1] = f end end
    local count = #dirs + #files
    b:text(x + pad, y + 64 * s, count .. (count == 1 and " item" or " items") .. (Lib.filter and ("  ·  \"" .. Lib.filter .. "\"") or ""),
        { size = 12 * s, color = D.T.text3 })
    if Lib.filter then
        U.icon_button("lib:clearf", x + w - pad - 12 * s, y + 64 * s, "x", { size = 13, box = 22, tooltip = "Clear filter", on_click = function() Lib.filter = nil end })
    end
    b:rect(x + pad, y + 80 * s, w - 2 * pad, 1 * s, { color = D.T.line })

    local ly = y + 86 * s
    local lh = y + h - ly
    local top = U.scroll_begin("lib:list", x, ly, w, lh)
    local rh = 40 * s
    local cy2 = top
    local playing = media.abspath(mp.get_property("path"))
    for i, d in ipairs(dirs) do
        row("lib:d:" .. i, x + 6 * s, cy2, w - 12 * s, rh, "folder", d.name, {
            on_click = function() Lib.set_dir(d.path) end,
            on_add = function()
                local n = 0
                for _, f in ipairs(media.list_dir(d.path).files) do mp.commandv("loadfile", f.path, "append-play"); n = n + 1 end
                ctx.toast(nil, n .. " files added to the queue")
            end,
        })
        cy2 = cy2 + rh
    end
    for i, f in ipairs(files) do
        local e = media.history_entry(f.path)
        local prog = (e and e.dur and e.dur > 0 and e.pos and e.pos > 5) and (e.pos / e.dur) or nil
        row("lib:f:" .. i, x + 6 * s, cy2, w - 12 * s, rh, f.audio and "music" or "film", f.name, {
            current = f.path == playing,
            progress = prog,
            on_click = function() media.play_folder_from(Lib.dir, f.path) end,
            on_add = function() mp.commandv("loadfile", f.path, "append-play"); ctx.toast(nil, "Added to queue: " .. f.name) end,
            on_rclick = function()
                ctx.api.open_menu({
                    { label = "Play", icon = "play", action = function() media.play_folder_from(Lib.dir, f.path) end },
                    { label = "Add to queue", icon = "list", action = function() mp.commandv("loadfile", f.path, "append-play") end },
                    { separator = true },
                    { label = "Rename…", icon = "type", hint = "F2", action = function() ctx.api.rename_file(f.path) end },
                    { label = "Rename files in this folder…", icon = "folder", action = function() ctx.api.rename_folder(Lib.dir) end },
                }, ctx.mouse.x, ctx.mouse.y)
            end,
            tooltip = f.name .. "  ·  right-click for more",
        })
        cy2 = cy2 + rh
    end
    if count == 0 then
        b:text(x + w / 2, ly + 40 * s, Lib.filter and "Nothing matches the filter" or "No media in this folder", { align = 5, size = 13 * s, color = D.T.text3 })
    end
    U.scroll_end("lib:list", x, ly, w, lh, cy2 - top + 10 * s)
end

local function draw_recent(x, y, w, h)
    local s, b = ctx.s, ctx.b
    local pad = 14 * s
    U.header(x + pad + 4 * s, y + 26 * s, "Recent")
    U.icon_button("lib:clearh", x + w - pad - 12 * s, y + 26 * s, "trash", {
        size = 15, tooltip = "Clear history", on_click = function() media.clear_history() end,
    })
    b:rect(x + pad, y + 50 * s, w - 2 * pad, 1 * s, { color = D.T.line })
    local ly = y + 56 * s
    local lh = y + h - ly
    local top = U.scroll_begin("lib:recent", x, ly, w, lh)
    local rh = 48 * s
    local cy = top
    local hist = media.store.history
    if #hist == 0 then
        b:text(x + w / 2, ly + 40 * s, "Nothing played yet", { align = 5, size = 13 * s, color = D.T.text3 })
    end
    for i, e in ipairs(hist) do
        local folder = media.dirname(e.path)
        local sub = (folder and media.basename(folder) or "") .. (e.dur and e.dur > 0 and ("  ·  " .. media.fmt_time(e.pos or 0) .. " / " .. media.fmt_time(e.dur)) or "")
        row("lib:h:" .. i, x + 6 * s, cy, w - 12 * s, rh, media.is_url(e.path) and "link" or (media.audio_ext[media.ext(e.path)] and "music" or "film"),
            e.title or media.basename(e.path), {
                sub = sub,
                progress = (e.dur and e.dur > 0) and (e.pos or 0) / e.dur or nil,
                on_click = function() mp.commandv("loadfile", e.path, "replace") end,
                on_add = function() mp.commandv("loadfile", e.path, "append-play") end,
                tooltip = e.path,
            })
        cy = cy + rh
    end
    U.scroll_end("lib:recent", x, ly, w, lh, cy - top + 10 * s)
end

local function draw_playlists(x, y, w, h)
    local s, b = ctx.s, ctx.b
    local pad = 14 * s
    U.header(x + pad + 4 * s, y + 26 * s, "Playlists")
    local lists = media.list_playlists()
    b:text(x + pad + 4 * s, y + 64 * s, #lists .. (#lists == 1 and " item" or " items"), { size = 12 * s, color = D.T.text3 })
    b:rect(x + pad, y + 80 * s, w - 2 * pad, 1 * s, { color = D.T.line })
    local ly = y + 86 * s
    local rh = 40 * s
    local cy = ly
    row("lib:pl:new", x + 6 * s, cy, w - 12 * s, rh, "plus", "Create playlist from queue", { on_click = media.save_queue_as_playlist })
    cy = cy + rh
    for i, pl in ipairs(lists) do
        row("lib:pl:" .. i, x + 6 * s, cy, w - 12 * s, rh, "list-music", pl.name, {
            on_click = function() mp.commandv("loadfile", pl.path, "replace") end,
            on_add = function() mp.commandv("loadfile", pl.path, "append-play") end,
            on_rclick = function()
                ctx.api.open_menu({
                    { label = "Play", icon = "play", action = function() mp.commandv("loadfile", pl.path, "replace") end },
                    { label = "Add to queue", icon = "list", action = function() mp.commandv("loadfile", pl.path, "append-play") end },
                    { separator = true },
                    { label = "Delete playlist", icon = "trash", icon_color = "c0462c", action = function() os.remove(pl.path) end },
                }, ctx.mouse.x, ctx.mouse.y)
            end,
            tooltip = "Right-click for more",
        })
        cy = cy + rh
    end
end

function Lib.draw(x, y, w, h)
    local s, b = ctx.s, ctx.b
    b:rect(x, y, w, h, { color = D.T.panel })
    U.region("lib:bg", x, y, w, h, { block = true, hover = false })
    -- icon rail
    local rw = 52 * s
    b:rect(x, y, rw, h, { color = "191919" })
    for i, it in ipairs(rail) do
        local cy = y + 24 * s + (i - 1) * 46 * s
        U.icon_button("lib:rail:" .. it[1], x + rw / 2, cy, it[2], {
            size = 18, active = Lib.view == it[1], tooltip = it[3],
            on_click = function() Lib.view = it[1] end,
        })
    end
    local cy = y + 24 * s + #rail * 46 * s
    U.icon_button("lib:rail:url", x + rw / 2, cy, "radio", { size = 18, tooltip = "Open network stream", on_click = media.open_url })
    U.icon_button("lib:rail:add", x + rw / 2, cy + 46 * s, "plus", { size = 18, tooltip = "Open files", on_click = function() media.open_dialog() end })

    local cx, cw = x + rw, w - rw
    if Lib.view == "recent" then draw_recent(cx, y, cw, h)
    elseif Lib.view == "playlists" then draw_playlists(cx, y, cw, h)
    else draw_browse(cx, y, cw, h) end
end

return Lib
