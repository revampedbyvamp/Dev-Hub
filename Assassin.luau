-- Assassin.luau
-- PlaceId-gated bootstrap loader. When executed in Roblox PlaceId 379614936,
-- this script downloads the canonical version of itself from GitHub and runs
-- it via loadstring. Local edits are ignored; the remote file is the
-- authoritative copy once this loader is in place.

local PLACE_ID = 379614936
local SOURCE_URL = "https://raw.githubusercontent.com/revampedbyvamp/Dev-Hub/refs/heads/main/Assassin.luau"

if game.PlaceId ~= PLACE_ID then
    return
end

local body = game:HttpGet(SOURCE_URL)

local fn, err = loadstring(body, SOURCE_URL)
if not fn then
    warn("[Assassin] loadstring failed:", err)
    return
end

local ok, execErr = pcall(fn)
if not ok then
    warn("[Assassin] remote execution failed:", execErr)
end
