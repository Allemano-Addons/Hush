-- Offline test of Links.lua (not loaded by the game). Run from the Hush folder:  lua Tests/links_test.lua
strlower = string.lower
local Hush = {}
assert(loadfile("Links.lua"))("Hush", Hush)
local L = Hush.Links
local function link(u) return "|cffaabbcc|Hhushurl:" .. u .. "|h" .. u .. "|h|r" end
local cases = {
    { "join https://discord.gg/abc123 now", "join " .. link("https://discord.gg/abc123") .. " now" },
    { "see www.wowhead.com/item=1.", "see " .. link("www.wowhead.com/item=1") .. "." },
    { "discord.gg/slaughter", link("discord.gg/slaughter") },
    { "(curseforge.com/wow/addons/hush)", "(" .. link("curseforge.com/wow/addons/hush") .. ")" },
    { "apply at allemano.com!", "apply at " .. link("allemano.com") .. "!" },
    { "http://a.b/c?x=1&y=2, ok", link("http://a.b/c?x=1&y=2") .. ", ok" },
    -- Not links
    { "omg...what", "omg...what" },
    { "i.e. this", "i.e. this" },
    { "mail me at a@b.com", "mail me at a@b.com" },
    { "lvl 20.5 tank", "lvl 20.5 tank" },
    { "gz.", "gz." },
    { "e.g. test", "e.g. test" },
    { "no dots here", "no dots here" },
    -- Game links stay untouched, addresses around them still work
    { "WTS |cffffffff|Hitem:1:0|h[Sword.com]|h|r see wowhead.com",
      "WTS |cffffffff|Hitem:1:0|h[Sword.com]|h|r see " .. link("wowhead.com") },
}
local bad = 0
for _, c in ipairs(cases) do
    local got = L.Linkify(c[1], "aabbcc")
    if got ~= c[2] then bad = bad + 1; print("BAD  " .. c[1] .. "\n  got:  " .. got .. "\n  want: " .. c[2]) else print("OK   " .. c[1]) end
end
assert(L.Url("hushurl:https://x.y/z") == "https://x.y/z")
assert(L.Url("item:1:0") == nil)
print(bad == 0 and "ALL OK" or (bad .. " wrong"))
assert(L.Linkify("trust.me ok.no", "aabbcc") == "trust.me ok.no", "word-like endings are not links")
print("WORDS OK")
