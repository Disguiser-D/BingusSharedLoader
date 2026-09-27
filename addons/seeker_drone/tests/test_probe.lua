local source = assert(arg[1])
local writes, updates, game_time = {}, 0, 0
local worlds = {'menu', 'mission'}
local g60_count, available = 0, false
local env = setmetatable({}, {__index = _G})

env._G = env
env.CowboyBingusModLoader = {open_log = function(name)
    assert(name == 'SeekerDroneProbe.log')
    return {write = function(_, value) writes[#writes + 1] = value end, close = function() end}
end}
env.stingray = {
    Application = {
        can_get = function(kind, path)
            assert(kind == 'unit' and type(path) == 'string')
            return available
        end,
        main_world = function() return 'menu' end,
        worlds = function() return worlds end,
        time_since_launch = function() return game_time end,
    },
    World = {
        units_by_resource = function(world, path)
            if world == 'mission' and path:find('at_self_destruct_drone', 1, true) then
                local result = {}
                for i = 1, g60_count do result[i] = i end
                return result
            end
            return {}
        end,
        spawn_unit = function() error('probe must not spawn a unit') end,
    },
    Unit = {
        alive = function() return true end,
        world_position = function(unit) return {unit, 2, 3} end,
    },
    Vector3 = {to_elements = function(position)
        return position[1], position[2], position[3]
    end},
}
env.update = function(a, b, c)
    updates = updates + 1
    assert(a == 1 and b == nil and c == 3)
    return 4, nil, 6, nil
end

assert(setfenv(assert(loadfile(source)), env)() == nil)
local wrapped = env.update
assert(#writes == 1 and writes[1]:find('probe v5: loaded', 1, true))
local function pack(...) return {n = select('#', ...), ...} end
local first = pack(wrapped(1, nil, 3))
assert(first.n == 4 and first[1] == 4 and first[2] == nil and first[3] == 6 and first[4] == nil)
assert(env.TzySeekerDroneProbe.samples == 1)
assert(writes[#writes]:find('worlds=2', 1, true))
local before = #writes
game_time = 0.05
wrapped(1, nil, 3)
assert(env.TzySeekerDroneProbe.samples == 1 and #writes == before)
game_time = 0.11
g60_count = 1
wrapped(1, nil, 3)
assert(env.TzySeekerDroneProbe.samples == 2 and #writes == before + 2)
assert(writes[#writes]:find('g60@w2', 1, true))
assert(writes[#writes]:find('xyz=1.00,2.00,3.00', 1, true))
assert(env.TzySeekerDroneProbe.max_g60 == 1)
game_time = 0.22
g60_count, available = 0, true
wrapped(1, nil, 3)
assert(writes[#writes]:find('g60:true', 1, true))
assert(setfenv(assert(loadfile(source)), env)() == nil and env.update == wrapped)
assert(updates == 4)
print('seeker drone probe scenarios passed')
