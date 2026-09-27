-- HD2-Addon: mods/tzy/seeker_drone_spawn_probe
-- One-shot G-50 spawn experiment; never generates G-60.
if rawget(_G, 'TzySeekerDroneSpawnProbe') then return end

local state = {lines = {'Seeker Drone spawn probe v1: loaded'}, started = nil,
    last_tick = nil, drone_seen_at = nil, attempted = false, spawned = nil,
    spawned_at = nil, last_detail = nil, finished = false}
rawset(_G, 'TzySeekerDroneSpawnProbe', state)

local G50 = 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone'
local DRONE = 'content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg'

local function log(line)
    state.lines[#state.lines + 1] = line
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneSpawnProbe.log')
        if file then
            file:write(table.concat(state.lines, '\n') .. '\n')
            file:close()
        end
    end)
end

local function position_text(engine, unit)
    local ok, x, y, z = pcall(function()
        local pos = engine.Unit.world_position(unit, 1)
        return engine.Vector3.to_elements(pos)
    end)
    if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
        return string.format('%.2f,%.2f,%.2f', x, y, z)
    end
    return 'unavailable'
end

local function attempt(engine, world, drone, now)
    state.attempted = true
    local ok, unit_or_error = pcall(function()
        local origin = engine.Unit.world_position(drone, 1)
        local above = engine.Vector3.add(origin,
            engine.Vector3.multiply(engine.Vector3.up(), 2))
        local rotation = engine.Unit.world_rotation(drone, 1)
        return engine.World.spawn_unit(world, G50, above, rotation)
    end)
    if not ok or not unit_or_error then
        log('spawn_failed=' .. tostring(unit_or_error))
        state.finished = true
        return
    end
    state.spawned, state.spawned_at, state.world = unit_or_error, now, world
    log(string.format('spawned t=%.2f pos=%s', now,
        position_text(engine, unit_or_error)))
end

local function tick(now)
    local engine = rawget(_G, 'stingray')
    local app = engine and engine.Application
    if not (app and engine.World and engine.Unit and engine.Vector3) then return end
    if state.spawned then
        local alive = engine.Unit.alive(state.spawned)
        if not alive then
            log(string.format('spawned_unit_gone t=%.2f', now))
            state.spawned, state.finished = nil, true
            return
        end
        if not state.last_detail or now - state.last_detail >= 1 then
            state.last_detail = now
            log(string.format('spawned_unit t=%.2f pos=%s', now,
                position_text(engine, state.spawned)))
        end
        if now - state.spawned_at >= 20 then
            local ok, err = pcall(engine.World.destroy_unit, state.world, state.spawned)
            log('cleanup=' .. (ok and 'success' or tostring(err)))
            state.spawned, state.finished = nil, true
        end
        return
    end
    if state.attempted or app.can_get('unit', G50) ~= true then return end
    local world = app.main_world()
    if not world then return end
    local drones = engine.World.units_by_resource(world, DRONE)
    if not drones or #drones ~= 1 then
        state.drone_seen_at = nil
        return
    end
    if not state.drone_seen_at then
        state.drone_seen_at = now
        log(string.format('one_drone_seen t=%.2f pos=%s', now,
            position_text(engine, drones[1])))
    elseif now - state.drone_seen_at >= 3 then
        attempt(engine, world, drones[1], now)
    end
end

log('waiting_for_one_drone_and_loaded_g50')
local previous = rawget(_G, 'update')
if type(previous) == 'function' then
    local function pack(...) return {n = select('#', ...), ...} end
    local unpack_values = unpack or table.unpack
    update = function(...)
        local result = pack(previous(...))
        if not state.finished then
            local app = stingray and stingray.Application
            local ok, now = pcall(function() return app.time_since_launch() end)
            if ok and type(now) == 'number' then
                if not state.started then state.started = now end
                if now - state.started > 600 then
                    state.finished = true
                    log('timeout_without_spawn')
                elseif not state.last_tick or now - state.last_tick >= 0.2 then
                    state.last_tick = now
                    local tick_ok, err = pcall(tick, now)
                    if not tick_ok then
                        state.finished = true
                        log('tick_error=' .. tostring(err))
                    end
                end
            end
        end
        return unpack_values(result, 1, result.n)
    end
else
    log('update_callback=unavailable')
end
