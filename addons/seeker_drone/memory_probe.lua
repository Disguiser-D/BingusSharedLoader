-- HD2-Addon: mods/tzy/seeker_drone_memory_probe
-- Read-only, bounded scan of this supported game.dll image for known resource hashes.
if rawget(_G, 'TzySeekerDroneMemoryProbe') then return end
local state = {lines = {'Seeker drone memory probe: loaded'}, started = false,
    done = false, cursor = nil, matches = {}, bytes = 0, failed = 0, tail = ''}
rawset(_G, 'TzySeekerDroneMemoryProbe', state)

local patterns = {
    mg_weapon = string.char(0x79,0x33,0xe1,0xbd,0xe3,0x21,0x26,0xa3),
    g50 = string.char(0x38,0x08,0x5e,0xc3,0x1e,0x8d,0x39,0x2d),
    g60 = string.char(0x62,0xbf,0x55,0x3e,0x93,0x5c,0x32,0x8e),
}

local function log(line)
    if #state.lines >= 120 then return end
    state.lines[#state.lines + 1] = line
    pcall(function()
        local loader = rawget(_G, 'CowboyBingusModLoader')
        local file = loader and loader.open_log and loader.open_log('SeekerDroneMemoryProbe.log')
        if file then file:write(table.concat(state.lines, '\n'), '\n'); file:close() end
    end)
end

local function u32(s, offset)
    local a,b,c,d = s:byte(offset+1,offset+4)
    if not d then return nil end
    return a+b*256+c*65536+d*16777216
end

local function init()
    local ffi = require('ffi')
    assert(ffi.os == 'Windows' and ffi.abi('64bit'), 'Windows x64 required')
    ffi.cdef [[
        void *GetModuleHandleA(const char *name);
        void *GetCurrentProcess(void);
        int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
        size_t VirtualQuery(const void *address, void *region, size_t size);
        typedef struct { void *base; void *allocation; uint32_t initial_protection;
            uint16_t partition; uint16_t padding; size_t size; uint32_t state;
            uint32_t protection; uint32_t kind; } TzySeekerMemoryRegion;
    ]]
    local kernel = ffi.load('kernel32')
    local module = kernel.GetModuleHandleA('game.dll')
    assert(module ~= nil, 'game.dll unavailable')
    local base = tonumber(ffi.cast('uintptr_t', module))
    local process = kernel.GetCurrentProcess()
    local function read(ptr, size)
        local data, count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
        if kernel.ReadProcessMemory(process, ffi.cast('void *', ptr), data, size, count) == 0
            or tonumber(count[0]) ~= size then return nil end
        return ffi.string(data, size)
    end
    local dos = assert(read(base, 64), 'PE DOS header unavailable')
    assert(dos:sub(1,2) == 'MZ', 'invalid DOS header')
    local pe = u32(dos, 0x3c)
    assert(pe and pe < 0x1000, 'invalid PE offset')
    local header = assert(read(base+pe, 0x60), 'PE header unavailable')
    assert(header:sub(1,4) == 'PE\0\0', 'invalid PE signature')
    local timestamp, image_size = u32(header,8), u32(header,24+56)
    assert(timestamp == 0x6ab3b43f and image_size == 0x04744000,
        'unsupported game.dll image')
    state.ffi, state.kernel, state.read = ffi, kernel, read
    state.base, state.cursor, state.finish = base, base, base+image_size
    state.started = true
    log(string.format('scan start timestamp=%08x image_size=%x', timestamp, image_size))
end

local function scan_chunk(data, ptr)
    local joined = state.tail .. data
    local start = ptr-#state.tail
    for kind, pattern in pairs(patterns) do
        local at = 1
        while true do
            local found = joined:find(pattern, at, true)
            if not found then break end
            local list = state.matches[kind] or {}
            state.matches[kind] = list
            if #list < 24 then list[#list+1] = string.format('0x%x', start+found-1-state.base) end
            at = found+1
        end
    end
    state.tail = joined:sub(math.max(1,#joined-6))
end

local function step()
    if state.done then return end
    if not state.started then init() end
    local ffi, kernel = state.ffi, state.kernel
    local budget = 4*1024*1024
    while state.cursor < state.finish and budget > 0 do
        local region = ffi.new('TzySeekerMemoryRegion[1]')
        local size = ffi.sizeof(region[0])
        if kernel.VirtualQuery(ffi.cast('void *',state.cursor),
            ffi.cast('void *',region),size) ~= size then error('VirtualQuery failed') end
        local item = region[0]
        local region_end = tonumber(ffi.cast('uintptr_t', item.base))+tonumber(item.size)
        assert(region_end > state.cursor, 'invalid memory region')
        local chunk = math.min(region_end-state.cursor, state.finish-state.cursor,
            budget, 1024*1024)
        local readable = item.state == 0x1000 and
            bit.band(item.protection,0x01) == 0 and
            bit.band(item.protection,0x100) == 0
        if readable then
            local data = state.read(state.cursor,chunk)
            if data then
                scan_chunk(data,state.cursor)
                state.bytes = state.bytes+chunk
            else
                state.failed = state.failed+1
                state.tail = ''
            end
        else
            state.tail = ''
        end
        state.cursor = state.cursor+chunk
        budget = budget-chunk
    end
    if state.cursor >= state.finish then
        state.done = true
        log('scan complete bytes=' .. state.bytes .. ' failed_reads=' .. state.failed)
        for _, kind in ipairs({'mg_weapon','g50','g60'}) do
            local matches = state.matches[kind] or {}
            log(kind .. ' matches=' .. #matches .. ' rvas=' .. table.concat(matches,','))
        end
    end
end

local previous = rawget(_G,'update')
if type(previous) == 'function' then
    update = function(...)
        if not state.done then
            local ok, reason = pcall(step)
            if not ok then state.done = true; log('scan error=' .. tostring(reason)) end
        end
        return previous(...)
    end
else
    log('update callback unavailable')
end
