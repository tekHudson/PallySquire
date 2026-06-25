--[[ PallySquire — English strings.

A tiny self-contained locale table (no AceLocale). ns.L falls back to the key
itself for any missing entry, so other locales can be added incrementally.
]]

local _, ns = ...

local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

-- Blessings
L["Blessing of Wisdom"]    = "Blessing of Wisdom"
L["Blessing of Might"]     = "Blessing of Might"
L["Blessing of Kings"]     = "Blessing of Kings"
L["Blessing of Salvation"] = "Blessing of Salvation"
L["Blessing of Light"]     = "Blessing of Light"
L["Blessing of Sanctuary"] = "Blessing of Sanctuary"
L["Blessing of Sacrifice"] = "Blessing of Sacrifice"

-- UI
L["Assignments"]   = "Assignments"
L["Auto Buff"]     = "Auto Buff"
L["Clear"]         = "Clear"
L["Refresh"]       = "Refresh"
L["Free Assign"]   = "Free Assign"
L["Options"]       = "Options"
L["No paladins in group"] = "No paladins in group"

-- Tooltips
L["DRAG_TOOLTIP"]  = "Drag to move. Right-click for assignments."
L["AUTO_TOOLTIP"]  = "Left-click: buff the next class member that needs it."
