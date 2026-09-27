-- HD2-Addon: mods/tzy/seeker_drone_probe
-- Read-only runtime probe. It never creates a game unit.
if rawget(_G, 'TzySeekerDroneProbe') then return end

local state = {
    lines = {'Seeker Drone probe v5: loaded'}, samples = 0, frames = 0,
    started_at = nil, last_sample_at = nil, last_log_at = nil,
    last_detail_at = nil, globals_scanned = false,
    last_observation = nil, max_g50 = 0, max_g60 = 0,
}
rawset(_G, 'TzySeekerDroneProbe', state)

local paths = {
    g50 = 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone',
    g60 = 'content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone',
    drone = 'content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg',
}

local function write_log()
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneProbe.log')
        if file then
            file:write(table.concat(state.lines, '\n') .. '\n')
            file:close()
        end
    end)
end

local function add_line(line)
    if #state.lines < 800 then
        state.lines[#state.lines + 1] = line
        write_log()
    end
end

local function safe_call(fn, fallback)
    local ok, result = pcall(fn)
    if ok then return result end
    return fallback or 'error'
end

local function enumerate_worlds(app)
    local worlds = safe_call(function() return app and app.worlds and app.worlds() end)
    if type(worlds) ~= 'table' then worlds = {} end
    local main = safe_call(function() return app and app.main_world and app.main_world() end)
    local found = false
    for i = 1, #worlds do
        if worlds[i] == main then found = true; break end
    end
    if main and main ~= 'error' and not found then worlds[#worlds + 1] = main end
    return worlds, main
end

local function get_units(world_api, world, path)
    return safe_call(function()
        return world_api.units_by_resource(world, path)
    end)
end

local function unit_detail(engine, kind, world_index, unit)
    local unit_api, vector_api = engine.Unit, engine.Vector3
    local alive = safe_call(function() return unit_api.alive(unit) end)
    local xyz = 'unknown'
    if unit_api and unit_api.world_position and vector_api and vector_api.to_elements then
        for _, node in ipairs({1, 0}) do
            local ok, x, y, z = pcall(function()
                local position = unit_api.world_position(unit, node)
                return vector_api.to_elements(position)
            end)
            if ok and type(x) == 'number' and type(y) == 'number' and type(z) == 'number' then
                xyz = string.format('%.2f,%.2f,%.2f', x, y, z)
                break
            end
        end
    end
    return kind .. '@w' .. world_index .. ' id=' .. tostring(unit) ..
        ' alive=' .. tostring(alive) .. ' xyz=' .. xyz
end

local function scan_globals()
    local names = {}
    local needles = {'drone', 'target', 'armor', 'armour', 'entity', 'spawn',
        'equipment', 'inventory', 'mission', 'player'}
    for key in pairs(_G) do
        if type(key) == 'string' then
            local lower = key:lower()
            for _, needle in ipairs(needles) do
                if lower:find(needle, 1, true) then
                    names[#names + 1] = key
                    break
                end
            end
        end
    end
    table.sort(names)
    while #names > 80 do names[#names] = nil end
    add_line('candidate_globals=' .. table.concat(names, ','))
end

local function sample(now)
    local engine = rawget(_G, 'stingray')
    local app, world_api = engine and engine.Application, engine and engine.World
    if not (app and world_api and type(world_api.units_by_resource) == 'function') then
        add_line('runtime_api_unavailable')
        return
    end
    local worlds, main = enumerate_worlds(app)
    state.samples = state.samples + 1
    if not state.globals_scanned and now - state.started_at >= 30 then
        state.globals_scanned = true
        scan_globals()
    end
    local totals = {g50 = 0, g60 = 0, drone = 0}
    local parts = {}
    local detail_due = not state.last_detail_at or now - state.last_detail_at >= 5
    local details = {}
    for i = 1, #worlds do
        local world = worlds[i]
        local fields = {'w' .. i .. (world == main and '(main)' or '')}
        for _, kind in ipairs({'g50', 'g60', 'drone'}) do
            local units = get_units(world_api, world, paths[kind])
            local n = type(units) == 'table' and #units or tostring(units)
            fields[#fields + 1] = kind .. ':' .. tostring(n)
            if type(n) == 'number' then totals[kind] = totals[kind] + n end
            if detail_due and type(units) == 'table' then
                local limit = kind == 'g50' and 2 or 1
                for j = 1, math.min(#units, limit) do
                    details[#details + 1] = unit_detail(engine, kind, i, units[j])
                end
            end
        end
        parts[#parts + 1] = table.concat(fields, ',')
    end
    state.max_g50 = math.max(state.max_g50, totals.g50)
    state.max_g60 = math.max(state.max_g60, totals.g60)
    local available = {}
    for _, kind in ipairs({'g50', 'g60'}) do
        available[#available + 1] = kind .. ':' .. tostring(safe_call(function()
            return app.can_get('unit', paths[kind])
        end))
    end
    local observation = 'worlds=' .. tostring(#worlds) .. ' [' .. table.concat(parts, ';') ..
        '] can_get=[' .. table.concat(available, ',') .. ']'
    if observation ~= state.last_observation or not state.last_log_at or now - state.last_log_at >= 30 then
        add_line(string.format('t=%.2f sample=%d %s', now, state.samples, observation))
        state.last_observation, state.last_log_at = observation, now
    end
    if detail_due and #details > 0 then
        state.last_detail_at = now
        add_line(string.format('t=%.2f units=%s', now, table.concat(details, ';')))
    end
end

write_log()
local previous = rawget(_G, 'update')
if type(previous) == 'function' then
    local function pack(...) return {n = select('#', ...), ...} end
    local unpack_values = unpack or table.unpack
    update = function(...)
        local result = pack(previous(...))
        state.frames = state.frames + 1
        local app = stingray and stingray.Application
        local now = safe_call(function() return app.time_since_launch() end)
        if type(now) ~= 'number' then now = state.frames / 60 end
        if not state.started_at then state.started_at = now end
        if now - state.started_at <= 600 and
                (not state.last_sample_at or now - state.last_sample_at >= 0.1) then
            state.last_sample_at = now
            local ok, err = pcall(sample, now)
            if not ok then add_line('sample_error=' .. tostring(err)) end
        elseif not state.finished and now - state.started_at > 600 then
            state.finished = true
            add_line('done samples=' .. state.samples .. ' max_g50=' .. state.max_g50 ..
                ' max_g60=' .. state.max_g60)
        end
        return unpack_values(result, 1, result.n)
    end
else
    add_line('update_callback=unavailable')
end
