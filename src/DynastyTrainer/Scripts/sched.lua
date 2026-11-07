-- Safe scheduling on the game thread.
-- UE4SS keeps only a registry ref to callbacks; if Lua's GC collects the
-- closure first, the engine tick fails with "Ref was not function" and the
-- game can crash. So every callback we hand to UE4SS is pinned here.

local M = {}

local ring, index = {}, 0
local forever = {}

function M.pin(fn)
    index = index % 512 + 1
    ring[index] = fn
    return fn
end

-- Run fn on the game thread soon (pinned until 512 later calls).
function M.run(fn)
    ExecuteInGameThread(M.pin(fn))
end

-- Run fn on the game thread after ms milliseconds.
function M.after(ms, fn)
    if type(ExecuteInGameThreadWithDelay) == "function" then
        ExecuteInGameThreadWithDelay(ms, M.pin(fn))
    else
        ExecuteWithDelay(ms, M.pin(function() ExecuteInGameThread(M.pin(fn)) end))
    end
end

-- Repeat fn on the game thread every ms milliseconds. fn is pinned forever.
function M.every(ms, fn)
    local tick = function() fn(); return false end
    forever[#forever + 1] = tick
    if type(LoopInGameThreadWithDelay) == "function" then
        forever[#forever + 1] = LoopInGameThreadWithDelay(ms, tick)
    else
        local async = function() ExecuteInGameThread(tick); return false end
        forever[#forever + 1] = async
        LoopAsync(ms, async)
    end
end

return M
