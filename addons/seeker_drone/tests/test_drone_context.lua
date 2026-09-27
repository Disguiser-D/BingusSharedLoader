local Context = dofile(assert(arg[1]) .. '/drone_context.lua')
local drones = {'only-drone'}
local engine = {
    Application = {main_world = function() return 'mission-world' end},
    World = {units_by_resource = function(world, name)
        assert(world == 'mission-world')
        assert(name == 'content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg')
        return drones
    end},
    Unit = {
        alive = function(unit) return unit ~= 'dead-drone' end,
        world_position = function(unit, node) assert(unit == 'only-drone' and node == 1); return 'position' end,
        world_rotation = function(unit, node) assert(unit == 'only-drone' and node == 1); return 'rotation' end,
    },
}
local world, position, rotation = Context.locate(engine)
assert(world == 'mission-world' and position == 'position' and rotation == 'rotation')
drones = {}
assert(Context.locate(engine) == nil)
drones = {'a', 'b'}
assert(Context.locate(engine) == nil)
drones = {'dead-drone'}
assert(Context.locate(engine) == nil)
print('seeker drone context scenarios passed')
