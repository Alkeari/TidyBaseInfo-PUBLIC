-- The one place this mod declares a color. Tokens are Alkeari Design System names; every widget
-- color in Tidy Base Info comes from Palette.color, so no other file carries a color literal.
local Palette = {}

Palette.tokens = {
    -- The plate behind the right-click action menu.
    deepGraphite = "1A1A1A",

    -- The thin edge around the menu plate and around each of its entries.
    hairline = "333333",

    -- The fill behind one entry of the action menu.
    raised = "2E2E2E",

    -- The fill behind the action menu entry the mouse is over.
    raisedHover = "3D3D3D",

    -- The focus ring around the action menu entry the mouse is over.
    forgedGold = "FFDA00",

    -- The label text of an action menu entry.
    softChampagne = "FFF1B3",
}

local function channel(hex, at)
    return tonumber(hex:sub(at, at + 1), 16) / 255
end

-- The FLinearColor table for a token name, opaque unless `alpha` says otherwise. An unknown
-- name yields black rather than nil, so a color setter is never handed a missing struct.
function Palette.color(name, alpha)
    local hex = Palette.tokens[name] or "000000"
    return {
        R = channel(hex, 1),
        G = channel(hex, 3),
        B = channel(hex, 5),
        A = alpha or 1.0,
    }
end

-- Fully transparent, for a widget that has to catch clicks without painting anything.
function Palette.none()
    return { R = 0, G = 0, B = 0, A = 0 }
end

-- Ease-out for the design system's one transition curve: fast first, settling at the end.
-- `t` is linear progress, clamped to 0 through 1.
function Palette.ease(t)
    if t <= 0 then
        return 0
    end
    if t >= 1 then
        return 1
    end
    local remaining = 1 - t
    return 1 - remaining * remaining
end

-- The color `progress` of the way from one color to another, for a state change that fades
-- rather than snaps. Always a fresh table, so neither end of the fade is ever written through.
function Palette.blend(from, to, progress)
    if progress <= 0 then
        progress = 0
    elseif progress >= 1 then
        progress = 1
    end
    return {
        R = from.R + (to.R - from.R) * progress,
        G = from.G + (to.G - from.G) * progress,
        B = from.B + (to.B - from.B) * progress,
        A = from.A + (to.A - from.A) * progress,
    }
end

return Palette
