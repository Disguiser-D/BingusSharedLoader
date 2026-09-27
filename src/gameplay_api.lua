-- Optional coordination for gameplay backends supplied by other addons.
-- This module does not implement Helldivers 2 entity or stratagem APIs.
local gameplay_api = {}

local function valid_name(name)
    return type(name) == 'string' and #name > 0 and #name <= 96
        and name:match('^[%w_%.]+$') ~= nil
        and name:sub(1, 1) ~= '.' and name:sub(-1) ~= '.'
        and not name:find('..', 1, true)
end

local function valid_owner(owner)
    return type(owner) == 'string' and #owner > 0 and #owner <= 128
        and owner:match('^[%w_%./]+$') ~= nil
        and owner:sub(1, 1) ~= '/' and owner:sub(-1) ~= '/'
        and not owner:find('..', 1, true) and not owner:find('//', 1, true)
end

function gameplay_api.start(loader, globals, on_error)
    assert(type(loader) == 'table', 'loader required')
    assert(type(globals) == 'table', 'globals required')
    if loader.gameplay then return loader.gameplay end
    on_error = on_error or function() end

    local providers, waiters, updates = {}, {}, {}
    local public = {api = 1, errors = {}}
    loader.gameplay = public

    local function record_error(kind, owner, reason)
        if #public.errors < 32 then
            public.errors[#public.errors + 1] = kind .. ' ' .. owner .. ': ' .. tostring(reason)
        end
        pcall(on_error, kind, owner, reason)
    end

    -- A provider may expose a game-native implementation, but registration
    -- does not imply that the game has loaded or verified that implementation.
    function public.register(name, version, provider, owner)
        if not valid_name(name) then return false, 'invalid capability name' end
        if type(version) ~= 'number' or version < 1 or version % 1 ~= 0 then
            return false, 'invalid capability version'
        end
        if type(provider) ~= 'table' then return false, 'provider must be a table' end
        if not valid_owner(owner) then return false, 'invalid owner name' end
        if providers[name] then return false, 'already registered by ' .. providers[name].owner end
        local entry = {version = version, provider = provider, owner = owner}
        providers[name] = entry
        local listeners = waiters[name]
        waiters[name] = nil
        if listeners then
            for _, listener in ipairs(listeners) do
                if version >= listener.minimum then
                    local ok, reason = pcall(listener.callback, provider, version, owner)
                    if not ok then record_error('capability', listener.owner, reason) end
                else
                    record_error('capability', listener.owner, 'version too old: ' .. name)
                end
            end
        end
        return true
    end

    function public.get(name, minimum)
        if not valid_name(name) then return nil, 'invalid capability name' end
        minimum = minimum or 1
        if type(minimum) ~= 'number' or minimum < 1 or minimum % 1 ~= 0 then
            return nil, 'invalid minimum version'
        end
        local entry = providers[name]
        if not entry then return nil, 'not registered' end
        if entry.version < minimum then return nil, 'version too old' end
        return entry.provider, entry.version, entry.owner
    end

    -- Pending callbacks run once when the first compatible provider arrives.
    -- A published provider is never replaced during the current game session.
    function public.when_available(name, minimum, owner, callback)
        if not valid_name(name) then return false, 'invalid capability name' end
        if type(minimum) ~= 'number' or minimum < 1 or minimum % 1 ~= 0 then
            return false, 'invalid minimum version'
        end
        if not valid_owner(owner) or type(callback) ~= 'function' then
            return false, 'invalid listener'
        end
        local entry = providers[name]
        if entry then
            if entry.version < minimum then return false, 'version too old' end
            local ok, reason = pcall(callback, entry.provider, entry.version, entry.owner)
            if not ok then record_error('capability', owner, reason) end
            return ok, ok and nil or tostring(reason)
        end
        local listeners = waiters[name] or {}
        listeners[#listeners + 1] = {minimum = minimum, owner = owner, callback = callback}
        waiters[name] = listeners
        return true
    end

    -- The first subscriber lazily wraps the current update function. Existing
    -- startup behavior stays unchanged when no addon subscribes.
    function public.subscribe_update(owner, callback)
        if not valid_owner(owner) or type(callback) ~= 'function' then
            return nil, 'invalid update subscriber'
        end
        if not public.update_installed then
            local previous = rawget(globals, 'update')
            if type(previous) ~= 'function' then return nil, 'update unavailable' end
            globals.update = function(...)
                -- Run subscribers first so the original call stays a tail call:
                -- no per-frame result table and no change to trailing nils.
                for index = 1, #updates do
                    local subscription = updates[index]
                    if subscription.active then
                        local ok, reason = pcall(subscription.callback, ...)
                        if not ok then
                            subscription.active = false
                            record_error('update', subscription.owner, reason)
                        end
                    end
                end
                return previous(...)
            end
            public.update_installed = true
        end
        local subscription = {owner = owner, callback = callback, active = true}
        updates[#updates + 1] = subscription
        return function()
            if not subscription.active then return false end
            subscription.active = false
            return true
        end
    end

    return public
end

return gameplay_api
