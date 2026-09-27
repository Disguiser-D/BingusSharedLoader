local source=assert(arg[1])
local writes={}
local clock=0
local unit={}
local env=setmetatable({}, {__index=_G})
env._G=env
env.CowboyBingusModLoader={open_log=function(name)
    assert(name=='SeekerDroneNetworkProbe.log')
    return {write=function(_,message) writes[#writes+1]=message end,
            close=function() end}
end}
env.stingray={
    Application={time_since_launch=function() return clock end,
                 worlds=function() return {'mission'} end},
    Network={game_session=function() return 'session' end},
    GameSession={unit_synchronizer=function(session)
        assert(session=='session');return 'sync'
    end,game_object_exists=function(session,id)
        assert(session=='session' and id==42);return true
    end},
    UnitSynchronizer={unit_to_game_object_id=function(sync,actual)
        assert(sync=='sync' and actual==unit);return 42
    end},
    World={units_by_resource=function(world,path)
        assert(world=='mission')
        return path:find('/self_destruct_drone/',1,true) and {unit} or {}
    end,spawn_unit=function() error('must not spawn') end},
    Unit={id=function(actual) assert(actual==unit);return 7 end},
}
env.update=function() return 3,nil end
assert(setfenv(assert(loadfile(source)),env)()==nil)
local function tick(t)
    clock=t
    local function pack(...) return {n=select('#',...),...} end
    local result=pack(env.update())
    assert(result.n==2 and result[1]==3 and result[2]==nil)
end
tick(0)
tick(0.3)
assert(#writes>0)
local log=writes[#writes]
assert(log:find('session=ok:string',1,true))
assert(log:find('mapping=ok:42',1,true))
assert(log:find('object_exists=ok:true',1,true))
print('seeker drone network probe scenarios passed')
