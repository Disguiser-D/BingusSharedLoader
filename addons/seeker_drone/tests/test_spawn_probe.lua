local source = assert(arg[1])
local clock, spawned, destroyed, writes = 0, 0, 0, {}
local drone, extra = {}, nil
local env = setmetatable({}, {__index = _G})
env._G = env
env.CowboyBingusModLoader = {open_log = function()
    return {write = function(_, line) writes[#writes + 1] = line end,
        close = function() end}
end}
env.stingray = {
    Application = {
        time_since_launch = function() return clock end,
        can_get = function(kind, resource)
            assert(kind == 'unit' and resource:find('self_destruct_drone', 1, true))
            return true
        end,
        main_world = function() return 'mission' end,
    },
    World = {
        units_by_resource = function(world, resource)
            assert(world == 'mission' and resource:find('drone_mg', 1, true))
            return {drone}
        end,
        spawn_unit = function(world, resource, position, rotation)
            assert(world == 'mission' and rotation == 'rotation')
            assert(resource:find('/self_destruct_drone/', 1, true))
            assert(not resource:find('at_self_destruct_drone', 1, true))
            assert(position[3] == 12)
            spawned = spawned + 1
            extra = {}
            return extra
        end,
        destroy_unit = function(world, unit)
            assert(world == 'mission' and unit == extra)
            destroyed = destroyed + 1
        end,
    },
    Unit = {
        world_position = function(unit)
            if unit == drone then return {1, 2, 10} end
            assert(unit == extra)
            return {1, 2, 12}
        end,
        world_rotation = function(unit) assert(unit == drone); return 'rotation' end,
        alive = function(unit) assert(unit == extra); return true end,
    },
    Vector3 = {
        up = function() return {0, 0, 1} end,
        multiply = function(v, k) return {v[1]*k, v[2]*k, v[3]*k} end,
        add = function(a, b) return {a[1]+b[1], a[2]+b[2], a[3]+b[3]} end,
        to_elements = function(v) return v[1], v[2], v[3] end,
    },
}
env.update = function() return 7, nil, 9 end
assert(setfenv(assert(loadfile(source)), env)() == nil)
local function pack(...) return {n = select('#', ...), ...} end
local result = pack(env.update())
assert(result.n == 3 and result[1] == 7 and result[2] == nil and result[3] == 9)
clock = 3.2
env.update()
assert(spawned == 1 and destroyed == 0)
clock = 4.5
env.update()
assert(writes[#writes]:find('spawned_unit', 1, true))
clock = 23.3
env.update()
assert(spawned == 1 and destroyed == 1)
clock = 24
env.update()
assert(spawned == 1 and destroyed == 1)
print('seeker drone spawn probe scenarios passed')
