local _, ns = ...

-- Any key without a translation shows the English text itself, so a missing entry never breaks the UI.
ns.L = setmetatable({}, { __index = function(_, key) return key end })
