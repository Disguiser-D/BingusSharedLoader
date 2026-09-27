local source = assert(arg[1])
local writes = {}
local env = setmetatable({}, {__index = _G})
env._G = env
env.CowboyBingusModLoader = {open_log = function(name)
    assert(name == 'SeekerDroneApiProbe.log')
    return {write = function(_, value) writes[#writes + 1] = value end,
            close = function() end}
end}
env.stingray = {
    Unit = {alive = function() return true end,
            armor_level = function() return 5 end},
    World = {spawn_unit = function() error('must not spawn') end},
    Targeting = {find_target = function() error('must not query') end},
}
env.update = function(a, b) assert(a == 7 and b == nil); return 11, nil end
assert(setfenv(assert(loadfile(source)), env)() == nil)
local wrapped = env.update
local function pack(...) return {n = select('#', ...), ...} end
local result = pack(wrapped(7, nil))
assert(result.n == 2 and result[1] == 11 and result[2] == nil)
assert(#writes > 0)
local log = table.concat(writes)
assert(log:find('stingray.Unit', 1, true))
assert(log:find('armor_level:function', 1, true))
assert(log:find('stingray.Targeting', 1, true))
assert(log:find('find_target:function', 1, true))
local before = #writes
wrapped(7, nil)
assert(#writes == before)
print('seeker drone read-only API probe scenarios passed')
