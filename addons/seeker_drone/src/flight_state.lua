-- Candidate native seeker activity check based on the extracted state machines.
-- The G-50 undeploy state was observed in-game; G-60 still needs live validation.
local FlightState = {}

-- Returns true while the native seeker is in a known active state, false once
-- it reaches undeploy or is no longer alive, and nil if the game state is
-- unavailable. Inventory:reconcile keeps a slot occupied on nil.
function FlightState.still_active(unit_api, unit)
    if not unit_api or unit == nil then return nil end
    if type(unit_api.alive) ~= 'function' or
        type(unit_api.has_animation_state_machine) ~= 'function' or
        type(unit_api.animation_get_state) ~= 'function' then return nil end
    local alive_ok, alive = pcall(unit_api.alive, unit)
    if not alive_ok or type(alive) ~= 'boolean' then return nil end
    if not alive then return false end
    local machine_ok, has_machine = pcall(unit_api.has_animation_state_machine, unit)
    if not machine_ok or has_machine ~= true then return nil end
    local state_ok, main_state = pcall(unit_api.animation_get_state, unit)
    if not state_ok or type(main_state) ~= 'number' then return nil end
    if main_state == 4 then return false end -- undeploy
    if main_state >= 0 and main_state <= 3 then return true end
    return nil
end

return FlightState
