-- Experimental single-drone locator for a prototype that occupies the
-- existing machine-gun Guard Dog slot. It never assumes ownership when
-- multiple matching drones are present in the world.
local Context = {}
local DRONE = 'content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg'

function Context.locate(engine)
    local app, world_api, unit_api = engine and engine.Application,
        engine and engine.World, engine and engine.Unit
    if not (app and app.main_world and world_api and world_api.units_by_resource
        and unit_api and unit_api.alive and unit_api.world_position and unit_api.world_rotation) then
        return nil
    end
    local world = app.main_world()
    if not world then return nil end
    local drones = world_api.units_by_resource(world, DRONE)
    if not drones or #drones ~= 1 then return nil end
    local drone = drones[1]
    if unit_api.alive(drone) ~= true then return nil end
    return world, unit_api.world_position(drone, 1), unit_api.world_rotation(drone, 1)
end

return Context
