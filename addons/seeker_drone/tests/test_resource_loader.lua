local Loader = dofile(assert(arg[1]) .. '/resource_loader.lua')
local created, flushed, unloaded, available = {}, {}, {}, false
local engine = {
    Application = {
        resource_package = function(name)
            assert(name:find('packages/generated/loadout/', 1, true) == 1)
            created[#created + 1] = name
            return name
        end,
        can_get = function(kind, name)
            assert(kind == 'unit' and name:find('self_destruct_drone', 1, true))
            return available
        end,
        release_resource_package = function(name) unloaded[#unloaded + 1] = name end,
    },
    ResourcePackage = {
        load = function(name) assert(name:find('packages/generated/loadout/', 1, true)) end,
        has_loaded = function() return available end,
        flush = function(name) flushed[#flushed + 1] = name end,
        unload = function(name) unloaded[#unloaded + 1] = name end,
    },
}
local loader = Loader.new(engine)
assert(not loader:poll() and loader.status == 'idle')
assert(loader:start() and #created == 2 and loader.status == 'loading')
assert(loader:start() and #created == 2)
assert(not loader:poll() and #flushed == 0)
available = true
assert(loader:poll() and loader.status == 'ready' and #flushed == 2)
assert(loader:poll() and #flushed == 2)
loader:close()
assert(loader.status == 'idle' and #unloaded == 4)

local unavailable = Loader.new({Application = {}})
assert(not unavailable:start() and unavailable.status == 'unavailable')
print('seeker drone resource loader scenarios passed')
