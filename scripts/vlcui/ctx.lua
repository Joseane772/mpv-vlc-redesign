-- Shared state for all vlcui modules (a plain table; `require` makes it a singleton).
return {
    w = 0, h = 0,          -- OSD size in pixels
    s = 1,                 -- UI scale factor
    mouse = { x = -1, y = -1, inside = false },
    regions = {},          -- hit regions of the last rendered frame (bottom -> top)
    hover = nil,           -- id of the hovered region
    drag = nil,            -- region currently being dragged
    pressed = nil,         -- region that received mouse-down
    scroll = {},           -- scroll offsets by container id
    clip_stack = {},
    p = {},                -- observed mpv properties
    panel = nil,           -- right panel: nil | "settings" | "queue"
    tab = "subtitles",     -- active tab of the settings sidebar
    library = false,       -- left library panel open
    modal = nil,           -- nil | "settings" | "shortcuts"
    menus = {},            -- open menu stack (context menu, dropdowns, popovers)
    toast = nil,
    ui_hidden = false,
}
