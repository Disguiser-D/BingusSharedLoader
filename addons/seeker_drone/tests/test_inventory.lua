local Inventory = dofile(assert(arg[1]) .. '/inventory.lua')

local m = Inventory.new()
local state = m:snapshot()
assert(state.drone.g50 == 200 and state.drone.g60 == 100)
assert(state.backpack.g50 == 1000 and state.backpack.g60 == 500)

-- Two G-50 and one G-60 occupy all three slots, even before spawns complete.
local a, b, c = m:begin_launch('g50'), m:begin_launch('g50'), m:begin_launch('g60')
assert(a and b and c)
assert(not m:begin_launch('g50') and not m:begin_launch('g60'))
assert(m:cancel_launch(b) and not m:cancel_launch(b))
assert(m.drone.g50 == 200)
assert(m:finish_launch(a, 'a') and m:finish_launch(c, 'c'))
assert(not m:finish_launch(a, 'duplicate'))
assert(m.drone.g50 == 199 and m.drone.g60 == 99)
local freed = assert(m:begin_launch('g50'))
assert(m:cancel_launch(freed))
assert(m:entity_gone('a') and not m:entity_gone('a'))
assert(m.airborne.g50 == 0)

-- Failed spawns and duplicate IDs cannot spend ammunition.
assert(m:entity_gone('c'))
local failed = m:begin_launch('g60')
assert(failed)
assert(not m:finish_launch(failed, nil))
assert(m:cancel_launch(failed))
assert(m.drone.g60 == 99)

-- Spend all G-50 units without exceeding the in-flight limit.
for i = 2, 200 do
    local token = assert(m:begin_launch('g50'))
    local id = 'g50-' .. i
    assert(m:finish_launch(token, id))
    assert(m:entity_gone(id))
end
assert(m.drone.g50 == 0 and m:needs_dock())
assert(m:begin_dock() and not m:begin_launch('g60'))
assert(m:finish_dock())
assert(m.drone.g50 == 200 and m.drone.g60 == 100)
assert(m.backpack.g50 == 800 and m.backpack.g60 == 499)

-- Supply replenishes the backpack reserve to its exact capacity.
m:resupply()
assert(m.backpack.g50 == 1000 and m.backpack.g60 == 500)
assert(m.drone.g50 == 200 and m.drone.g60 == 100)

-- When the reserve is short, the drone receives only what remains.
m.drone.g50, m.drone.g60 = 0, 0
m.backpack.g50, m.backpack.g60 = 3, 0
assert(m:begin_dock() and m:finish_dock())
assert(m.drone.g50 == 3 and m.drone.g60 == 0)
assert(m.backpack.g50 == 0 and not m:needs_dock())

-- A single round cannot be promised to two simultaneous spawn requests.
m.drone.g50 = 1
local last = assert(m:begin_launch('g50'))
assert(not m:begin_launch('g50'))
assert(m:finish_launch(last, 'last'))
assert(m.drone.g50 == 0 and m.airborne.g50 == 1)

-- Automatic replacement fills only vacant slots and stops on spawn failure.
local auto = Inventory.new()
local created = {}
local function spawn(kind)
    local id = kind .. '-' .. tostring(#created + 1)
    created[#created + 1] = id
    return id
end
local launches = auto:maintain(spawn)
assert(launches.g50 == 2 and launches.g60 == 0 and #created == 2)
launches = auto:maintain(spawn, function() return nil end, function() return true end)
assert(launches.g60 == 0 and #created == 2)
launches = auto:maintain(spawn, function() return 'light' end, function() return false end)
assert(launches.g60 == 0 and #created == 2)
launches = auto:maintain(spawn, function() return 'heavy' end, function() return 1 end)
assert(launches.g60 == 0 and #created == 2)
launches = auto:maintain(spawn, function() return 'heavy' end, function() return true end)
assert(launches.g50 == 0 and launches.g60 == 1 and #created == 3)
launches = auto:maintain(spawn, function() return 'heavy' end, function() return true end)
assert(launches.g50 == 0 and launches.g60 == 0 and #created == 3)
assert(auto:entity_gone('g60-3'))
local g60_before = auto.drone.g60
launches = auto:maintain(function(kind)
    if kind == 'g60' then return nil end
    return spawn(kind)
end, function() return 'heavy' end, function() return true end)
assert(launches.g60 == 0 and auto.drone.g60 == g60_before)
assert(auto:entity_gone('g50-1'))
launches = auto:maintain(spawn, function() return 'heavy' end, function() return true end)
assert(launches.g50 == 1 and launches.g60 == 1 and #created == 5)
assert(auto:entity_gone('g50-2'))
local before = auto.drone.g50
launches = auto:maintain(function() return nil end)
assert(launches.g50 == 0 and auto.drone.g50 == before)
assert(auto:reconcile(function(entity)
    if entity == 'g50-4' then return false end
    if entity == 'g60-5' then error('temporarily unavailable') end
    return true
end) == 1)
assert(auto.airborne.g50 == 0 and auto.airborne.g60 == 1)
print('seeker drone inventory scenarios passed')
