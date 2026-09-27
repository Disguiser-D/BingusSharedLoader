-- Experimental visual-unit-only Stingray adapter. A live game probe showed
-- that World.spawn_unit creates an inert G-50; do not use it for gameplay.
-- This file is not included in the probe ZIP.
local Adapter = {}

local RESOURCES = {
    g50 = 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone',
    g60 = 'content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone',
}

function Adapter.new(engine, drone_transform)
    assert(type(engine) == 'table', 'engine required')
    assert(type(drone_transform) == 'function', 'drone transform callback required')
    local app, world_api, unit_api = engine.Application, engine.World, engine.Unit
    local self = {}

    function self.spawn(kind)
        local resource = RESOURCES[kind]
        if not resource or not (app and app.can_get and world_api and world_api.spawn_unit) then
            return nil
        end
        if app.can_get('unit', resource) ~= true then return nil end
        local world, position, orientation = drone_transform()
        if not world or not position then return nil end
        return world_api.spawn_unit(world, resource, position, orientation)
    end

    function self.alive(unit)
        if not (unit_api and unit_api.alive) then return nil end
        return unit_api.alive(unit)
    end

    return self
end

return Adapter
