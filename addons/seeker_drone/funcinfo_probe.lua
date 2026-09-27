-- Read-only LuaJIT C-function address inventory. Never invokes the functions.
-- HD2-Addon: mods/tzy/seeker_drone_funcinfo_probe
if rawget(_G, 'TzySeekerDroneFuncinfoProbe') then return end
rawset(_G, 'TzySeekerDroneFuncinfoProbe', true)

local lines = {'Seeker drone funcinfo probe: loaded'}
local finished = false
local attempts = 0

local function log(value)
    lines[#lines + 1] = tostring(value)
end

local function save()
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneFuncinfoProbe.log')
        if not file then return end
        file:write(table.concat(lines, '\n'), '\n')
        file:close()
    end)
end

local function inspect(util, name, fn)
    if type(fn) ~= 'function' then
        log(name .. '=unavailable:' .. type(fn))
        return
    end
    local ok, info = pcall(util.funcinfo, fn)
    if not ok then
        log(name .. '=funcinfo_error:' .. tostring(info))
    elseif type(info) ~= 'table' or info.addr == nil then
        log(name .. '=no_c_address')
    else
        log(name .. '=addr:' .. tostring(info.addr) .. ',addr_type:' .. type(info.addr))
    end
end

local function scan()
    if finished then return end
    attempts = attempts + 1
    local engine = rawget(_G, 'stingray')
    local world = engine and engine.World
    if not world and attempts < 120 then return end
    finished = true
    local jit_api = rawget(_G, 'jit')
    log('jit=' .. type(jit_api) .. ',version:' .. tostring(jit_api and jit_api.version))
    local ok, util = pcall(require, 'jit.util')
    if not ok or type(util) ~= 'table' or type(util.funcinfo) ~= 'function' then
        log('jit.util=unavailable:' .. tostring(util))
        save()
        return
    end
    inspect(util, 'World.spawn_unit', world and world.spawn_unit)
    inspect(util, 'World.units_by_resource', world and world.units_by_resource)
    inspect(util, 'Unit.alive', engine and engine.Unit and engine.Unit.alive)
    inspect(util, 'Application.main_world',
        engine and engine.Application and engine.Application.main_world)
    save()
end

local previous = rawget(_G, 'update')
if type(previous) == 'function' then
    update = function(...)
        local ok, reason = pcall(scan)
        if not ok then
            finished = true
            log('scan_error=' .. tostring(reason))
            save()
        end
        return previous(...)
    end
else
    log('update callback unavailable')
    save()
end
