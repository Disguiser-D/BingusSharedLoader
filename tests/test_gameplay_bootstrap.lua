local wrapper = assert(arg[1])
local updates, addon_loaded = 0, false
local entry = 'mods/cowboybingus/vanilla_plus_megapack'
local env = setmetatable({print = function() end,
    os = {getenv = function() return nil end},
    jit = false,
    stingray = {Application = {can_get = function(kind, name)
        assert(kind == 'lua')
        return name == entry
    end}},
    update = function(a, b, c)
        assert(a == 1 and b == nil and c == 3)
        updates = updates + 1
        return 4, nil, 6, nil
    end}, {__index = _G})
env._G = env
env.loadstring = function(bytes, name)
    local chunk, reason = loadstring(bytes, name)
    if chunk then setfenv(chunk, env) end
    return chunk, reason
end
env.require = function(name)
    assert(name == entry)
    local loader = assert(env.CowboyBingusModLoader)
    assert(loader.api == 1 and loader.gameplay.api == 1)
    local missing, reason = loader.gameplay.get('game.entity.spawn_throwable')
    assert(missing == nil and reason == 'not registered')
    local ok = loader.gameplay.register('test.backend', 1, {ready = true}, entry)
    assert(ok)
    local cancel = assert(loader.gameplay.subscribe_update(entry, function()
        updates = updates + 10
    end))
    assert(type(cancel) == 'function')
    addon_loaded = true
    return true
end
local function pack(...) return {n = select('#', ...), ...} end
local stock = pack(setfenv(assert(loadfile(wrapper)), env)())
assert(stock.n == 4 and stock[1] == 'stock' and stock[2] == nil and stock[3] == 3 and stock[4] == nil)
assert(addon_loaded)
local result = pack(env.update(1, nil, 3))
assert(result.n == 4 and result[1] == 4 and result[2] == nil and result[3] == 6 and result[4] == nil)
assert(updates == 11)
print('PASS: bootstrap exposes the gameplay broker before addon startup and preserves update returns')
