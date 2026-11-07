-- Translations. Each language is a file in Scripts/locales/<code>.lua returning
-- { name = "...", plural = function(n) -> form index, strings = { key = "text" | {forms...} } }.
-- To add a language: copy locales/en.lua, translate it, add its code to LANGUAGES.

local M = {}

-- Same languages as the game (Steam store list).
M.LANGUAGES = { "en", "de", "es", "fr", "it", "pl", "pt-BR", "pt-PT", "ru", "uk", "cs", "hu",
    "nl", "sv", "tr", "ja", "ko", "zh-Hans" }
M.DEFAULT = "en"

local locales = {}
local current = M.DEFAULT

local function load(code)
    if locales[code] == nil then
        local ok, data = pcall(require, "locales." .. code)
        locales[code] = ok and type(data) == "table" and data or false
        if not ok then print("[DynastyTrainer] cannot load locale '" .. code .. "': " .. tostring(data) .. "\n") end
    end
    return locales[code] or nil
end

function M.set(code)
    if load(code) then current = code; return true end
    return false
end

function M.get() return current end

function M.name(code) local l = load(code or current); return l and l.name or code end

function M.next()
    for i, code in ipairs(M.LANGUAGES) do
        if code == current then return M.LANGUAGES[i % #M.LANGUAGES + 1] end
    end
    return M.DEFAULT
end

-- Thousands separator per language, e.g. 10,000 vs 10 000.
function M.number(n)
    local l = load(current) or load(M.DEFAULT)
    local sep = l.thousands or ","
    local s = tostring(math.floor(n))
    local sign, digits = s:match("^(-?)(%d+)$")
    digits = digits:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    if digits:sub(1, #sep) == sep then digits = digits:sub(#sep + 1) end
    return sign .. digits
end

-- t("key", {var = value, ...}); for plural entries pass `count`.
function M.t(key, vars)
    vars = vars or {}
    local function lookup(code)
        local l = load(code)
        local s = l and l.strings[key]
        if type(s) == "table" then
            local idx = l.plural and l.plural(math.floor(vars.count or 0)) or 1
            s = s[idx] or s[#s]
        end
        return s
    end
    local s = lookup(current) or lookup(M.DEFAULT) or key
    return (s:gsub("{(%w+)}", function(k)
        local v = vars[k]
        if type(v) == "number" then return M.number(v) end
        return v ~= nil and tostring(v) or "{" .. k .. "}"
    end))
end

return M
