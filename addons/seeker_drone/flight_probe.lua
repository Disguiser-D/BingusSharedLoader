-- HD2-Addon: mods/tzy/seeker_drone_flight_probe
-- Read-only G-50 animation-state observation. It never spawns a unit.
if rawget(_G, 'TzySeekerDroneFlightProbe') then return end
local state = {lines = {'Seeker drone flight-state probe: loaded'},
    started = nil, last_sample = nil, next_id = 0, observed = {},
    last_detail = nil, samples = 0}
rawset(_G, 'TzySeekerDroneFlightProbe', state)

local G50 = 'content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone'

local function log(line)
    if #state.lines >= 600 then return end
    state.lines[#state.lines+1] = line
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneFlightProbe.log')
        if file then file:write(table.concat(state.lines, '\n'), '\n'); file:close() end
    end)
end

local function pack(...) return {n=select('#',...), ...} end

local function animation_text(unit_api, unit)
    local ok, value = pcall(function()
        local result = pack(unit_api.animation_get_state(unit))
        local parts = {}
        for i=1,result.n do parts[i] = tostring(result[i]) end
        return table.concat(parts,'/')
    end)
    return ok and value or 'error:' .. tostring(value)
end

local function position_text(engine, unit)
    local ok, x, y, z = pcall(function()
        local position = engine.Unit.world_position(unit,1)
        return engine.Vector3.to_elements(position)
    end)
    if ok and type(x)=='number' and type(y)=='number' and type(z)=='number' then
        return string.format('%.2f,%.2f,%.2f',x,y,z)
    end
    return 'unavailable'
end

local function sample(engine, now)
    local app, world_api, unit_api = engine.Application,engine.World,engine.Unit
    if not (app and world_api and unit_api and app.worlds and
            world_api.units_by_resource and unit_api.animation_get_state) then
        log('required API unavailable')
        return
    end
    local worlds = app.worlds()
    if type(worlds)~='table' then return end
    state.samples = state.samples+1
    local detail = not state.last_detail or now-state.last_detail>=2
    if detail then state.last_detail=now end
    local live = {}
    for wi=1,#worlds do
        local ok, units = pcall(world_api.units_by_resource,worlds[wi],G50)
        if ok and type(units)=='table' then
            for _,unit in ipairs(units) do
                live[unit]=true
                local item=state.observed[unit]
                if not item then
                    state.next_id=state.next_id+1
                    item={id=state.next_id,last_state=nil}
                    state.observed[unit]=item
                    log(string.format('t=%.2f unit=%d first_seen world=%d',now,item.id,wi))
                end
                local alive_ok,alive=pcall(unit_api.alive,unit)
                local has_ok,has_machine=pcall(unit_api.has_animation_state_machine,unit)
                local animation=(alive_ok and alive and has_ok and has_machine)
                    and animation_text(unit_api,unit) or 'unavailable'
                if animation~=item.last_state or detail then
                    item.last_state=animation
                    log(string.format('t=%.2f unit=%d world=%d alive=%s machine=%s state=%s xyz=%s',
                        now,item.id,wi,tostring(alive_ok and alive),
                        tostring(has_ok and has_machine),animation,
                        position_text(engine,unit)))
                end
            end
        end
    end
    for unit,item in pairs(state.observed) do
        if not live[unit] and not item.absent then
            item.absent=true
            log(string.format('t=%.2f unit=%d absent_from_worlds',now,item.id))
        elseif live[unit] then
            item.absent=false
        end
    end
end

local previous=rawget(_G,'update')
if type(previous)=='function' then
    update=function(...)
        local engine=rawget(_G,'stingray')
        local app=engine and engine.Application
        local ok,now=pcall(function() return app.time_since_launch() end)
        if ok and type(now)=='number' then
            state.started=state.started or now
            if now-state.started<180 and
                (not state.last_sample or now-state.last_sample>=0.1) then
                state.last_sample=now
                local sampled,reason=pcall(sample,engine,now)
                if not sampled then log('sample_error='..tostring(reason)) end
            end
        end
        return previous(...)
    end
else
    log('update callback unavailable')
end
