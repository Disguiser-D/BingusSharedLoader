local source = assert(arg[1])

local function scenario(entity_available)
    local writes, spawned, destroyed = {}, 0, 0
    local now = 30
    local entity = {}
    local drone = {}
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.CowboyBingusModLoader = {open_log = function(name)
        assert(name == 'SeekerDroneEntityProbe.log')
        return {write = function(_, data) writes[#writes + 1] = data end,
                close = function() end}
    end}
    env.stingray = {
        Application = {
            main_world = function() return 'mission' end,
            can_get = function(kind)
                if kind == 'unit' then return true end
                assert(kind == 'entity')
                return entity_available
            end,
            time_since_launch = function() return now end,
        },
        World = {units_by_resource = function() return {drone} end},
        Unit = {alive = function() return true end,
                world_position = function() return {1, 2, 3} end,
                world_rotation = function() return 'rotation' end},
        Vector3 = {add = function() return {1, 2, 5} end,
                   multiply = function() return {0, 0, 2} end,
                   up = function() return {0, 0, 1} end,
                   to_elements = function(p) return p[1], p[2], p[3] end},
        EntityManager = {
            spawn = function(_, name)
                assert(name:find('self_destruct_drone', 1, true))
                spawned = spawned + 1
                return entity
            end,
            alive = function(e) assert(e == entity); return true end,
            unit_component = function() return 'component' end,
            destroy = function(e) assert(e == entity); destroyed = destroyed + 1 end,
        },
        UnitComponent = {unit = function() return drone end},
    }
    env.update = function(a, b) assert(a == 4 and b == nil); return 5, nil end
    assert(setfenv(assert(loadfile(source)), env)() == nil)
    local function pack(...) return {n = select('#', ...), ...} end
    local result = pack(env.update(4, nil))
    assert(result.n == 2 and result[1] == 5 and result[2] == nil)
    assert(spawned == (entity_available and 1 or 0))
    if entity_available then
        now = 32
        env.update(4, nil)
        now = 51
        env.update(4, nil)
        assert(destroyed == 1)
    else
        assert(destroyed == 0)
    end
    env.update(4, nil)
    assert(spawned == (entity_available and 1 or 0))
    local log = writes[#writes]
    assert(log:find('g50_entity_available=' .. tostring(entity_available), 1, true))
    return log
end

local absent = scenario(false)
assert(absent:find('skipped spawn', 1, true))
local present = scenario(true)
assert(present:find('cleanup=true', 1, true))
print('seeker drone entity probe scenarios passed')
