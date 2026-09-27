local source=assert(arg[1])
local writes,spawned={},0
local clock,animation,visible=0,0,false
local unit={}
local env=setmetatable({}, {__index=_G})
env._G=env
env.CowboyBingusModLoader={open_log=function(name)
    assert(name=='SeekerDroneFlightProbe.log')
    return {write=function(_,message) writes[#writes+1]=message end,
            close=function() end}
end}
env.stingray={
    Application={worlds=function() return {'mission'} end,
                 time_since_launch=function() return clock end},
    World={units_by_resource=function(world,path)
        assert(world=='mission' and path:find('self_destruct_drone',1,true))
        return visible and {unit} or {}
    end,
    spawn_unit=function() spawned=spawned+1; error('must not spawn') end},
    Unit={alive=function() return true end,
          has_animation_state_machine=function() return true end,
          animation_get_state=function() return animation,1,nil end,
          world_position=function() return {1,2,3} end},
    Vector3={to_elements=function(p) return p[1],p[2],p[3] end},
}
env.update=function(a,b) assert(a==8 and b==nil); return 4,nil end
assert(setfenv(assert(loadfile(source)),env)()==nil)
local function tick(t)
    clock=t
    local function pack(...) return {n=select('#',...),...} end
    local result=pack(env.update(8,nil))
    assert(result.n==2 and result[1]==4 and result[2]==nil)
end
tick(0)
visible=true
tick(0.2)
animation=1
tick(0.4)
visible=false
tick(0.6)
assert(spawned==0)
local log=writes[#writes]
assert(log:find('first_seen',1,true))
assert(log:find('state=0/1/nil',1,true))
assert(log:find('state=1/1/nil',1,true))
assert(log:find('absent_from_worlds',1,true))
print('seeker drone flight-state probe scenarios passed')
