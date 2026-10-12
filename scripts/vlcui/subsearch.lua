-- "Add subtitles" dialog: for this file or a whole folder, from this computer or from OpenSubtitles.
-- OpenSubtitles REST API (api.opensubtitles.com) needs a free API key: Settings → Subtitle downloads.
local mp = require 'mp'
local utils = require 'mp.utils'
local ctx = require 'ctx'
local D = require 'draw'
local U = require 'ui'
local media = require 'media'

local O = {
    target = "file",     -- file | folder
    source = "online",   -- online | local
    query = "", lang = "en",
    results = nil, status = nil, busy = false,
    pick_for = nil,      -- folder row index whose alternatives are shown
    rows = nil, dir = nil,
    token = nil,
}

local APP = "mpv-vlc-redesign v1.1"

---------------------------------------------------------------------------
-- Config
---------------------------------------------------------------------------
function O.api_url() return (ctx.opts.opensubtitles_api_url or "https://api.opensubtitles.com/api/v1"):gsub("/$", "") end
function O.api_key()
    local k = media.setting("os_api_key", "")
    if k == "" then k = ctx.opts.opensubtitles_api_key or "" end
    return k
end
local function creds()
    local u = media.setting("os_username", "")
    local p = media.setting("os_password", "")
    if u == "" then u = ctx.opts.opensubtitles_username or "" end
    if p == "" then p = ctx.opts.opensubtitles_password or "" end
    return u, p
end

---------------------------------------------------------------------------
-- HTTP (curl)
---------------------------------------------------------------------------
local function urlencode(s)
    -- the API redirects unless spaces are "+" and parameters are sorted + lowercase
    return (tostring(s):gsub("[^%w%-%._~ ]", function(c) return string.format("%%%02X", c:byte()) end):gsub(" ", "+"))
end

local function http(method, url, body, cb, extra_headers)
    if not media.find_exe("curl") then
        cb(0, nil, "curl is not installed")
        return
    end
    local args = { "curl", "-sS", "-L", "--max-time", "30", "-X", method,
        "-H", "Accept: application/json", "-H", "User-Agent: " .. APP, "-w", "\n%{http_code}" }
    local key = O.api_key()
    if key ~= "" then args[#args + 1] = "-H"; args[#args + 1] = "Api-Key: " .. key end
    for _, h in ipairs(extra_headers or {}) do args[#args + 1] = "-H"; args[#args + 1] = h end
    if body then
        args[#args + 1] = "-H"; args[#args + 1] = "Content-Type: application/json"
        args[#args + 1] = "--data-binary"; args[#args + 1] = utils.format_json(body)
    end
    args[#args + 1] = url
    mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true, capture_stderr = true, playback_only = false },
        function(ok, res)
            if not ok or not res or res.status ~= 0 then
                cb(0, nil, (res and res.stderr ~= "" and res.stderr) or "network error")
                return
            end
            local out = res.stdout or ""
            local text, code = out:match("^(.*)\n(%d%d%d)$")
            code = tonumber(code) or 0
            local json = text and utils.parse_json(text) or nil
            cb(code, json, text)
        end)
end

local function api_error(code, json, text)
    if code == 0 then return text or "network error" end
    if code == 401 or code == 403 then
        return (json and json.message) or "OpenSubtitles rejected the API key or login (" .. code .. ")"
    end
    if code == 406 or code == 429 then
        return (json and json.message) or "Download limit reached, try again later"
    end
    return (json and (json.message or json.error)) or ("OpenSubtitles error " .. code)
end

---------------------------------------------------------------------------
-- OpenSubtitles movie hash (file size + 64-bit sums of the first/last 64 KiB)
---------------------------------------------------------------------------
function O.hash(path)
    if not path or media.is_url(path) then return nil end
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    if not size or size < 131072 then f:close(); return nil end
    local lo, hi = size % 4294967296, math.floor(size / 4294967296)
    local function chunk(data)
        for i = 1, 65536, 8 do
            local b1, b2, b3, b4, b5, b6, b7, b8 = data:byte(i, i + 7)
            lo = lo + b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
            hi = hi + b5 + b6 * 256 + b7 * 65536 + b8 * 16777216
        end
    end
    f:seek("set", 0); chunk(f:read(65536))
    f:seek("set", size - 65536); chunk(f:read(65536))
    f:close()
    hi = (hi + math.floor(lo / 4294967296)) % 4294967296
    lo = lo % 4294967296
    return string.format("%08x%08x", hi, lo)
end

---------------------------------------------------------------------------
-- API calls
---------------------------------------------------------------------------
-- params: query, languages, moviehash, season_number, episode_number, year
function O.search(params, cb)
    local keys = {}
    for k, v in pairs(params) do if v ~= nil and v ~= "" then keys[#keys + 1] = k end end
    table.sort(keys) -- the API wants sorted, lowercase parameters
    local q = {}
    for _, k in ipairs(keys) do q[#q + 1] = k .. "=" .. urlencode(tostring(params[k]):lower()) end
    http("GET", O.api_url() .. "/subtitles?" .. table.concat(q, "&"), nil, function(code, json, text)
        if code ~= 200 or type(json) ~= "table" then return cb(nil, api_error(code, json, text)) end
        local list = {}
        for _, it in ipairs(json.data or {}) do
            local a = it.attributes or {}
            local file = (a.files or {})[1]
            if file and file.file_id then
                local fd = a.feature_details or {}
                list[#list + 1] = {
                    file_id = file.file_id,
                    name = (a.release and a.release ~= "") and a.release or (file.file_name or "subtitle"),
                    lang = a.language or "",
                    downloads = a.download_count or 0,
                    hi = a.hearing_impaired == true,
                    match = a.moviehash_match == true,
                    trusted = a.from_trusted == true,
                    ai = a.ai_translated == true or a.machine_translated == true,
                    title = fd.title or fd.movie_name,
                    season = fd.season_number, episode = fd.episode_number,
                }
            end
        end
        table.sort(list, function(x, y)
            if x.match ~= y.match then return x.match end
            if x.ai ~= y.ai then return y.ai end
            if x.trusted ~= y.trusted then return x.trusted end
            return x.downloads > y.downloads
        end)
        cb(list)
    end)
end

local function login(cb)
    local u, p = creds()
    if O.token or u == "" then return cb(O.token) end
    http("POST", O.api_url() .. "/login", { username = u, password = p }, function(code, json, text)
        if code == 200 and json and json.token then
            O.token = json.token
            cb(O.token)
        else
            cb(nil, api_error(code, json, text))
        end
    end)
end

-- Downloads a subtitle next to `video` as <video name>.<lang>.<ext>; cb(path, err, remaining)
function O.download(item, video, cb)
    login(function(token, lerr)
        if lerr then return cb(nil, "Login failed: " .. lerr) end
        local headers = token and { "Authorization: Bearer " .. token } or nil
        http("POST", O.api_url() .. "/download", { file_id = item.file_id }, function(code, json, text)
            if code ~= 200 or not json or not json.link then return cb(nil, api_error(code, json, text)) end
            local ext = (json.file_name or ""):match("%.(%w+)$") or "srt"
            local dir = video and media.dirname(video) or nil
            local base = video and media.basename(video):gsub("%.[%w]+$", "") or "subtitle"
            local lang = (item.lang ~= "" and item.lang) or O.lang
            local dest = dir and media.unique_path(dir, base .. "." .. lang, ext)
            local probe = dest and io.open(dest, "wb")
            if probe then probe:close(); os.remove(dest) else
                local fallback = mp.command_native({ "expand-path", "~~state/vlcui-subs" })
                media.mkdir(fallback)
                dest = media.unique_path(fallback, base .. "." .. lang, ext)
            end
            mp.command_native_async({ name = "subprocess", playback_only = false, capture_stdout = true, capture_stderr = true,
                args = { "curl", "-sS", "-L", "--max-time", "60", "-A", APP, "-o", dest, json.link } }, function(ok, res)
                if ok and res and res.status == 0 and media.file_exists(dest) then
                    cb(dest, nil, json.remaining)
                else
                    cb(nil, "Download failed")
                end
            end)
        end, headers)
    end)
end

---------------------------------------------------------------------------
-- Dialog state helpers
---------------------------------------------------------------------------
local function playing_path()
    local p = mp.get_property("path")
    return p and media.abspath(p)
end

local function default_lang()
    local sl = mp.get_property_native("slang")
    if type(sl) == "table" then
        for _, l in ipairs(sl) do if #l == 2 then return l end end
    end
    return "en"
end

local function search_params(path, query)
    local parsed = media.parse_name(query or media.basename(path or ""))
    local params = { languages = O.lang }
    params.query = parsed.show
    if parsed.season then params.season_number = parsed.season end
    if parsed.episode then params.episode_number = parsed.episode end
    if parsed.year and not parsed.episode then params.year = parsed.year end
    return params
end

function O.open(target, source)
    local path = playing_path()
    O.target = target or "file"
    O.source = source or (O.api_key() ~= "" and "online" or "local")
    O.lang = O.lang ~= "" and O.lang or default_lang()
    if path and not media.is_url(path) then
        local pn = media.parse_name(media.basename(path))
        O.query = pn.show .. (pn.season and string.format(" S%02dE%02d", pn.season, pn.episode or 1) or (pn.year and (" " .. pn.year) or ""))
        O.dir = media.dirname(path)
    else
        O.query = mp.get_property("media-title") or ""
    end
    if O.lang == "en" then O.lang = default_lang() end
    O.results, O.status, O.rows, O.pick_for = nil, nil, nil, nil
    ctx.modal = "subs"
    ctx.request_render()
end

local function rows_for_dir()
    if O.rows and O.rows_dir == O.dir then return O.rows end
    O.rows = {}
    O.rows_dir = O.dir
    for _, f in ipairs(media.list_dir(O.dir).files) do
        if not f.audio then
            O.rows[#O.rows + 1] = { path = f.path, name = f.name, parsed = media.parse_name(f.name), status = "" }
        end
    end
    return O.rows
end

local function set_status(msg)
    O.status = msg
    ctx.request_render()
end

-- single file search (also used for "show alternatives" of a folder row)
function O.run_search()
    if O.api_key() == "" then return set_status("Add your OpenSubtitles API key first") end
    local video = O.pick_for and O.rows and O.rows[O.pick_for] and O.rows[O.pick_for].path or playing_path()
    local query = O.pick_for and O.rows[O.pick_for].name or O.query
    local params = search_params(video, query)
    local hash = O.hash(video)
    O.busy = true
    O.results = nil
    set_status("Searching OpenSubtitles…")
    local function done(list, err)
        O.busy = false
        if not list then return set_status(err) end
        O.results = list
        set_status(#list == 0 and "No subtitles found. Try another search or language." or (#list .. " results"))
    end
    if hash then
        params.moviehash = hash
        O.search(params, function(list, err)
            if list and #list > 0 then return done(list) end
            params.moviehash = nil
            O.search(params, done)
        end)
    else
        O.search(params, done)
    end
end

-- folder: best match per episode, one request at a time
function O.find_all()
    if O.api_key() == "" then return set_status("Add your OpenSubtitles API key first") end
    local rows = rows_for_dir()
    local i = 0
    O.busy = true
    local function step()
        i = i + 1
        local row = rows[i]
        if not row then
            O.busy = false
            local found = 0
            for _, r in ipairs(rows) do if r.result then found = found + 1 end end
            return set_status(string.format("Found subtitles for %d of %d files", found, #rows))
        end
        row.status = "searching"
        set_status(string.format("Searching %d / %d…", i, #rows))
        local params = search_params(row.path, row.name)
        params.moviehash = O.hash(row.path)
        O.search(params, function(list)
            if (not list or #list == 0) and params.moviehash then
                params.moviehash = nil
                return O.search(params, function(list2)
                    row.results = list2 or {}
                    row.result = row.results[1]
                    row.status = row.result and "found" or "none"
                    step()
                end)
            end
            row.results = list or {}
            row.result = row.results[1]
            row.status = row.result and "found" or "none"
            step()
        end)
    end
    step()
end

local function attach(video, sub)
    if video == playing_path() then mp.commandv("sub-add", sub, "select") end
end

function O.download_one(item, video)
    video = video or playing_path()
    O.busy = true
    set_status("Downloading " .. item.name .. "…")
    O.download(item, video, function(path, err, remaining)
        O.busy = false
        if not path then return set_status(err) end
        attach(video, path)
        set_status("Saved " .. media.basename(path) .. (remaining and (" · " .. remaining .. " downloads left today") or ""))
        ctx.toast(nil, "Subtitle downloaded")
    end)
end

function O.download_all()
    local rows = rows_for_dir()
    local i = 0
    O.busy = true
    local saved, left = 0, nil
    local function step()
        i = i + 1
        local row = rows[i]
        if not row then
            O.busy = false
            return set_status(string.format("Downloaded %d subtitles%s", saved, left and (" · " .. left .. " downloads left today") or ""))
        end
        if not row.result or row.status == "saved" then return step() end
        row.status = "downloading"
        set_status(string.format("Downloading %d / %d…", i, #rows))
        O.download(row.result, row.path, function(path, err, remaining)
            if path then
                row.status = "saved"; saved = saved + 1; left = remaining or left
                attach(row.path, path)
                step()
            else
                row.status = "error"
                O.busy = false
                set_status(err)
            end
        end)
    end
    step()
end

---------------------------------------------------------------------------
-- From this computer: copy subtitles next to the videos with matching names
---------------------------------------------------------------------------
local function sub_lang(name)
    local l = name:match("%.(%a%a%a?)%.[%w]+$") or name:match("[%._%-](%a%a%a?)%.[%w]+$")
    if l then l = l:lower() end
    local known = { en = 1, eng = 1, es = 1, spa = 1, fr = 1, fre = 1, de = 1, ger = 1, it = 1, ita = 1, pt = 1, por = 1,
        ja = 1, jpn = 1, ru = 1, rus = 1, nl = 1, pl = 1, tr = 1, ar = 1, ko = 1, zh = 1, sv = 1 }
    return known[l or ""] and l or nil
end

function O.local_pick()
    media.pick("subtitle", function(list)
        if O.target == "file" then
            local video = playing_path()
            for _, src in ipairs(list) do
                local dest = src
                if O.save_copy ~= false and video and not media.is_url(video) then
                    local base = media.basename(video):gsub("%.[%w]+$", "")
                    local l = sub_lang(media.basename(src))
                    local ext = media.ext(src)
                    if media.dirname(src) ~= media.dirname(video) or not media.basename(src):find(base, 1, true) then
                        dest = media.unique_path(media.dirname(video), base .. (l and ("." .. l) or ""), ext)
                        if not media.copy_file(src, dest) then dest = src end
                    end
                end
                mp.commandv("sub-add", dest, "select")
            end
            ctx.modal = nil
            ctx.toast(nil, #list > 1 and (#list .. " subtitles added") or "Subtitle added")
            return
        end
        -- folder: match by season/episode, then by order
        local rows = rows_for_dir()
        local subs = {}
        for _, src in ipairs(list) do
            subs[#subs + 1] = { path = src, name = media.basename(src), parsed = media.parse_name(media.basename(src)) }
        end
        table.sort(subs, function(a, b) return media.natural_lt(a.name, b.name) end)
        local used = {}
        for _, row in ipairs(rows) do
            row.local_sub = nil
            for j, sb in ipairs(subs) do
                if not used[j] and row.parsed.episode and sb.parsed.episode == row.parsed.episode
                    and (not row.parsed.season or not sb.parsed.season or sb.parsed.season == row.parsed.season) then
                    row.local_sub, used[j] = sb, true
                    break
                end
            end
        end
        local unmatched_rows, unmatched_subs = {}, {}
        for _, row in ipairs(rows) do if not row.local_sub then unmatched_rows[#unmatched_rows + 1] = row end end
        for j, sb in ipairs(subs) do if not used[j] then unmatched_subs[#unmatched_subs + 1] = sb end end
        for k = 1, math.min(#unmatched_rows, #unmatched_subs) do unmatched_rows[k].local_sub = unmatched_subs[k] end
        for _, row in ipairs(rows) do row.status = row.local_sub and "matched" or "" end
        set_status("Check the matches, then press Link subtitles")
    end)
end

function O.local_link()
    local n = 0
    for _, row in ipairs(rows_for_dir()) do
        local sb = row.local_sub
        if sb and row.status ~= "saved" then
            local base = row.name:gsub("%.[%w]+$", "")
            local l = sub_lang(sb.name)
            local dest = media.unique_path(media.dirname(row.path), base .. (l and ("." .. l) or ""), media.ext(sb.path))
            if media.copy_file(sb.path, dest) then
                row.status = "saved"
                n = n + 1
                attach(row.path, dest)
            else
                row.status = "error"
            end
        end
    end
    set_status(n .. " subtitle files copied next to their videos. They load automatically from now on.")
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local function result_row(id, x, y, w, rh, it, on_click, selected)
    local s, b = ctx.s, ctx.b
    local hov = ctx.hover == id
    if selected then
        b:rect(x, y + 2 * s, w, rh - 4 * s, { color = D.T.accent_dim, r = 5 * s })
    elseif hov then
        b:rect(x, y + 2 * s, w, rh - 4 * s, { color = D.T.surface, r = 5 * s })
    end
    local cy = y + rh / 2
    local bx = x + 12 * s
    bx = bx + U.badge(bx, cy, (it.lang ~= "" and it.lang or "?"):upper(), D.T.accent) + 10 * s
    local right = x + w - 12 * s
    b:text(right, cy, tostring(it.downloads) .. " ↓", { align = 6, size = 12 * s, color = D.T.text3 })
    right = right - 70 * s
    local function flag(text, color)
        local fw = D.text_width(text, 11 * s, true) + 10 * s
        right = right - fw - 6 * s
        U.badge(right, cy, text, color)
    end
    if it.match then flag("HASH MATCH", "8be07a") end
    if it.trusted then flag("TRUSTED", "6fe3f2") end
    if it.hi then flag("HI", D.T.text2) end
    if it.ai then flag("AI", "f28cc5") end
    b:text(bx, cy, it.name, { size = 13 * s, color = hov and D.T.text or D.T.text2, clip = { bx, y, right - 8 * s, y + rh } })
    U.region(id, x, y, w, rh, { click = on_click, tooltip = it.name })
end

local function draw_key_missing(x, y, w)
    local s, b = ctx.s, ctx.b
    b:text(x, y + 20 * s, "OpenSubtitles needs a free API key.", { size = 15 * s, color = D.T.text })
    b:text(x, y + 46 * s, "1. Create an account at opensubtitles.com and open opensubtitles.com/consumers", { size = 13 * s, color = D.T.text2 })
    b:text(x, y + 68 * s, "2. Create a new consumer (any name) and copy its API key", { size = 13 * s, color = D.T.text2 })
    b:text(x, y + 90 * s, "3. Paste it here. Optional: your username and password give you more downloads per day.", { size = 13 * s, color = D.T.text2 })
    U.button("subs:setkey", x, y + 116 * s, 180 * s, 36 * s, "Paste API key…", {
        primary = true, icon = "clipboard",
        on_click = function()
            media.prompt("OpenSubtitles API key:", "", function(t)
                t = (t or ""):gsub("%s", "")
                if t ~= "" then media.set_setting("os_api_key", t); O.status = "API key saved" end
            end)
        end,
    })
    U.button("subs:login", x + 190 * s, y + 116 * s, 180 * s, 36 * s, "Account login…", {
        icon = "keyboard", on_click = function() ctx.api.open_settings("downloads") end,
    })
end

function O.draw()
    local s, b = ctx.s, ctx.b
    local close = function() ctx.modal = nil end
    local x, y, w, h = U.modal("subs", "Add subtitles", 920 * s, 660 * s, close)
    local y0 = y

    -- target + source
    U.segmented("subs:target", x, y, 250 * s, 34 * s, {
        { label = "This file", value = "file" }, { label = "This folder", value = "folder" },
    }, O.target, function(v) O.target = v; O.results = nil; O.pick_for = nil; O.status = nil end)
    U.segmented("subs:source", x + w - 340 * s, y, 340 * s, 34 * s, {
        { label = "From OpenSubtitles", value = "online" }, { label = "From this computer", value = "local" },
    }, O.source, function(v) O.source = v; O.status = nil end)
    y = y + 50 * s

    local foot_h = 52 * s
    local list_y = y + 50 * s
    local list_h = y0 + h - foot_h - list_y

    if O.source == "online" then
        if O.api_key() == "" then
            draw_key_missing(x, y, w)
        else
            -- search row
            local lang_w, btn_w = 90 * s, 110 * s
            local qw = w - lang_w - btn_w - 20 * s
            local qtext = O.pick_for and O.rows and O.rows[O.pick_for] and media.parse_name(O.rows[O.pick_for].name).show or O.query
            U.box("subs:query", x, y, qw, 36 * s, qtext, {
                placeholder = "Search for a movie or show (S01E02 works too)",
                on_click = function()
                    media.prompt("Search subtitles:", O.query, function(t)
                        if t and t ~= "" then O.query = t; O.pick_for = nil; O.target = "file"; O.run_search() end
                    end)
                end,
            })
            ctx.b:icon(x + qw - 18 * s, y + 18 * s, "search", { size = 15 * s, color = D.T.text3 })
            U.box("subs:lang", x + qw + 10 * s, y, lang_w, 36 * s, O.lang, {
                tooltip = "Language code(s), e.g. en or en,pt-br",
                on_click = function()
                    media.prompt("Subtitle languages (comma separated, e.g. en,es):", O.lang, function(t)
                        if t and t ~= "" then O.lang = t:gsub("%s", ""):lower() end
                    end)
                end,
            })
            if O.target == "file" or O.pick_for then
                U.button("subs:go", x + w - btn_w, y, btn_w, 36 * s, O.busy and "Searching…" or "Search", {
                    primary = true, icon = "search", on_click = function() if not O.busy then O.run_search() end end,
                })
            else
                U.button("subs:findall", x + w - btn_w, y, btn_w, 36 * s, "Find all", {
                    primary = true, icon = "search", on_click = function() if not O.busy then O.find_all() end end,
                    tooltip = "Find the best subtitle for every video in this folder",
                })
            end
        end
    else
        local label = O.target == "file" and "Choose subtitle files…" or "Choose subtitle files for this folder…"
        U.button("subs:pick", x, y, 280 * s, 36 * s, label, { primary = true, icon = "file-plus", on_click = O.local_pick })
        if O.target == "file" then
            local on = O.save_copy ~= false
            U.toggle("subs:savecopy", x + w, y + 18 * s, on, function() O.save_copy = not on end)
            b:text(x + w - 74 * s, y + 18 * s, "Save next to the video so it loads automatically", { align = 6, size = 13 * s, color = D.T.text2 })
        else
            b:text(x + 296 * s, y + 18 * s, "Pick all the files. They are matched to episodes by S01E02 / 1x02 / episode number.",
                { size = 13 * s, color = D.T.text2, clip = { x, y, x + w, y + 36 * s } })
        end
    end

    -- list
    local rh = 40 * s
    if not (O.source == "online" and O.api_key() == "") then
        b:rect(x, list_y - 6 * s, w, 1 * s, { color = "202020" })
        local top = U.scroll_begin("subs:list", x, list_y, w, list_h)
        local cy = top
        if O.target == "file" or (O.pick_for and O.source == "online") then
            if O.pick_for then
                local row = O.rows[O.pick_for]
                U.button("subs:back", x, cy + 4 * s, 120 * s, 30 * s, "Back to folder", { icon = "arrow-left", size = 13, on_click = function() O.pick_for = nil; O.results = nil end })
                b:text(x + 134 * s, cy + 19 * s, "Choose a subtitle for " .. row.name, { size = 13 * s, color = D.T.text2, clip = { x, cy, x + w, cy + 40 * s } })
                cy = cy + 44 * s
            end
            if O.source == "online" then
                for i, it in ipairs(O.results or {}) do
                    result_row("subs:r:" .. i, x, cy, w, rh, it, function()
                        if O.busy then return end
                        if O.pick_for then
                            local row = O.rows[O.pick_for]
                            row.result, row.status = it, "found"
                            O.pick_for, O.results = nil, nil
                        else
                            O.download_one(it)
                        end
                    end, O.pick_for and O.rows[O.pick_for].result == it)
                    cy = cy + rh
                end
                if not O.results and not O.busy then
                    b:text(x + w / 2, cy + 50 * s, "Press Search. Results matching your file's hash are marked HASH MATCH.", { align = 5, size = 13 * s, color = D.T.text3 })
                end
            end
        else
            local rows = rows_for_dir()
            if #rows == 0 then b:text(x + w / 2, cy + 40 * s, "No videos in this folder", { align = 5, size = 13 * s, color = D.T.text3 }) end
            local colw = w * 0.42
            for i, row in ipairs(rows) do
                local id = "subs:row:" .. i
                local hov = ctx.hover == id
                if hov then b:rect(x, cy + 2 * s, w, rh - 4 * s, { color = D.T.surface, r = 5 * s }) end
                b:icon(x + 16 * s, cy + rh / 2, "film", { size = 15 * s, color = D.T.text2 })
                b:text(x + 36 * s, cy + rh / 2, row.name, { size = 13 * s, color = D.T.text, clip = { x, cy, x + colw - 10 * s, cy + rh } })
                b:icon(x + colw + 6 * s, cy + rh / 2, "arrow-right", { size = 13 * s, color = D.T.text3 })
                local sub = O.source == "online" and row.result and row.result.name or (O.source == "local" and row.local_sub and row.local_sub.name)
                local stat = ({ searching = "Searching…", none = "Not found", downloading = "Downloading…", saved = "Saved", error = "Failed", matched = "" })[row.status] or ""
                local scol = row.status == "saved" and "8be07a" or ((row.status == "none" or row.status == "error") and "e8504a" or D.T.text3)
                local right = x + w - 12 * s
                if stat ~= "" then
                    b:text(right, cy + rh / 2, stat, { align = 6, size = 12 * s, color = scol })
                    right = right - D.text_width(stat, 12 * s) - 12 * s
                end
                b:text(x + colw + 26 * s, cy + rh / 2, sub or "—", { size = 13 * s, color = sub and D.T.text2 or D.T.text3, clip = { x + colw, cy, right, cy + rh } })
                U.region(id, x, cy, w, rh, {
                    click = function()
                        if O.source == "online" and row.results then
                            O.pick_for, O.results = i, row.results
                        elseif O.source == "online" then
                            O.pick_for = i; O.run_search()
                        end
                    end,
                    tooltip = O.source == "online" and "Click to choose a different subtitle" or nil,
                })
                cy = cy + rh
            end
        end
        U.scroll_end("subs:list", x, list_y, w, list_h, cy - top + 10 * s)
    end

    -- footer
    local fy = y0 + h - foot_h + 10 * s
    b:text(x, fy + 18 * s, O.status or (O.source == "online" and "Subtitles are saved next to the video as <video name>.<language>.srt" or ""),
        { size = 13 * s, color = D.T.text2, clip = { x, fy, x + w - 230 * s, fy + 40 * s } })
    if O.target == "folder" and not O.pick_for then
        if O.source == "online" and O.api_key() ~= "" then
            U.button("subs:dlall", x + w - 200 * s, fy, 200 * s, 36 * s, "Download all", {
                primary = true, icon = "file-plus", on_click = function() if not O.busy then O.download_all() end end,
            })
        elseif O.source == "local" then
            U.button("subs:link", x + w - 200 * s, fy, 200 * s, 36 * s, "Link subtitles", {
                primary = true, icon = "link", on_click = O.local_link,
                tooltip = "Copies each subtitle next to its video with the same name",
            })
        end
    end
end

return O
