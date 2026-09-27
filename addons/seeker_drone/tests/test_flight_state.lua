local module_path = assert(arg[1])
local FlightState = assert(loadfile(module_path))()
local unit = {}
local main_state, alive, machine = 0, true, true
local api = {
    alive = function(actual) assert(actual == unit); return alive end,
    has_animation_state_machine = function(actual)
        assert(actual == unit); return machine
    end,
    animation_get_state = function(actual)
        assert(actual == unit); return main_state, 1, 1
    end,
}
for state = 0, 3 do
    main_state = state
    assert(FlightState.still_active(api, unit) == true)
end
main_state = 4
assert(FlightState.still_active(api, unit) == false)
main_state = 5
assert(FlightState.still_active(api, unit) == nil)
machine = false
assert(FlightState.still_active(api, unit) == nil)
machine = true
alive = false
assert(FlightState.still_active(api, unit) == false)
assert(FlightState.still_active({}, unit) == nil)
assert(FlightState.still_active(api, nil) == nil)
print('seeker drone flight-state scenarios passed')
