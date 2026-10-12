-- File renaming: rename the playing file (F2) or a whole folder with a live preview and Undo.
-- Matching subtitle files (video.en.srt …) are renamed along with their video.
local mp = require 'mp'
local utils = require 'mp.utils'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'

local R = {
    dir = nil,
    find = "", replace = "",
    pattern = "{name}",
    clean = false,
    subs = true,
    undo = nil,      -- list of { from, to } of the last rename
    status = nil,
}

local windows = package.config:sub(1, 1) == "\\"

local function split(name)
    local base, ext = name:match("^(.*)%.([%w]+)$")
    if not base then return name, nil end
    return base, ext
end

local function sanitize(name)
    name = name:gsub("[/%z]", "-")
    if windows then name = name:gsub('[<>:"\\|%?%*]', "-") end
    return (name:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- subtitle files belonging to a video: "<base>.srt", "<base>.en.srt", "<base>.forced.en.ass", …
local function sidecars(dir, base)
    local out = {}
    for _, f in ipairs(utils.readdir(dir, "files") or {}) do
        if f:sub(1, #base + 1) == base .. "." and media.sub_ext[media.ext(f)] then
            out[#out + 1] = f
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Core: apply a list of renames safely (two phases, so A->B, B->A swaps work)
---------------------------------------------------------------------------
local function update_references(map)
    -- history, bookmarks
    for _, e in ipairs(media.store.history) do
        if map[e.path] then e.path = map[e.path] end
    end
    for old, new in pairs(map) do
        if media.store.bookmarks[old] then
            media.store.bookmarks[new] = media.store.bookmarks[old]
            media.store.bookmarks[old] = nil
        end
    end
    media.save_store()
    -- playlist entries
    local list = mp.get_property_native("playlist") or {}
    local cur_new
    for i = #list, 1, -1 do
        local it = list[i]
        local new = map[media.abspath(it.filename)]
        if new then
            if it.current then
                cur_new = { index = i - 1, path = new }
            else
                mp.commandv("loadfile", new, "insert-at", tostring(i - 1))
                mp.commandv("playlist-remove", tostring(i))
            end
        end
    end
    if cur_new then
        -- keep watching: open the renamed file at the same position, then drop the old entry
        local pos = mp.get_property_number("time-pos", 0)
        local paused = mp.get_property_bool("pause")
        mp.commandv("loadfile", cur_new.path, "insert-at", tostring(cur_new.index + 1),
            string.format("start=%.3f,pause=%s", pos, paused and "yes" or "no"))
        mp.commandv("playlist-play-index", tostring(cur_new.index + 1))
        mp.commandv("playlist-remove", tostring(cur_new.index))
    end
end

-- ops: list of { from = path, to = path }. Returns done list and error message.
local function apply(ops)
    local stamp = tostring(os.time())
    local staged, done = {}, {}
    for i, op in ipairs(ops) do
        local tmp = op.from .. ".vlcui-rename-" .. stamp .. "-" .. i
        local ok, err = os.rename(op.from, tmp)
        if not ok then
            -- roll back what was staged
            for _, st in ipairs(staged) do os.rename(st.tmp, st.from) end
            return {}, (err or "rename failed") .. (windows and " (is the file open in another program?)" or "")
        end
        staged[#staged + 1] = { from = op.from, tmp = tmp, to = op.to }
    end
    local err_msg
    for _, st in ipairs(staged) do
        local ok, err = os.rename(st.tmp, st.to)
        if ok then
            done[#done + 1] = { from = st.from, to = st.to }
        else
            os.rename(st.tmp, st.from)
            err_msg = err_msg or err
        end
    end
    local map = {}
    for _, d in ipairs(done) do map[d.from] = d.to end
    ctx.fs_version = (ctx.fs_version or 0) + 1
    update_references(map)
    return done, err_msg
end

---------------------------------------------------------------------------
-- Single file
---------------------------------------------------------------------------
function R.rename_file(path)
    path = media.abspath(path or mp.get_property("path"))
    if not path or media.is_url(path) then return ctx.toast(nil, "Only local files can be renamed") end
    local dir, name = media.dirname(path), media.basename(path)
    local base, ext = split(name)
    media.prompt("Rename to:", name, function(text)
        text = sanitize(text or "")
        if text == "" or text == name then return end
        if not text:find("%.[%w]+$") and ext then text = text .. "." .. ext end
        local target = utils.join_path(dir, text)
        if media.file_exists(target) then return ctx.toast(nil, "A file named \"" .. text .. "\" already exists") end
        local ops = { { from = path, to = target } }
        local new_base = split(text)
        for _, sc in ipairs(sidecars(dir, base)) do
            local dest = utils.join_path(dir, new_base .. sc:sub(#base + 1))
            if not media.file_exists(dest) then ops[#ops + 1] = { from = utils.join_path(dir, sc), to = dest } end
        end
        local done, err = apply(ops)
        if err then return ctx.toast(nil, "Rename failed: " .. err, 3) end
        R.undo = done
        ctx.toast("F2", "Renamed to " .. text .. (#done > 1 and (" (+" .. (#done - 1) .. " subtitle)") or ""), 2.5)
    end)
end

---------------------------------------------------------------------------
-- Batch (folder)
---------------------------------------------------------------------------
local function pad(n, width) return string.format("%0" .. width .. "d", n) end

function R.preview()
    local files = media.list_dir(R.dir).files
    local width = math.max(2, #tostring(#files))
    local rows, targets = {}, {}
    local olds = {}
    for _, f in ipairs(files) do olds[f.name] = true end
    for i, f in ipairs(files) do
        local base, ext = split(f.name)
        local name = base
        if R.find ~= "" then name = name:gsub(R.find:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"), (R.replace:gsub("%%", "%%%%"))) end
        if R.clean then name = name:gsub("[%._]+", " "):gsub("%s+", " ") end
        local p = media.parse_name(name .. (ext and ("." .. ext) or "")) -- so find/replace also changes {show}
        local show = p.show
        local new = R.pattern
            :gsub("{name}", (name:gsub("%%", "%%%%")))
            :gsub("{show}", (show:gsub("%%", "%%%%")))
            :gsub("{season}", p.season and pad(p.season, 2) or "")
            :gsub("{episode}", p.episode and pad(p.episode, 2) or "")
            :gsub("{year}", p.year and tostring(p.year) or "")
            :gsub("{n}", pad(i, width))
        new = sanitize(new:gsub("%s+", " "))
        if ext then new = new .. "." .. ext end
        local row = { path = f.path, old = f.name, new = new, base = base }
        local needs_ep = R.pattern:find("{episode}", 1, true) or R.pattern:find("{season}", 1, true)
        if needs_ep and (not p.episode or (R.pattern:find("{season}", 1, true) and not p.season)) then
            row.new, row.problem = f.name, "no season/episode in the name"
        elseif new == "" or new == "." .. (ext or "") then
            row.problem = "empty name"
        elseif new ~= f.name then
            if targets[new:lower()] then
                row.problem = "duplicate name"
                targets[new:lower()].problem = "duplicate name"
            elseif media.file_exists(utils.join_path(R.dir, new)) and not olds[new] then
                row.problem = "already exists"
            end
            targets[new:lower()] = row
        end
        rows[#rows + 1] = row
    end
    return rows
end

function R.apply_batch()
    local ops = {}
    local count = 0
    for _, row in ipairs(R.preview()) do
        if row.new ~= row.old and not row.problem then
            ops[#ops + 1] = { from = row.path, to = utils.join_path(R.dir, row.new) }
            count = count + 1
            if R.subs then
                local new_base = split(row.new)
                for _, sc in ipairs(sidecars(R.dir, row.base)) do
                    local dest = utils.join_path(R.dir, new_base .. sc:sub(#row.base + 1))
                    if not media.file_exists(dest) then ops[#ops + 1] = { from = utils.join_path(R.dir, sc), to = dest } end
                end
            end
        end
    end
    if #ops == 0 then R.status = "Nothing to rename"; return end
    local done, err = apply(ops)
    R.undo = done
    R.status = err and ("Stopped: " .. err) or string.format("Renamed %d files (%d with subtitles). You can undo this.", count, #done)
    ctx.toast(nil, string.format("Renamed %d files", count))
end

function R.undo_last()
    if not R.undo or #R.undo == 0 then return ctx.toast(nil, "Nothing to undo") end
    local ops = {}
    for _, d in ipairs(R.undo) do ops[#ops + 1] = { from = d.to, to = d.from } end
    local done, err = apply(ops)
    R.undo = nil
    R.status = err and ("Undo stopped: " .. err) or ("Undid " .. #done .. " renames")
    ctx.toast(nil, err and "Undo failed" or "Rename undone")
end

function R.open(dir)
    dir = dir or media.dirname(media.abspath(mp.get_property("path")))
    if not dir then return ctx.toast(nil, "Open a local file or folder first") end
    if dir ~= R.dir then R.find, R.replace, R.status = "", "", nil end
    R.dir = dir
    ctx.modal = "rename"
    ctx.request_render()
end

local patterns = {
    { label = "Keep the name", value = "{name}" },
    { label = "Show - S01E02", value = "{show} - S{season}E{episode}" },
    { label = "Show S01E02", value = "{show} S{season}E{episode}" },
    { label = "S01E02 - name", value = "S{season}E{episode} - {name}" },
    { label = "01 - name", value = "{n} - {name}" },
    { label = "Custom…", value = "__custom" },
}

function R.draw()
    local s, b = ctx.s, ctx.b
    local close = function() ctx.modal = nil end
    local x, y, w, h = U.modal("ren", "Rename files", 920 * s, 660 * s, close)
    local y0 = y
    -- folder
    b:icon(x + 8 * s, y + 17 * s, "folder", { size = 16 * s, color = D.T.text2 })
    local shown = (R.dir or ""):gsub("^" .. (os.getenv("HOME") or "\0"):gsub("%p", "%%%0"), "~")
    local parts = {}
    for part in shown:gmatch("[^/\\]+") do parts[#parts + 1] = part end
    if #parts > 3 then shown = "…/" .. table.concat(parts, "/", #parts - 2) end
    b:text(x + 26 * s, y + 17 * s, shown, { size = 13 * s, color = D.T.text2, clip = { x, y, x + w - 170 * s, y + 34 * s } })
    U.button("ren:dir", x + w - 160 * s, y, 160 * s, 34 * s, "Choose folder…", {
        icon = "folder-open", size = 13, on_click = function() media.pick("folder", function(l) R.open(l[1]) end) end,
    })
    y = y + 48 * s

    -- find / replace / pattern
    local col = (w - 20 * s) / 3
    local function field(id, label, value, xx, prompt, cb)
        b:text(xx, y + 8 * s, label, { size = 12 * s, color = D.T.text3 })
        U.box(id, xx, y + 20 * s, col, 34 * s, value, {
            placeholder = "—",
            on_click = function() media.prompt(prompt, value, function(t) cb(t or ""); R.status = nil; ctx.request_render() end) end,
        })
    end
    field("ren:find", "Find", R.find, x, "Find text:", function(t) R.find = t end)
    field("ren:repl", "Replace with", R.replace, x + col + 10 * s, "Replace with:", function(t) R.replace = t end)
    b:text(x + 2 * (col + 10 * s), y + 8 * s, "New name", { size = 12 * s, color = D.T.text3 })
    local plabel
    for _, pt in ipairs(patterns) do if pt.value == R.pattern then plabel = pt.label end end
    U.dropdown("ren:pattern", x + 2 * (col + 10 * s), y + 20 * s, col, 34 * s, patterns, R.pattern, function(v)
        if v == "__custom" then
            media.prompt("Pattern ({name} {show} {season} {episode} {n} {year}):", R.pattern, function(t)
                if t and t ~= "" then R.pattern = t; ctx.request_render() end
            end)
        else
            R.pattern = v
        end
        R.status = nil
    end, { label = plabel or R.pattern })
    y = y + 66 * s

    -- options
    U.toggle("ren:clean", x + 62 * s, y + 16 * s, R.clean, function() R.clean = not R.clean end)
    b:text(x + 74 * s, y + 16 * s, "Turn dots and underscores into spaces", { size = 13 * s, color = D.T.text2 })
    U.toggle("ren:subs", x + w * 0.5 + 62 * s, y + 16 * s, R.subs, function() R.subs = not R.subs end)
    b:text(x + w * 0.5 + 74 * s, y + 16 * s, "Also rename matching subtitle files", { size = 13 * s, color = D.T.text2 })
    y = y + 44 * s

    -- preview
    local rows = R.preview()
    local changes, problems = 0, 0
    for _, r in ipairs(rows) do
        if r.problem then problems = problems + 1 elseif r.new ~= r.old then changes = changes + 1 end
    end
    b:rect(x, y, w, 1 * s, { color = "202020" })
    local foot_h = 52 * s
    local ly, lh = y + 6 * s, y0 + h - foot_h - (y + 6 * s)
    local top = U.scroll_begin("ren:list", x, ly, w, lh)
    local rh = 34 * s
    local half = (w - 40 * s) / 2
    local cy = top
    local playing = media.abspath(mp.get_property("path"))
    for _, r in ipairs(rows) do
        local changed = r.new ~= r.old
        local c1 = changed and D.T.text2 or D.T.text3
        if r.path == playing then b:icon(x + 6 * s, cy + rh / 2, "play", { size = 12 * s, color = D.T.accent }) end
        b:text(x + 20 * s, cy + rh / 2, r.old, { size = 13 * s, color = c1, clip = { x, cy, x + half, cy + rh } })
        b:icon(x + half + 20 * s, cy + rh / 2, "arrow-right", { size = 13 * s, color = changed and D.T.accent or D.T.text3 })
        local c2 = r.problem and "e8504a" or (changed and D.T.text or D.T.text3)
        local nx = x + half + 40 * s
        b:text(nx, cy + rh / 2, r.new .. (r.problem and ("   (" .. r.problem .. ")") or ""), { size = 13 * s, color = c2, clip = { nx, cy, x + w, cy + rh } })
        cy = cy + rh
    end
    if #rows == 0 then b:text(x + w / 2, ly + 40 * s, "No media files in this folder", { align = 5, size = 13 * s, color = D.T.text3 }) end
    U.scroll_end("ren:list", x, ly, w, lh, cy - top + 10 * s)

    -- footer
    local fy = y0 + h - foot_h + 10 * s
    local info = R.status or string.format("%d of %d files will be renamed%s", changes, #rows, problems > 0 and string.format(" · %d skipped (see red)", problems) or "")
    b:text(x, fy + 18 * s, info, { size = 13 * s, color = D.T.text2, clip = { x, fy, x + w - 330 * s, fy + 40 * s } })
    if R.undo and #R.undo > 0 then
        U.button("ren:undo", x + w - 320 * s, fy, 110 * s, 36 * s, "Undo", { icon = "undo", on_click = R.undo_last })
    end
    U.button("ren:apply", x + w - 200 * s, fy, 200 * s, 36 * s, "Rename " .. changes .. " files", {
        primary = changes > 0, icon = "check", on_click = function() if changes > 0 then R.apply_batch() end end,
    })
end

return R
