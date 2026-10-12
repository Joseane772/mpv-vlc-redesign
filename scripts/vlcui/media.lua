-- Player logic: tracks, filters, presets, bookmarks, history, dialogs, subtitle timeline, waveform.
local mp = require 'mp'
local utils = require 'mp.utils'
local ctx = require 'ctx'

local M = {}

local ok_input, input = pcall(require, 'mp.input')
if not ok_input then input = nil end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
M.video_ext = {}
for e in ("mkv mp4 avi mov webm wmv flv m4v mpg mpeg ts m2ts mts 3gp ogv vob rm rmvb divx hevc y4m"):gmatch("%S+") do M.video_ext[e] = true end
M.audio_ext = {}
for e in ("mp3 flac wav ogg oga opus m4a aac wma alac ape aiff aif mka wv dsf"):gmatch("%S+") do M.audio_ext[e] = true end
M.sub_ext = {}
for e in ("srt ass ssa vtt sub idx sup smi"):gmatch("%S+") do M.sub_ext[e] = true end

function M.ext(path) return (path:match("%.([^%./\\]+)$") or ""):lower() end
function M.is_media(path) local e = M.ext(path); return M.video_ext[e] or M.audio_ext[e] or false end
function M.is_url(path) return path and path:match("^%a[%w+.-]*://") ~= nil end
function M.basename(path)
    if not path then return "" end
    if M.is_url(path) then return path end
    local _, f = utils.split_path(path)
    return f
end
function M.dirname(path)
    if not path or M.is_url(path) then return nil end
    local d = utils.split_path(path)
    d = d:gsub("[/\\]$", "")
    if d == "" then d = "/" end
    return d
end
function M.abspath(path)
    if not path or M.is_url(path) then return path end
    if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then return path end
    return utils.join_path(mp.get_property("working-directory", ""), path)
end

function M.fmt_time(t, hours)
    if not t or t ~= t then return "--:--" end
    local neg = t < 0
    t = math.floor(math.abs(t))
    local h, m, s = math.floor(t / 3600), math.floor(t / 60) % 60, t % 60
    local str
    if h > 0 or hours then str = string.format("%02d:%02d:%02d", h, m, s) else str = string.format("%02d:%02d", m, s) end
    return (neg and "-" or "") .. str
end

-- Natural sort ("Episode 2" < "Episode 10")
function M.natural_lt(a, b)
    local function pad(s) return (s:lower():gsub("%d+", function(d) return string.format("%012d", tonumber(d) or 0) end)) end
    return pad(a) < pad(b)
end

function M.file_exists(path)
    local info = path and utils.file_info(path)
    return info ~= nil
end

-- "The.Wand.S01E04.1080p.WEB.mkv" -> { show = "The Wand", season = 1, episode = 4, year = nil, base = ... }
local junk = { "%d%d%d%d?p", "%d[kK]", "x26[45]", "[hH]%.?26[45]", "hevc", "avc", "web%-?dl", "web%-?rip", "webrip", "web",
    "bluray", "blu%-ray", "bdrip", "brrip", "dvdrip", "hdtv", "hdr", "10bit", "aac", "ac3", "dts", "ddp?5%.?1", "proper", "repack" }
function M.parse_name(name)
    local base = (name or ""):gsub("%.[%w]+$", "")
    local clean = base:gsub("[%._]", " "):gsub("%s+", " ")
    local r = { base = base }
    local s, e = clean:match("[Ss](%d%d?)%s?[Ee](%d%d?%d?)")
    local cut = clean:find("[Ss]%d%d?%s?[Ee]%d")
    if not s then
        s, e = clean:match("(%d%d?)[xX](%d%d%d?)")
        cut = s and clean:find("%d%d?[xX]%d%d")
    end
    if not e then
        e = clean:match("[Ee][Pp]?%s?(%d%d?%d?)%f[^%d]") or clean:match("%s%-%s(%d%d?%d?)%f[^%d]")
        cut = e and (clean:find("[Ee][Pp]?%s?%d") or clean:find("%s%-%s%d"))
    end
    r.season, r.episode = tonumber(s), tonumber(e)
    local show = cut and clean:sub(1, cut - 1) or clean
    local year = show:match("[%(%[]?((19%d%d))[%)%]]?") or show:match("%f[%d](20%d%d)%f[^%d]")
    r.year = tonumber(year)
    show = show:gsub("%b[]", ""):gsub("%b()", "")
    local low = show:lower()
    local stop = #show + 1
    for _, pat in ipairs(junk) do
        local i = low:find("%f[%w]" .. pat .. "%f[^%w]")
        if i and i < stop then stop = i end
    end
    if r.year then
        local i = show:find(tostring(r.year), 1, true)
        if i and i > 1 and i < stop then stop = i end
    end
    show = show:sub(1, stop - 1):gsub("[%s%-]+$", ""):gsub("^%s+", "")
    r.show = show ~= "" and show or clean
    return r
end

function M.copy_file(src, dst)
    local i = io.open(src, "rb")
    if not i then return false end
    local data = i:read("*a")
    i:close()
    local o = io.open(dst, "wb")
    if not o then return false end
    o:write(data)
    o:close()
    return true
end

-- A path that does not exist yet: base.ext, base.2.ext, base.3.ext …
function M.unique_path(dir, base, ext)
    local p = utils.join_path(dir, base .. "." .. ext)
    local n = 2
    while M.file_exists(p) do
        p = utils.join_path(dir, base .. "." .. n .. "." .. ext)
        n = n + 1
    end
    return p
end

local function find_exe(name)
    local path = os.getenv("PATH") or ""
    for dir in path:gmatch("[^:]+") do
        local info = utils.file_info(dir .. "/" .. name)
        if info and info.is_file then return dir .. "/" .. name end
    end
    return nil
end
M.find_exe = find_exe

---------------------------------------------------------------------------
-- Persistent store (~~state/vlcui.json)
---------------------------------------------------------------------------
local state_dir = mp.command_native({ "expand-path", "~~state/" })
local store_path = utils.join_path(state_dir, "vlcui.json")
M.playlists_dir = utils.join_path(state_dir, "vlcui-playlists")

local function mkdir(dir)
    if utils.file_info(dir) then return end
    if package.config:sub(1, 1) == "\\" then
        mp.command_native({ name = "subprocess", args = { "cmd", "/c", "mkdir", dir }, playback_only = false })
    else
        mp.command_native({ name = "subprocess", args = { "mkdir", "-p", dir }, playback_only = false })
    end
end
M.mkdir = mkdir

M.store = { settings = {}, presets = {}, folder_presets = {}, bookmarks = {}, history = {} }

function M.load_store()
    local f = io.open(store_path, "r")
    if f then
        local data = utils.parse_json(f:read("*a") or "")
        f:close()
        if type(data) == "table" then
            for k, v in pairs(data) do
                if type(v) == "table" then M.store[k] = v end
            end
        end
    end
    -- copy into plain tables: parse_json marks empty sections as arrays, which would drop string keys on save
    local function plain(t)
        local out = {}
        if type(t) == "table" then for k, v in pairs(t) do out[k] = v end end
        return out
    end
    for _, k in ipairs({ "settings", "presets", "folder_presets", "bookmarks" }) do
        M.store[k] = plain(M.store[k])
    end
    M.store.history = plain(M.store.history)
end

local save_timer
function M.save_store(now)
    local function write()
        mkdir(state_dir)
        local json = utils.format_json(M.store)
        if not json then return end
        local f = io.open(store_path, "w")
        if f then f:write(json); f:close() end
    end
    if now then
        if save_timer then save_timer:kill() end
        write()
        return
    end
    if save_timer then save_timer:kill() end
    save_timer = mp.add_timeout(1.0, write)
end

function M.setting(name, default)
    local v = M.store.settings[name]
    if v == nil then return default end
    return v
end

function M.set_setting(name, value)
    M.store.settings[name] = value
    M.save_store()
    ctx.request_render()
end

---------------------------------------------------------------------------
-- Text input + toasts + clipboard + file dialogs
---------------------------------------------------------------------------
function M.prompt(prompt, default, cb)
    if not input then
        mp.osd_message("mp.input requires mpv 0.39+")
        return
    end
    input.get({
        prompt = prompt .. " ",
        default_text = default or "",
        submit = function(text)
            input.terminate()
            cb(text)
        end,
    })
end

function M.clipboard()
    local v = mp.get_property("clipboard/text")
    if v and v ~= "" then return v end
    for _, cmd in ipairs({ { "wl-paste", "--no-newline" }, { "xclip", "-o", "-selection", "clipboard" }, { "xsel", "-ob" } }) do
        if find_exe(cmd[1]) then
            local r = mp.command_native({ name = "subprocess", args = cmd, capture_stdout = true, playback_only = false })
            if r and r.status == 0 and r.stdout ~= "" then return r.stdout end
        end
    end
    return ""
end

-- kind: "media" | "folder" | "subtitle"
function M.pick(kind, cb)
    local start = M.dirname(M.abspath(mp.get_property("path"))) or os.getenv("HOME") or ""
    local args
    if find_exe("zenity") then
        args = { "zenity", "--file-selection", "--filename=" .. start .. "/" }
        if kind == "folder" then
            args[#args + 1] = "--directory"; args[#args + 1] = "--title=Open folder"
        else
            args[#args + 1] = "--multiple"; args[#args + 1] = "--separator=\n"
            if kind == "subtitle" then
                args[#args + 1] = "--title=Add subtitles"
                args[#args + 1] = "--file-filter=Subtitles | *.srt *.ass *.ssa *.vtt *.sub *.sup *.idx *.smi"
            else
                args[#args + 1] = "--title=Open media"
            end
            args[#args + 1] = "--file-filter=All files | *"
        end
    elseif find_exe("kdialog") then
        if kind == "folder" then
            args = { "kdialog", "--getexistingdirectory", start }
        else
            args = { "kdialog", "--getopenfilename", start, kind == "subtitle" and "*.srt *.ass *.ssa *.vtt *.sub *.sup|Subtitles" or "", "--multiple", "--separate-output" }
        end
    elseif find_exe("osascript") then -- macOS
        if kind == "folder" then
            args = { "osascript", "-e", 'POSIX path of (choose folder with prompt "Open folder")' }
        else
            args = { "osascript",
                "-e", 'set fs to choose file with prompt "' .. (kind == "subtitle" and "Add subtitles" or "Open media") .. '" with multiple selections allowed',
                "-e", 'set out to ""',
                "-e", 'repeat with f in fs',
                "-e", 'set out to out & POSIX path of f & linefeed',
                "-e", 'end repeat',
                "-e", 'return out' }
        end
    elseif package.config:sub(1, 1) == "\\" then
        local ps
        if kind == "folder" then
            ps = "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.FolderBrowserDialog; if($d.ShowDialog() -eq 'OK'){$d.SelectedPath}"
        else
            ps = "Add-Type -AssemblyName System.Windows.Forms; $d=New-Object System.Windows.Forms.OpenFileDialog; $d.Multiselect=$true; if($d.ShowDialog() -eq 'OK'){$d.FileNames -join \"`n\"}"
        end
        args = { "powershell", "-NoProfile", "-Command", ps }
    end
    if not args then
        M.prompt(kind == "folder" and "Folder path:" or "File path:", start .. "/", function(text)
            if text and text ~= "" then cb({ text }) end
        end)
        return
    end
    mp.command_native_async({ name = "subprocess", args = args, capture_stdout = true, playback_only = false }, function(ok, res)
        if not ok or not res or res.status ~= 0 then return end
        local list = {}
        for line in (res.stdout or ""):gmatch("[^\r\n]+") do list[#list + 1] = line end
        if #list > 0 then cb(list) end
    end)
end

function M.open_paths(paths, mode)
    mode = mode or "replace"
    for i, p in ipairs(paths) do
        local m = (i == 1 and mode == "replace") and "replace" or "append-play"
        mp.commandv("loadfile", p, m)
    end
end

function M.open_dialog(mode)
    M.pick("media", function(list) M.open_paths(list, mode) end)
end

function M.open_folder_dialog(mode)
    M.pick("folder", function(list)
        local files = M.list_dir(list[1]).files
        local paths = {}
        for _, f in ipairs(files) do paths[#paths + 1] = f.path end
        if #paths > 0 then M.open_paths(paths, mode) else ctx.toast(nil, "No media files in that folder") end
    end)
end

function M.add_subtitle_dialog()
    M.pick("subtitle", function(list)
        for _, p in ipairs(list) do mp.commandv("sub-add", p, "select") end
        ctx.toast(nil, #list > 1 and (#list .. " subtitle tracks added") or "Subtitle track added")
    end)
end

function M.open_url()
    local clip = M.clipboard():gsub("^%s+", ""):gsub("%s+$", "")
    if not M.is_url(clip) then clip = "" end
    M.prompt("Open network stream (URL):", clip, function(text)
        text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" then mp.commandv("loadfile", text, "replace") end
    end)
end

function M.paste_and_play()
    local clip = M.clipboard():gsub("^%s+", ""):gsub("%s+$", "")
    if clip == "" then
        ctx.toast(nil, "Clipboard is empty")
        return
    end
    mp.commandv("loadfile", clip, "replace")
    ctx.toast(nil, "Playing from clipboard")
end

---------------------------------------------------------------------------
-- Directory listing
---------------------------------------------------------------------------
function M.list_dir(dir)
    local res = { dirs = {}, files = {} }
    if not dir then return res end
    local dirs = utils.readdir(dir, "dirs") or {}
    local files = utils.readdir(dir, "files") or {}
    table.sort(dirs, M.natural_lt)
    table.sort(files, M.natural_lt)
    for _, d in ipairs(dirs) do
        if d:sub(1, 1) ~= "." then res.dirs[#res.dirs + 1] = { name = d, path = utils.join_path(dir, d) } end
    end
    for _, f in ipairs(files) do
        if M.is_media(f) and f:sub(1, 1) ~= "." then
            res.files[#res.files + 1] = { name = f, path = utils.join_path(dir, f), audio = M.audio_ext[M.ext(f)] or false }
        end
    end
    return res
end

-- Play a folder starting at `path` (the "click an episode and keep watching" flow).
function M.play_folder_from(dir, path)
    local files = M.list_dir(dir).files
    local start = 0
    mp.commandv("playlist-clear")
    for i, f in ipairs(files) do
        if f.path == path then start = i - 1 end
    end
    mp.commandv("loadfile", files[1] and files[1].path or path, "replace")
    for i = 2, #files do mp.commandv("loadfile", files[i].path, "append") end
    if start > 0 then mp.set_property_number("playlist-pos", start) end
end

-- Autoload sibling files into the queue when a single local file is opened.
function M.autoload()
    if not M.setting("autoload", true) then return end
    if mp.get_property_number("playlist-count", 1) ~= 1 then return end
    local path = M.abspath(mp.get_property("path"))
    if not path or M.is_url(path) then return end
    local dir = M.dirname(path)
    local cur_audio = M.audio_ext[M.ext(path)] or false
    local files = M.list_dir(dir).files
    local before, found = 0, false
    for _, f in ipairs(files) do
        if f.audio == cur_audio then
            if f.path == path then
                found = true
            else
                mp.commandv("loadfile", f.path, "append")
                if not found then
                    local count = mp.get_property_number("playlist-count", 1)
                    mp.commandv("playlist-move", count - 1, before)
                    before = before + 1
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Tracks
---------------------------------------------------------------------------
function M.tracks(kind)
    local out = {}
    for _, t in ipairs(ctx.p["track-list"] or {}) do
        if t.type == kind then out[#out + 1] = t end
    end
    return out
end

local lang_names = {
    en = "English", eng = "English", ja = "Japanese", jpn = "Japanese", es = "Spanish", spa = "Spanish",
    fr = "French", fre = "French", fra = "French", de = "German", ger = "German", deu = "German",
    it = "Italian", ita = "Italian", pt = "Portuguese", por = "Portuguese", ru = "Russian", rus = "Russian",
    zh = "Chinese", chi = "Chinese", zho = "Chinese", ko = "Korean", kor = "Korean", ar = "Arabic", ara = "Arabic",
    nl = "Dutch", dut = "Dutch", nld = "Dutch", pl = "Polish", pol = "Polish", tr = "Turkish", tur = "Turkish",
    sv = "Swedish", swe = "Swedish", hi = "Hindi", hin = "Hindi", und = nil,
}

function M.track_label(t)
    local parts = {}
    if t.external and t["external-filename"] and not M.is_url(t["external-filename"]) then
        -- mpv titles external files with just their suffix ("en.srt"); the file name is clearer
        parts[#parts + 1] = M.basename(t["external-filename"])
    elseif t.title and t.title ~= "" then
        parts[#parts + 1] = t.title
    end
    if t.lang and lang_names[t.lang] and not (t.title and t.title:lower():find(lang_names[t.lang]:lower(), 1, true)) then
        parts[#parts + 1] = lang_names[t.lang]
    elseif t.lang and t.lang ~= "und" and #parts == 0 then
        parts[#parts + 1] = t.lang
    end
    if #parts == 0 then
        if t.external and t["external-filename"] then
            parts[#parts + 1] = M.basename(t["external-filename"])
        else
            parts[#parts + 1] = "Track " .. t.id
        end
    end
    local label = table.concat(parts, " - ")
    if t.type == "audio" and t["demux-channel-count"] then
        label = label .. "  ·  " .. t["demux-channel-count"] .. "ch"
    end
    return label
end

-- Output devices for the active audio driver only (the full list includes every ALSA plugin).
function M.audio_devices()
    local all = ctx.p["audio-device-list"] or {}
    local ao = mp.get_property("current-ao")
    local out, seen = {}, {}
    for _, d in ipairs(all) do
        local keep = d.name == "auto" or not ao or d.name:sub(1, #ao + 1) == ao .. "/"
        local label = d.name == "auto" and "System default" or (d.description or d.name)
        if keep and not seen[label] then
            seen[label] = true
            out[#out + 1] = { name = d.name, label = label }
        end
    end
    if #out <= 1 then
        out, seen = {}, {}
        for _, d in ipairs(all) do
            local label = d.name == "auto" and "System default" or (d.description or d.name)
            if not seen[label] then seen[label] = true; out[#out + 1] = { name = d.name, label = label } end
        end
    end
    return out
end

function M.select_track(kind, id)
    local prop = ({ audio = "aid", sub = "sid", video = "vid" })[kind]
    mp.set_property(prop, id and tostring(id) or "no")
end

function M.current_track(kind)
    for _, t in ipairs(M.tracks(kind)) do
        if t.selected and not (kind == "sub" and t["main-selection"] == 1) then return t end
    end
    return nil
end

---------------------------------------------------------------------------
-- Audio filters
---------------------------------------------------------------------------
M.eq_freqs = { 60, 170, 310, 600, 1000, 3000, 6000, 12000, 14000, 16000 }
M.eq_labels = { "60 Hz", "170 Hz", "310 Hz", "600 Hz", "1 KHz", "3 KHz", "6 KHz", "12 KHz", "14 KHz", "16 KHz" }
M.eq_presets = {
    { "None",            { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } },
    { "Classical",       { 0, 0, 0, 0, 0, 0, -7.2, -7.2, -7.2, -9.6 } },
    { "Club",            { 0, 0, 8, 5.6, 5.6, 5.6, 3.2, 0, 0, 0 } },
    { "Dance",           { 9.6, 7.2, 2.4, 0, 0, -5.6, -7.2, -7.2, 0, 0 } },
    { "Full bass",       { -8, 9.6, 9.6, 5.6, 1.6, -4, -8, -10.4, -11.2, -11.2 } },
    { "Bass & treble",   { 7.2, 5.6, 0, -7.2, -4.8, 1.6, 8, 11.2, 12, 12 } },
    { "Full treble",     { -9.6, -9.6, -9.6, -4, 2.4, 11.2, 16, 16, 16, 16.8 } },
    { "Headphones",      { 4.8, 11.2, 5.6, -3.2, -2.4, 1.6, 4.8, 9.6, 12.8, 14.4 } },
    { "Large hall",      { 10.4, 10.4, 5.6, 5.6, 0, -4.8, -4.8, -4.8, 0, 0 } },
    { "Live",            { -4.8, 0, 4, 5.6, 5.6, 5.6, 4, 2.4, 2.4, 2.4 } },
    { "Party",           { 7.2, 7.2, 0, 0, 0, 0, 0, 0, 7.2, 7.2 } },
    { "Pop",             { -1.6, 4.8, 7.2, 8, 5.6, 0, -2.4, -2.4, -1.6, -1.6 } },
    { "Reggae",          { 0, 0, 0, -5.6, 0, 6.4, 6.4, 0, 0, 0 } },
    { "Rock",            { 8, 4.8, -5.6, -8, -3.2, 4, 8.8, 11.2, 11.2, 11.2 } },
    { "Ska",             { -2.4, -4.8, -4, 0, 4, 5.6, 8.8, 9.6, 11.2, 9.6 } },
    { "Soft",            { 4.8, 1.6, 0, -2.4, 0, 4, 8, 9.6, 11.2, 12 } },
    { "Soft rock",       { 4, 4, 2.4, 0, -4, -5.6, -3.2, 0, 2.4, 8.8 } },
    { "Techno",          { 8, 5.6, 0, -5.6, -4.8, 0, 8, 9.6, 9.6, 8.8 } },
}

M.audio = {
    eq = false, eq_preset = "None", preamp = 0, bands = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    comp = false, comp_threshold = -18, comp_ratio = 4, comp_attack = 25, comp_release = 100, comp_makeup = 4, comp_knee = 5,
    normalize = false, widen = false, mono = false,
}

local active_filters = { af = {}, vf = {} }

local function set_filter(kind, label, spec)
    local full = "@vlcui-" .. label
    if active_filters[kind][label] then
        mp.commandv(kind, "remove", full)
        active_filters[kind][label] = nil
    end
    if spec then
        if kind == "vf" then
            local hw = mp.get_property("hwdec-current", "no")
            if hw ~= "no" and hw ~= "" and not hw:match("%-copy$") then
                mp.set_property("hwdec", "auto-copy-safe")
            end
        end
        if mp.commandv(kind, "add", full .. ":" .. spec) then
            active_filters[kind][label] = spec
        else
            ctx.toast(nil, "Could not apply filter: " .. label)
        end
    end
end
M.set_filter = set_filter

function M.eq_apply()
    local a = M.audio
    if not a.eq then return set_filter("af", "eq", nil) end
    local parts = {}
    if math.abs(a.preamp) > 0.05 then parts[#parts + 1] = string.format("volume=%.1fdB", a.preamp) end
    for i, f in ipairs(M.eq_freqs) do
        local g = a.bands[i] or 0
        if math.abs(g) > 0.05 then parts[#parts + 1] = string.format("equalizer=f=%d:t=o:w=1:g=%.1f", f, g) end
    end
    if #parts == 0 then return set_filter("af", "eq", nil) end
    set_filter("af", "eq", "lavfi=[" .. table.concat(parts, ",") .. "]")
end

function M.eq_set_preset(name)
    for _, p in ipairs(M.eq_presets) do
        if p[1] == name then
            local maxg = 0
            for i = 1, 10 do
                M.audio.bands[i] = p[2][i]
                maxg = math.max(maxg, p[2][i])
            end
            M.audio.preamp = -math.floor(maxg * 0.6 * 10 + 0.5) / 10 -- headroom against clipping
            M.audio.eq_preset = name
            if name ~= "None" then M.audio.eq = true end
        end
    end
    M.eq_apply()
end

local function db2lin(db) return 10 ^ (db / 20) end

function M.comp_apply()
    local a = M.audio
    if not a.comp then return set_filter("af", "comp", nil) end
    set_filter("af", "comp", string.format("lavfi=[acompressor=threshold=%.6f:ratio=%.2f:attack=%.2f:release=%.2f:makeup=%.4f:knee=%.4f]",
        math.max(0.000976563, db2lin(a.comp_threshold)), a.comp_ratio, a.comp_attack, a.comp_release,
        math.max(1, math.min(64, db2lin(a.comp_makeup))), math.max(1, math.min(8, db2lin(a.comp_knee)))))
end

function M.simple_audio(name, on)
    M.audio[name] = on
    local specs = {
        normalize = "lavfi=[dynaudnorm=f=250:g=15:p=0.9]",
        widen = "lavfi=[extrastereo=m=2.0]",
        mono = "lavfi=[pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1]",
    }
    set_filter("af", name, on and specs[name] or nil)
end

---------------------------------------------------------------------------
-- Video filters
---------------------------------------------------------------------------
M.video = { flip = "none", negate = false, gray = false, sepia = false, sharpen = false, denoise = false }

function M.set_flip(v)
    M.video.flip = v
    set_filter("vf", "flip", (v == "h" and "lavfi=[hflip]") or (v == "v" and "lavfi=[vflip]") or nil)
end

local vfx = {
    negate = "lavfi=[negate]",
    gray = "lavfi=[hue=s=0]",
    sepia = "lavfi=[colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131]",
    sharpen = "lavfi=[unsharp=5:5:0.9:3:3:0.4]",
    denoise = "lavfi=[hqdn3d=4:3:6:4.5]",
}
function M.video_fx(name, on)
    M.video[name] = on
    set_filter("vf", name, on and vfx[name] or nil)
end

---------------------------------------------------------------------------
-- Presets (subtitle + audio sync settings saved per show / folder)
---------------------------------------------------------------------------
M.preset_props = {
    "sub-delay", "sub-speed", "sub-scale", "sub-font-size", "sub-font", "sub-color", "sub-outline-color",
    "sub-outline-size", "sub-pos", "sub-back-color", "sub-border-style", "sub-bold", "sub-ass-override", "audio-delay",
}

function M.capture_preset()
    local p = { props = {} }
    for _, name in ipairs(M.preset_props) do p.props[name] = mp.get_property(name) end
    local function pick(kind)
        local cur = M.current_track(kind)
        if not cur then return nil end
        local idx = 0
        for i, t in ipairs(M.tracks(kind)) do if t.id == cur.id then idx = i end end
        return { lang = cur.lang, title = cur.title, index = idx }
    end
    p.sub = pick("sub")
    p.audio = pick("audio")
    p.eq = { enabled = M.audio.eq, preset = M.audio.eq_preset, preamp = M.audio.preamp, bands = M.audio.bands }
    return p
end

function M.apply_preset(name, quiet)
    local p = M.store.presets[name]
    if not p then return end
    for k, v in pairs(p.props or {}) do mp.set_property(k, v) end
    local function choose(kind, pref)
        if not pref then return end
        local list = M.tracks(kind)
        for _, t in ipairs(list) do
            if pref.lang and t.lang == pref.lang and (not pref.title or t.title == pref.title) then return M.select_track(kind, t.id) end
        end
        for _, t in ipairs(list) do
            if pref.lang and t.lang == pref.lang then return M.select_track(kind, t.id) end
        end
        if pref.index and list[pref.index] then M.select_track(kind, list[pref.index].id) end
    end
    choose("sub", p.sub)
    choose("audio", p.audio)
    if p.eq then
        M.audio.eq = p.eq.enabled
        M.audio.eq_preset = p.eq.preset or "None"
        M.audio.preamp = p.eq.preamp or 0
        for i = 1, 10 do M.audio.bands[i] = (p.eq.bands or {})[i] or 0 end
        M.eq_apply()
    end
    ctx.active_preset = name
    if not quiet then ctx.toast(nil, "Preset applied: " .. name) end
end

function M.save_preset(name, link_folder)
    M.store.presets[name] = M.capture_preset()
    if link_folder then
        local dir = M.dirname(M.abspath(mp.get_property("path")))
        if dir then M.store.folder_presets[dir] = name end
    end
    ctx.active_preset = name
    M.save_store()
    ctx.toast(nil, "Preset saved: " .. name)
end

function M.delete_preset(name)
    M.store.presets[name] = nil
    for dir, n in pairs(M.store.folder_presets) do
        if n == name then M.store.folder_presets[dir] = nil end
    end
    if ctx.active_preset == name then ctx.active_preset = nil end
    M.save_store()
end

function M.preset_names()
    local list = {}
    for k in pairs(M.store.presets) do list[#list + 1] = k end
    table.sort(list, M.natural_lt)
    return list
end

function M.folder_preset()
    local dir = M.dirname(M.abspath(mp.get_property("path")))
    return dir and M.store.folder_presets[dir]
end

---------------------------------------------------------------------------
-- Bookmarks
---------------------------------------------------------------------------
local function key_path() return M.abspath(mp.get_property("path")) end

function M.bookmarks()
    local k = key_path()
    return k and M.store.bookmarks[k] or {}
end

function M.add_bookmark()
    local k = key_path()
    local t = mp.get_property_number("time-pos")
    if not k or not t then return end
    local list = M.store.bookmarks[k] or {}
    list[#list + 1] = { time = t, name = "Bookmark " .. (#list + 1) }
    table.sort(list, function(a, b) return a.time < b.time end)
    M.store.bookmarks[k] = list
    M.save_store()
    return t
end

function M.remove_bookmark(i)
    local k = key_path()
    local list = k and M.store.bookmarks[k]
    if not list then return end
    table.remove(list, i)
    if #list == 0 then M.store.bookmarks[k] = nil end
    M.save_store()
end

function M.rename_bookmark(i)
    local list = M.bookmarks()
    local bm = list[i]
    if not bm then return end
    M.prompt("Bookmark name:", bm.name, function(text)
        if text and text ~= "" then bm.name = text; M.save_store(); ctx.request_render() end
    end)
end

---------------------------------------------------------------------------
-- History (recent files + watch progress)
---------------------------------------------------------------------------
function M.history_entry(path)
    for _, e in ipairs(M.store.history) do
        if e.path == path then return e end
    end
    return nil
end

function M.update_history()
    local path = key_path()
    if not path then return end
    local pos = mp.get_property_number("time-pos")
    local dur = mp.get_property_number("duration")
    local e = M.history_entry(path)
    if not e then
        e = { path = path }
        table.insert(M.store.history, 1, e)
    else
        for i, x in ipairs(M.store.history) do
            if x == e then table.remove(M.store.history, i); break end
        end
        table.insert(M.store.history, 1, e)
    end
    e.title = mp.get_property("media-title") or M.basename(path)
    e.pos = pos or e.pos or 0
    e.dur = dur or e.dur or 0
    e.t = os.time()
    while #M.store.history > 60 do table.remove(M.store.history) end
    M.save_store()
end

function M.clear_history()
    M.store.history = {}
    M.save_store()
end

---------------------------------------------------------------------------
-- Saved playlists (m3u files)
---------------------------------------------------------------------------
function M.list_playlists()
    local files = utils.readdir(M.playlists_dir, "files") or {}
    local out = {}
    for _, f in ipairs(files) do
        if f:match("%.m3u8?$") then out[#out + 1] = { name = f:gsub("%.m3u8?$", ""), path = utils.join_path(M.playlists_dir, f) } end
    end
    table.sort(out, function(a, b) return M.natural_lt(a.name, b.name) end)
    return out
end

function M.save_queue_as_playlist()
    M.prompt("Playlist name:", "", function(name)
        name = (name or ""):gsub("[/\\:]", "-")
        if name == "" then return end
        mkdir(M.playlists_dir)
        local f = io.open(utils.join_path(M.playlists_dir, name .. ".m3u"), "w")
        if not f then return ctx.toast(nil, "Could not write playlist") end
        f:write("#EXTM3U\n")
        for _, it in ipairs(ctx.p.playlist or {}) do
            f:write(M.abspath(it.filename) .. "\n")
        end
        f:close()
        ctx.toast(nil, "Playlist saved: " .. name)
    end)
end

---------------------------------------------------------------------------
-- Sleep timer
---------------------------------------------------------------------------
M.sleep = { mode = "off", ends = nil, timer = nil }

function M.set_sleep(mode)
    if M.sleep.timer then M.sleep.timer:kill(); M.sleep.timer = nil end
    M.sleep.mode, M.sleep.ends = mode, nil
    local mins = tonumber(mode)
    if mins then
        M.sleep.ends = mp.get_time() + mins * 60
        M.sleep.timer = mp.add_timeout(mins * 60, function()
            mp.set_property_bool("pause", true)
            M.sleep.mode, M.sleep.ends, M.sleep.timer = "off", nil, nil
            ctx.toast(nil, "Sleep timer: playback paused")
        end)
        ctx.toast(nil, "Sleep timer: " .. mins .. " min")
    elseif mode == "eof" then
        ctx.toast(nil, "Sleep timer: end of current file")
    else
        ctx.toast(nil, "Sleep timer off")
    end
end

---------------------------------------------------------------------------
-- Subtitle timeline (cue ranges drawn on the seekbar)
---------------------------------------------------------------------------
local cue_cache = {}

local function parse_cues(data)
    local cues = {}
    local function ms(frac) return tonumber("0." .. frac) or 0 end
    for h1, m1, s1, f1, h2, m2, s2, f2 in data:gmatch("(%d+):(%d%d):(%d%d)[,%.](%d+)%s*%-%->%s*(%d+):(%d%d):(%d%d)[,%.](%d+)") do
        cues[#cues + 1] = { h1 * 3600 + m1 * 60 + s1 + ms(f1), h2 * 3600 + m2 * 60 + s2 + ms(f2) }
    end
    if #cues == 0 then -- WebVTT without hours
        for m1, s1, f1, m2, s2, f2 in data:gmatch("\n(%d%d):(%d%d)%.(%d+)%s*%-%->%s*(%d%d):(%d%d)%.(%d+)") do
            cues[#cues + 1] = { m1 * 60 + s1 + ms(f1), m2 * 60 + s2 + ms(f2) }
        end
    end
    if #cues == 0 then -- ASS/SSA
        for h1, m1, s1, f1, h2, m2, s2, f2 in data:gmatch("Dialogue:%s*[^,]*,(%d+):(%d+):(%d+)%.(%d+),(%d+):(%d+):(%d+)%.(%d+)") do
            cues[#cues + 1] = { h1 * 3600 + m1 * 60 + s1 + ms(f1), h2 * 3600 + m2 * 60 + s2 + ms(f2) }
        end
    end
    table.sort(cues, function(a, b) return a[1] < b[1] end)
    return cues
end

local text_codecs = { subrip = true, ass = true, ssa = true, mov_text = true, webvtt = true, text = true }

-- Returns the cue list for the selected subtitle track (async for embedded tracks), or nil.
function M.sub_cues()
    local t = M.current_track("sub")
    if not t then return nil end
    local path = M.abspath(mp.get_property("path"))
    local key = (path or "") .. "|" .. t.id
    local c = cue_cache[key]
    if c then return c ~= "pending" and c or nil end
    if t.external and t["external-filename"] then
        local f = io.open(t["external-filename"], "r")
        if f then
            cue_cache[key] = parse_cues(f:read("*a") or "")
            f:close()
        else
            cue_cache[key] = {}
        end
        return cue_cache[key]
    end
    if not path or M.is_url(path) or not text_codecs[t.codec or ""] or not t["ff-index"] or not find_exe("ffmpeg") then
        cue_cache[key] = {}
        return nil
    end
    cue_cache[key] = "pending"
    mp.command_native_async({
        name = "subprocess", playback_only = false, capture_stdout = true,
        args = { "ffmpeg", "-v", "error", "-nostdin", "-i", path, "-map", "0:" .. t["ff-index"], "-f", "srt", "-" },
    }, function(ok, res)
        cue_cache[key] = (ok and res and res.stdout) and parse_cues(res.stdout) or {}
        ctx.request_render()
    end)
    return nil
end

---------------------------------------------------------------------------
-- Audio waveform for the seekbar (computed once per file with ffmpeg)
---------------------------------------------------------------------------
local wave_cache = {}
M.wave_bins = 600

function M.waveform()
    local path = M.abspath(mp.get_property("path"))
    local dur = mp.get_property_number("duration")
    if not path or M.is_url(path) or not dur or dur <= 0 then return nil end
    local w = wave_cache[path]
    if w then return w ~= "pending" and w or nil end
    if not find_exe("ffmpeg") or #M.tracks("audio") == 0 then wave_cache[path] = {}; return nil end
    wave_cache[path] = "pending"
    local rate = 8000
    local n = math.max(1, math.floor(dur * rate / M.wave_bins))
    mp.command_native_async({
        name = "subprocess", playback_only = false, capture_stdout = true,
        args = { "ffmpeg", "-v", "error", "-nostdin", "-i", path, "-map", "0:a:0", "-ac", "1", "-ar", tostring(rate),
            "-af", "asetnsamples=n=" .. n .. ",astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-",
            "-f", "null", "-" },
    }, function(ok, res)
        local peaks = {}
        if ok and res and res.stdout then
            for db in res.stdout:gmatch("RMS_level=([%-%d%.inf]+)") do
                local v = tonumber(db) or -90
                peaks[#peaks + 1] = math.max(0, math.min(1, (v + 50) / 45))
            end
        end
        wave_cache[path] = peaks
        ctx.request_render()
    end)
    return nil
end

---------------------------------------------------------------------------
-- Misc actions
---------------------------------------------------------------------------
M.mini = nil
function M.toggle_mini()
    if M.mini then
        mp.set_property_bool("ontop", M.mini.ontop)
        if M.mini.scale then mp.set_property_number("current-window-scale", M.mini.scale) end
        M.mini = nil
        ctx.toast(nil, "Mini player off")
    else
        if mp.get_property_bool("fullscreen") then mp.set_property_bool("fullscreen", false) end
        M.mini = { ontop = mp.get_property_bool("ontop"), scale = mp.get_property_number("current-window-scale") }
        local vw = mp.get_property_number("width") or 1280
        mp.set_property_bool("ontop", true)
        mp.set_property_number("current-window-scale", math.max(0.15, 480 / vw))
        ctx.toast(nil, "Mini player (always on top)")
    end
end

function M.toggle_record()
    local cur = mp.get_property("stream-record", "")
    if cur ~= "" then
        mp.set_property("stream-record", "")
        ctx.toast("Shift+R", "Recording saved: " .. M.basename(cur))
        return
    end
    local dir = mp.command_native({ "expand-path", "~~desktop/" }) or os.getenv("HOME")
    local name = (mp.get_property("filename/no-ext") or "stream"):gsub("[/\\:]", "-")
    local file = utils.join_path(dir, name .. "-" .. os.date("%Y%m%d-%H%M%S") .. ".mkv")
    mp.set_property("stream-record", file)
    ctx.toast("Shift+R", "Recording… (Shift+R to stop)")
end

function M.media_info_lines()
    local lines = {}
    local function add(k, v) if v and v ~= "" then lines[#lines + 1] = { k, tostring(v) } end end
    add("Title", mp.get_property("media-title"))
    local md = mp.get_property_native("metadata") or {}
    local function meta(k) return md[k] or md[k:upper()] or md[k:sub(1, 1):upper() .. k:sub(2)] end
    add("Artist", meta("artist"))
    add("Album", meta("album"))
    add("Date", meta("date"))
    add("File", mp.get_property("filename"))
    add("Format", mp.get_property("file-format"))
    local vp = mp.get_property_native("video-params")
    if vp and vp.w then
        add("Video", string.format("%s  %dx%d  %.3g fps", mp.get_property("video-format") or "", vp.w, vp.h,
            mp.get_property_number("container-fps", 0)))
        add("Colors", (vp.primaries or "") .. " / " .. (vp.gamma or ""))
        add("Hardware decoding", mp.get_property("hwdec-current"))
    end
    local ap = mp.get_property_native("audio-params")
    if ap and ap.samplerate then
        add("Audio", string.format("%s  %d Hz  %s", mp.get_property("audio-codec-name") or "", ap.samplerate, ap["hr-channels"] or ""))
    end
    local br = mp.get_property_number("video-bitrate") or 0
    local abr = mp.get_property_number("audio-bitrate") or 0
    if br + abr > 0 then add("Bitrate", string.format("%.0f kbps", (br + abr) / 1000)) end
    local size = mp.get_property_number("file-size")
    if size then add("Size", string.format("%.1f MB", size / 1048576)) end
    return lines
end

return M
