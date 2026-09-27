-- Read-only API discovery. It never creates units or changes gameplay data.
-- HD2-Addon: mods/tzy/seeker_drone_api_probe
if rawget(_G, 'TzySeekerDroneApiProbe') then return end
rawset(_G, 'TzySeekerDroneApiProbe', true)
local lines = {'Seeker drone API probe: loaded'}
local seen = {}
local started = false
local written = false
local key_limit = 180

local function log(line)
    if #lines < 400 then lines[#lines + 1] = line end
end

local function save()
    if written then return end
    written = true
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneApiProbe.log')
        if not file then return end
        file:write(table.concat(lines, '\n'), '\n')
        file:close()
    end)
end

local function matches(name)
    local lower = name:lower()
    for _, word in ipairs({'target', 'armor', 'armour', 'health', 'damage',
        'projectile', 'throw', 'weapon', 'enemy', 'faction', 'agent', 'unit',
        'entity', 'spawn', 'equipment', 'player', 'drone', 'game'}) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

local function keys_of(path, value, filter)
    if type(value) ~= 'table' or seen[value] then return end
    seen[value] = true
    local keys = {}
    local ok = pcall(function()
        for key, child in pairs(value) do
            if type(key) == 'string' and (not filter or matches(key)) then
                keys[#keys + 1] = key .. ':' .. type(child)
            end
        end
    end)
    if not ok then log(path .. '=uninspectable'); return end
    table.sort(keys)
    local total = #keys
    while #keys > key_limit do keys[#keys] = nil end
    log(path .. ' keys=' .. tostring(total) .. ' [' .. table.concat(keys, ',') .. ']')
end

local function scan()
    if started then return end
    started = true
    local engine = rawget(_G, 'stingray')
    keys_of('stingray', engine, true)
    keys_of('stingray.Unit', engine and engine.Unit, false)
    keys_of('stingray.World', engine and engine.World, true)
    keys_of('stingray.Application', engine and engine.Application, true)
    if type(engine) == 'table' then
        local groups = {}
        for name, value in pairs(engine) do
            if type(name) == 'string' and type(value) == 'table' and matches(name)
                and name ~= 'Unit' and name ~= 'World' and name ~= 'Application' then
                groups[#groups + 1] = name
            end
        end
        table.sort(groups)
        for i = 1, math.min(#groups, 45) do
            local name = groups[i]
            keys_of('stingray.' .. name, engine[name], false)
        end
    end
    local globals = {}
    for name, value in pairs(_G) do
        if type(name) == 'string' and type(value) == 'table' and matches(name)
            and name ~= 'stingray' then
            globals[#globals + 1] = name
        end
    end
    table.sort(globals)
    for i = 1, math.min(#globals, 30) do
        keys_of('_G.' .. globals[i], rawget(_G, globals[i]), true)
    end
    save()
end

local previous = rawget(_G, 'update')
if type(previous) == 'function' then
    update = function(...)
        if not started then
            local ok, reason = pcall(scan)
            if not ok then log('scan_error=' .. tostring(reason)); save() end
        end
        return previous(...)
    end
else
    log('update callback unavailable')
    save()
end
