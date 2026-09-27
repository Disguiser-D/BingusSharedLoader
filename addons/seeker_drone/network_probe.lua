-- HD2-Addon: mods/tzy/seeker_drone_network_probe
-- Read-only check of native G-50/G-60 network associations.
if rawget(_G, 'TzySeekerDroneNetworkProbe') then return end
local state={lines={'Seeker drone network probe: loaded'},seen={},started=nil,
    last_sample=nil,done=false}
rawset(_G,'TzySeekerDroneNetworkProbe',state)

local RESOURCES={
    g50='content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone',
    g60='content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone',
}
local function log(line)
    if #state.lines>=100 then return end
    state.lines[#state.lines+1]=line
    pcall(function()
        local loader=rawget(_G,'CowboyBingusModLoader')
        local file=loader and loader.open_log and loader.open_log('SeekerDroneNetworkProbe.log')
        if file then file:write(table.concat(state.lines,'\n'),'\n');file:close() end
    end)
end

local function call(fn,...)
    if type(fn)~='function' then return 'unavailable',nil end
    local ok,value=pcall(fn,...)
    if not ok then return 'error:'..tostring(value),nil end
    return 'ok',value
end

local function scan(engine,now)
    local network=engine.Network
    local network_status,session=call(network and network.game_session)
    local sync_status,sync='unavailable',nil
    if session then
        sync_status,sync=call(engine.GameSession and engine.GameSession.unit_synchronizer,session)
    end
    local session_description='network='..tostring(type(network))..' session='..network_status..
            ':'..tostring(type(session))..' synchronizer='..sync_status..
            ':'..tostring(type(sync))
    if state.session_description~=session_description then
        state.session_description=session_description
        log(session_description)
    end
    local worlds=engine.Application and engine.Application.worlds and engine.Application.worlds()
    if type(worlds)~='table' or not engine.World or not engine.World.units_by_resource then return end
    for wi=1,#worlds do
        for kind,resource in pairs(RESOURCES) do
            local ok,units=pcall(engine.World.units_by_resource,worlds[wi],resource)
            if ok and type(units)=='table' then
                for _,unit in ipairs(units) do
                    local id_status,id=call(engine.Unit and engine.Unit.id,unit)
                    local mapping_status,object_id='unavailable',nil
                    if sync then
                        mapping_status,object_id=call(engine.UnitSynchronizer and
                            engine.UnitSynchronizer.unit_to_game_object_id,sync,unit)
                    end
                    local exists_status,exists='unavailable',nil
                    if session and type(object_id)=='number' then
                        exists_status,exists=call(engine.GameSession and
                            engine.GameSession.game_object_exists,session,object_id)
                    end
                    local description=kind..' world='..wi..' unit_id='..id_status..':'..
                        tostring(id)..' mapping='..mapping_status..':'..tostring(object_id)..
                        ' object_exists='..exists_status..':'..tostring(exists)
                    if state.seen[unit]~=description then
                        state.seen[unit]=description
                        log(string.format('t=%.2f %s',now,description))
                    end
                end
            end
        end
    end
end

local previous=rawget(_G,'update')
if type(previous)=='function' then
    update=function(...)
        if not state.done then
            local engine=rawget(_G,'stingray')
            local app=engine and engine.Application
            local ok,now=pcall(function() return app.time_since_launch() end)
            if ok and type(now)=='number' then
                state.started=state.started or now
                if now-state.started>600 then state.done=true;log('scan complete')
                elseif not state.last_sample or now-state.last_sample>=0.2 then
                    state.last_sample=now
                    local scanned,reason=pcall(scan,engine,now)
                    if not scanned then log('scan_error='..tostring(reason)) end
                end
            end
        end
        return previous(...)
    end
else log('update callback unavailable') end
