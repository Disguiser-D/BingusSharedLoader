-- Pure inventory and in-flight bookkeeping for the proposed seeker drone.
-- This module does not create game entities or hook game callbacks.
local Inventory = {}
Inventory.__index = Inventory

local TYPES = {
    g50 = {drone = 200, backpack = 1000, airborne = 2},
    g60 = {drone = 100, backpack = 500, airborne = 1},
}

local function kind_spec(kind)
    local spec = TYPES[kind]
    assert(spec, 'unknown seeker type: ' .. tostring(kind))
    return spec
end

function Inventory.new()
    local self = setmetatable({
        drone = {}, backpack = {}, airborne = {}, pending = {}, entities = {},
        next_token = 0, docked = false,
    }, Inventory)
    for kind, spec in pairs(TYPES) do
        self.drone[kind] = spec.drone
        self.backpack[kind] = spec.backpack
        self.airborne[kind] = 0
    end
    return self
end

function Inventory:can_launch(kind)
    local spec = kind_spec(kind)
    if self.docked or self.drone[kind] == 0 then return false end
    local reserved = 0
    for _, pending_kind in pairs(self.pending) do
        if pending_kind == kind then reserved = reserved + 1 end
    end
    return self.airborne[kind] + reserved < spec.airborne
        and reserved < self.drone[kind]
end

-- Reserve the slot before asking the game to spawn an entity. A failed spawn
-- must be canceled, so it never spends ammunition or occupies an air slot.
function Inventory:begin_launch(kind)
    if not self:can_launch(kind) then return nil end
    self.next_token = self.next_token + 1
    self.pending[self.next_token] = kind
    return self.next_token
end

function Inventory:cancel_launch(token)
    if not self.pending[token] then return false end
    self.pending[token] = nil
    return true
end

function Inventory:finish_launch(token, entity_id)
    local kind = self.pending[token]
    if not kind or entity_id == nil or type(entity_id) == 'boolean'
        or self.entities[entity_id] then return false end
    self.pending[token] = nil
    self.entities[entity_id] = kind
    self.airborne[kind] = self.airborne[kind] + 1
    self.drone[kind] = self.drone[kind] - 1
    return true
end

-- Called for impact, destruction, expiration, or any other authoritative
-- disappearance event. Duplicate notifications cannot free two slots.
function Inventory:entity_gone(entity_id)
    local kind = self.entities[entity_id]
    if not kind then return false end
    self.entities[entity_id] = nil
    self.airborne[kind] = self.airborne[kind] - 1
    return true
end

-- The game adapter must report whether the seeker is still airborne. Unit.alive
-- alone is insufficient: spent native seeker units can remain in the world.
-- Unknown/error results keep the slot occupied rather than spawning duplicates.
function Inventory:reconcile(still_airborne)
    assert(type(still_airborne) == 'function', 'airborne callback required')
    local removed = 0
    for entity_id in pairs(self.entities) do
        local ok, airborne = pcall(still_airborne, entity_id)
        if ok and airborne == false and self:entity_gone(entity_id) then
            removed = removed + 1
        end
    end
    return removed
end

-- The game adapter supplies spawn(kind), returning the spawned entity's stable
-- ID or nil. Both types fill vacant slots; native seeker behavior chooses
-- targets after a proper game-entity spawn.
function Inventory:maintain(spawn)
    assert(type(spawn) == 'function', 'spawn callback required')
    if self.docked or self:needs_dock() then return {g50 = 0, g60 = 0} end
    local launched = {g50 = 0, g60 = 0}
    for _, kind in ipairs({'g50', 'g60'}) do
        while self:can_launch(kind) do
            local token = self:begin_launch(kind)
            local ok, entity_id = pcall(spawn, kind)
            if not ok or entity_id == nil or not self:finish_launch(token, entity_id) then
                self:cancel_launch(token)
                break
            end
            launched[kind] = launched[kind] + 1
        end
    end
    return launched
end

function Inventory:needs_dock()
    for kind in pairs(TYPES) do
        if self.drone[kind] == 0 and self.backpack[kind] > 0 then return true end
    end
    return false
end

function Inventory:begin_dock()
    if not self:needs_dock() or self.docked then return false end
    -- The game adapter must first cancel any in-progress entity spawn.
    if next(self.pending) then return false end
    self.docked = true
    return true
end

-- Call only once the real drone has returned to its backpack.
function Inventory:finish_dock()
    if not self.docked then return false end
    for kind, spec in pairs(TYPES) do
        local transfer = math.min(spec.drone - self.drone[kind], self.backpack[kind])
        self.drone[kind] = self.drone[kind] + transfer
        self.backpack[kind] = self.backpack[kind] - transfer
    end
    self.docked = false
    return true
end

-- A supply pickup replenishes the backpack reserve. It does not create
-- in-flight seekers or silently refill the drone before it docks.
function Inventory:resupply()
    for kind, spec in pairs(TYPES) do self.backpack[kind] = spec.backpack end
end

function Inventory:snapshot()
    return {
        drone = {g50 = self.drone.g50, g60 = self.drone.g60},
        backpack = {g50 = self.backpack.g50, g60 = self.backpack.g60},
        airborne = {g50 = self.airborne.g50, g60 = self.airborne.g60},
        docked = self.docked,
    }
end

return Inventory
