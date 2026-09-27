local Adapter = dofile(assert(arg[1]) .. '/engine_adapter.lua')
local calls, available, has_world = {}, true, true
local engine = {
    Application = {can_get = function(kind, resource)
        assert(kind == 'unit')
        assert(resource:find('self_destruct_drone', 1, true))
        return available
    end},
    World = {spawn_unit = function(world, resource, position, orientation)
        assert(world == 'mission' and position == 'drone-position' and orientation == 'drone-rotation')
        calls[#calls + 1] = resource
        return 'unit-' .. #calls
    end},
    Unit = {alive = function(unit) return unit ~= 'dead-unit' end},
}
local adapter = Adapter.new(engine, function()
    if has_world then return 'mission', 'drone-position', 'drone-rotation' end
end)
assert(adapter.spawn('g50') == 'unit-1')
assert(adapter.spawn('g60') == 'unit-2')
assert(calls[1] == 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone')
assert(calls[2] == 'content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone')
assert(adapter.alive('unit-2') and not adapter.alive('dead-unit'))
available = false
assert(adapter.spawn('g50') == nil and #calls == 2)
available, has_world = true, false
assert(adapter.spawn('g60') == nil and #calls == 2)
assert(adapter.spawn('invalid') == nil and #calls == 2)
print('seeker drone engine adapter scenarios passed')
