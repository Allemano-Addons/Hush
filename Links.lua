-- Links: web addresses in messages become clickable (click = copy box). Only the displayed
-- text changes; the saved message is untouched. Item links and other game links are left alone.
local _, Hush = ...

local Links = {}
Hush.Links = Links

Links.PREFIX = "hushurl"

-- Top-level domains accepted for addresses without http:// or www. ("discord.gg/abc").
local TLD = {}
for tld in ("com net org gg io tv se eu de uk fr nl dk fi pl ru ca ly app dev info xyz cc"):gmatch("%a+") do
    TLD[tld] = true
end

local function isUrl(s)
    if s:find("@", 1, true) then return false end -- mail addresses are not links
    local lower = strlower(s)
    if lower:match("^https?://[%w%-]+") then return true end
    if lower:match("^www%.[%w%-]+%.%a") then return true end
    -- name.tld or name.tld/path (the name must start with a letter or digit)
    local host = lower:match("^([%w][%w%-%.]*%.%a+)[/:?#]") or lower:match("^([%w][%w%-%.]*%.%a+)$")
    if host then
        local tld = host:match("%.(%a+)$")
        return tld ~= nil and TLD[tld] == true and not host:find("..", 1, true)
    end
    return false
end

local function wrapWord(word, color)
    -- Keep leading "(" / "<" and trailing punctuation outside the link.
    local lead, core = word:match("^([%(%[<\"']*)(.*)$")
    local trail = ""
    while #core > 0 do
        local last = core:sub(-1)
        if last:match("[%.,;:!%?%)%]>\"']") then
            trail = last .. trail
            core = core:sub(1, -2)
        else
            break
        end
    end
    if core == "" or not isUrl(core) then return word end
    return ("%s|cff%s|H%s:%s|h%s|h|r%s"):format(lead, color, Links.PREFIX, core, core, trail)
end

local function linkifyPlain(s, color)
    return (s:gsub("%S+", function(word)
        -- A pipe means an escape code inside the word: never touch it.
        if word:find("|", 1, true) then return word end
        return wrapWord(word, color)
    end))
end

-- text -> text with web addresses as |Hhushurl:...|h links in the given color ("RRGGBB").
function Links.Linkify(text, color)
    if not text or text == "" or not text:find(".", 1, true) then return text end
    color = color or "3fc7eb"
    -- Leave existing game links (|H...|h...|h) exactly as they are.
    local out, pos = {}, 1
    while true do
        local s, e = text:find("|H.-|h.-|h", pos)
        if not s then break end
        out[#out + 1] = linkifyPlain(text:sub(pos, s - 1), color)
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    out[#out + 1] = linkifyPlain(text:sub(pos), color)
    return table.concat(out)
end

-- The address of a hushurl link, or nil for any other link.
function Links.Url(link)
    return link and link:match("^" .. Links.PREFIX .. ":(.+)$")
end
