local gameplay_api = assert(loadfile(assert(arg[1])))()

local originals, events, problems = 0, {}, {}
local globals = {update = function(a, b, c)
    originals = originals + 1
    assert(a == 7 and b == nil and c == 9)
    return 1, nil, 3, nil
end}
local original_update = globals.update
local loader = {}
local api = gameplay_api.start(loader, globals, function(kind, owner, reason)
    problems[#problems + 1] = kind .. ':' .. owner .. ':' .. tostring(reason)
end)
assert(api == loader.gameplay and api.api == 1)
assert(gameplay_api.start(loader, globals) == api)
assert(globals.update == original_update, 'the update hook must be lazy')

local absent, reason = api.get('game.entity.spawn_throwable')
assert(absent == nil and reason == 'not registered')
assert(not api.register('../bad', 1, {}, 'mods/test'))
assert(not api.register('game.entity.spawn_throwable', 0, {}, 'mods_test'))
assert(not api.register('game.entity.spawn_throwable', 1, function() end, 'mods_test'))

local calls = 0
assert(api.when_available('game.entity.spawn_throwable', 1, 'consumer', function(provider, version, owner)
    assert(provider.spawn and version == 2 and owner == 'mods/tzy/native_bridge')
    calls = calls + 1
end))
assert(api.when_available('game.entity.spawn_throwable', 3, 'future_consumer', function()
    error('old version should not be delivered')
end))
assert(api.when_available('game.entity.spawn_throwable', 1, 'broken_consumer', function()
    error('listener failure')
end))
local provider = {spawn = function() return 'native entity' end}
assert(api.register('game.entity.spawn_throwable', 2, provider, 'mods/tzy/native_bridge'))
assert(calls == 1 and #api.errors == 2)
assert(not api.register('game.entity.spawn_throwable', 2, {}, 'other_owner'))
local actual, version, owner = api.get('game.entity.spawn_throwable', 2)
assert(actual == provider and version == 2 and owner == 'mods/tzy/native_bridge')
assert(api.get('game.entity.spawn_throwable', 3) == nil)
assert(api.when_available('game.entity.spawn_throwable', 1, 'late_consumer', function(value)
    assert(value == provider)
    calls = calls + 1
end))
assert(calls == 2)

local stop = assert(api.subscribe_update('healthy', function(a, b, c)
    assert(a == 7 and b == nil and c == 9)
    events[#events + 1] = 'healthy'
end))
assert(globals.update ~= original_update)
assert(api.subscribe_update('broken', function()
    events[#events + 1] = 'broken'
    error('callback failure')
end))
local function pack(...) return {n = select('#', ...), ...} end
local first = pack(globals.update(7, nil, 9))
assert(first.n == 4 and first[1] == 1 and first[2] == nil and first[3] == 3 and first[4] == nil)
assert(originals == 1 and table.concat(events, ',') == 'healthy,broken')
assert(#api.errors == 3 and problems[3]:find('update:broken', 1, true))
globals.update(7, nil, 9)
assert(originals == 2 and table.concat(events, ',') == 'healthy,broken,healthy')
assert(stop() and not stop())
globals.update(7, nil, 9)
assert(originals == 3 and #events == 3)

local unavailable = gameplay_api.start({}, {})
assert(unavailable.subscribe_update('addon', function() end) == nil)
print('PASS: gameplay provider registration, version checks, callback isolation and lazy update dispatch')
