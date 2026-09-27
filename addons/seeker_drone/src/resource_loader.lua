-- Experimental package loader for native seeker units. No game files are
-- changed. Keep packages loaded until all spawned units have disappeared.
local Loader = {}
Loader.__index = Loader

local NAMES = {
    {package = 'packages/generated/loadout/self_destruct_drone',
     unit = 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone'},
    {package = 'packages/generated/loadout/at_self_destruct_drone',
     unit = 'content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone'},
}

function Loader.new(engine)
    return setmetatable({engine = engine, handles = {}, status = 'idle'}, Loader)
end

function Loader:start()
    if self.status ~= 'idle' then return self.status == 'loading' or self.status == 'ready' end
    local app = self.engine and self.engine.Application
    local package_api = self.engine and self.engine.ResourcePackage
    if not (app and app.resource_package and package_api and package_api.load) then
        self.status = 'unavailable'
        return false
    end
    for _, resource in ipairs(NAMES) do
        local ok, handle = pcall(app.resource_package, resource.package)
        if not ok or not handle then self.status = 'failed'; return false end
        self.handles[#self.handles + 1] = handle
        local started = pcall(package_api.load, handle)
        if not started then self.status = 'failed'; return false end
    end
    self.status = 'loading'
    return true
end

function Loader:poll()
    if self.status ~= 'loading' then return self.status == 'ready' end
    local package_api = self.engine.ResourcePackage
    for _, handle in ipairs(self.handles) do
        local ok, loaded = pcall(package_api.has_loaded, handle)
        if not ok then self.status = 'failed'; return false end
        if loaded ~= true then return false end
    end
    for _, handle in ipairs(self.handles) do
        if not pcall(package_api.flush, handle) then
            self.status = 'failed'
            return false
        end
    end
    local app = self.engine.Application
    for _, resource in ipairs(NAMES) do
        local ok, available = pcall(app.can_get, 'unit', resource.unit)
        if not ok or available ~= true then
            self.status = 'failed'
            return false
        end
    end
    self.status = 'ready'
    return true
end

function Loader:close()
    -- The caller must first remove or wait for all units spawned from these
    -- packages. Stingray cannot safely unload a package that is still in use.
    local app = self.engine and self.engine.Application
    local package_api = self.engine and self.engine.ResourcePackage
    for _, handle in ipairs(self.handles) do
        if package_api and package_api.unload then pcall(package_api.unload, handle) end
        if app and app.release_resource_package then pcall(app.release_resource_package, handle) end
    end
    self.handles = {}
    self.status = 'idle'
end

return Loader
