-- HD2-Addon: mods/tzy/seeker_drone_entity_probe
-- One-shot G-50 entity-path test. Never creates G-60.
if rawget(_G, 'TzySeekerDroneEntityProbe') then return end
local state = {lines = {'Seeker drone entity probe: loaded'}, checked = false,
    entity = nil, spawned_at = nil, last_log = nil, finished = false}
rawset(_G, 'TzySeekerDroneEntityProbe', state)

local G50 = 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone'
local DRONE = 'content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg'

local function log(line)
    if #state.lines >= 100 then return end
    state.lines[#state.lines + 1] = line
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneEntityProbe.log')
        if file then
            file:write(table.concat(state.lines, '\n'), '\n')
            file:close()
        end
    end)
end

local function vector_text(engine, unit)
    local ok, x, y, z = pcall(function()
        return engine.Vector3.to_elements(engine.Unit.world_position(unit, 1))
    end)
    if ok then return string.format('%.2f,%.2f,%.2f', x, y, z) end
    return 'unavailable'
end

local function inspect_entity(engine, now)
    local manager = engine.EntityManager
    local ok, alive = pcall(manager.alive, state.entity)
    if not ok or alive ~= true then
        state.finished = true
        state.entity = nil
        log('entity ended before cleanup')
        return
    end
    if not state.last_log or now - state.last_log >= 2 then
        state.last_log = now
        local unit_ok, unit = pcall(function()
            local component = manager.unit_component(state.world)
            return engine.UnitComponent.unit(component, state.entity)
        end)
        log('entity alive=true unit=' .. tostring(unit_ok and unit ~= nil) ..
            ' position=' .. (unit_ok and unit and vector_text(engine, unit) or 'unavailable'))
    end
    if now - state.spawned_at >= 20 then
        local destroyed, reason = pcall(manager.destroy, state.entity)
        state.entity = nil
        state.finished = true
        log('cleanup=' .. tostring(destroyed) ..
            (destroyed and '' or ' reason=' .. tostring(reason)))
    end
end

local function try_once(engine, now)
    if state.checked then return end
    local app, world_api, manager = engine.Application, engine.World, engine.EntityManager
    if not (app and world_api and manager and type(manager.spawn) == 'function') then
        state.checked, state.finished = true, true
        log('required API unavailable')
        return
    end
    local world = app.main_world()
    if not world then return end
    local drones = world_api.units_by_resource(world, DRONE)
    if type(drones) ~= 'table' or #drones ~= 1 then return end
    local drone = drones[1]
    if not engine.Unit.alive(drone) then return end
    local unit_available = app.can_get('unit', G50)
    if unit_available ~= true then return end
    state.checked = true
    local entity_ok, entity_available = pcall(app.can_get, 'entity', G50)
    log('g50_entity_available=' .. (entity_ok and tostring(entity_available) or 'error'))
    if not entity_ok or entity_available ~= true then
        state.finished = true
        log('skipped spawn: entity resource not confirmed available')
        return
    end
    local spawned, entity_or_error = pcall(function()
        local position = engine.Unit.world_position(drone, 1)
        local above = engine.Vector3.add(position,
            engine.Vector3.multiply(engine.Vector3.up(), 2))
        local rotation = engine.Unit.world_rotation(drone, 1)
        return manager.spawn(world, G50, above, rotation)
    end)
    if not spawned or not entity_or_error then
        state.finished = true
        log('spawn failed=' .. tostring(entity_or_error))
        return
    end
    state.entity, state.world, state.spawned_at = entity_or_error, world, now
    log('spawn returned entity; observing for 20 seconds')
end

local previous = rawget(_G, 'update')
if type(previous) == 'function' then
    update = function(...)
        if not state.finished then
            local engine = rawget(_G, 'stingray')
            local ok, reason = pcall(function()
                local app = engine and engine.Application
                local now = app and app.time_since_launch and app.time_since_launch()
                if type(now) ~= 'number' then return end
                if state.entity then inspect_entity(engine, now)
                else try_once(engine, now) end
            end)
            if not ok then
                if state.entity then
                    pcall(engine and engine.EntityManager and engine.EntityManager.destroy,
                        state.entity)
                    state.entity = nil
                end
                state.finished = true
                log('probe error=' .. tostring(reason))
            end
        end
        return previous(...)
    end
else
    log('update callback unavailable')
end
