# Seeker drone backend: verified boundary

This note records what the new gameplay coordination API can and cannot do
for a proposed G-50/G-60 drone. It is a development note, not an installable
drone mod.

## Decision gate

The complete drone is **no-go with the currently verified interfaces**.
The loader's capability broker can coordinate a backend, but no provider yet
creates a native active seeker or returns a game-side heavy-target boolean.
Further Lua API enumeration or scans for byte-identical raw component records
do not address either missing operation.

The proposed **read-only API-table gate** has been completed. In the supported
live build, `game.dll` `setup_game` (RVA `0x4EE160`) calls a helper at RVA
`0x4EDA90` with `get_engine_api`; the helper requests ID 31 and stores its
return value at RVA `0x3326308`. This slot and two successive table pointers
are readable, but the function at the SDK-predicted `WorldCApi.spawn_unit`
slot has an incompatible calling pattern: it uses only the first two input
registers, substitutes a constant resource ID, and forwards to an internal
wrapper. The adjacent slots also do not establish the SDK `WorldCApi` layout.
**Do not call or label this function as `spawn_unit`.** ID 31 in this game
build cannot be interpreted from the public sample SDK alone. The on-disk
DLL is packed; these findings come from read-only live memory and are valid
only for the checked game build. They do not capture a normal throw's call
stack or identify a native seeker constructor.

A later menu-only probe used [LuaJIT `jit.util.funcinfo`](https://github.com/LuaJIT/LuaJIT/blob/v2.1/src/lib_jit.c) to obtain the actual
`stingray.World.spawn_unit` C-function address without invoking it. On the
checked build it was in `helldivers2.exe` at RVA `0x3EACF0`, a small thunk to
RVA `0x3EAA90`. Read-only code extraction followed its call chain through
RVA `0x1A7E50` and `0x1A7FC0` to the engine's unit allocation path at RVA
`0x1A3930`. The chain parses the Lua world and resource arguments and returns
a Unit handle. This is a **verified engine Unit path**, not a Helldivers 2
throwable gameplay constructor: the earlier one-shot test through this Lua
function created an inert G-50 model. No normal player's throw was traced to
any of these functions. The development probe is
`addons/seeker_drone/funcinfo_probe.lua`; it only records function addresses.

An initial resource-override check with
[Filediver v0.7.55](https://github.com/xypwn/filediver/releases/tag/v0.7.55)
found no `dl_bin` entry in the game **archives**. A complete read-only dump of
the loaded `game.dll` corrected the scope of that result: its function at RVA
`0xFDB440` explicitly requests `generated_entities.dl_bin`, and the current
installation has this as a loose file at `data/game/generated_entities.dl_bin`.
The file is 46,612,636 bytes and its current SHA-256 is
`7DF1A07E90C61E0B8398ECBC5C088074655900943BF1CD7E09F69BCCEDEC4A2A`.
Its bytes are high-entropy and have no plaintext `DLDL` header. Filediver's
embedded decoded snapshot is 46,612,588 bytes with a `DLDL` header; the
verified current-build projectile-weapon subtable matches that snapshot.
The game's own data loader hashes the **decoded full file** with MurmurHash64A
seed `0xDEADBEEFABAD1DEA`; its expected result is
`0xEBFD607F348CFC7F`. The Filediver decoded snapshot produces exactly that
result, establishing whole-file compatibility with the current game's
expected content hash. This is not a byte-for-byte SHA-256 comparison with
the encrypted installed file. The extra 48 bytes and differing encoding mean
a modified plaintext snapshot cannot simply be substituted for the installed
file. The loader's archive writer emits Lua resources only. No verified
load-time encoding or safe overlay path exists yet; the installed file has not
been edited.
The live image used for this offline analysis was 74,727,424 bytes, with no
unreadable pages, and was kept only in ignored local development artifacts.

The loader at RVA `0xFDB440` calls its resource-read callback, verifies the
decoded buffer at RVA `0x1269820`, then parses its DL structure. A mismatch
enters an error-report callback before parsing continues. The callback's
effect has not been verified, so bypassing or ignoring the integrity result
would be an unsupported gameplay change. The offline
`tools/plan_projectile_entity.py --decoded-full` mode checks the original
full-file SHA-256 and game-side content hash, then reports the exact G-50
candidate field offset and resulting hashes without writing modified data.

The complete image also allowed a focused heavy-target search. References to
`tag_spot_enemy_gen_character_heavy` and
`tag_spot_enemy_anyfac_patrol_heavy` are in a hash-to-string lookup, not a
function accepting a target. The `TargetingComponent` name leads to component
storage growth/copy code; `BugArmored` is among spawn-configuration labels.
No checked candidate both accepts an actual target and returns a heavy-target
boolean. This does not establish that such logic is absent, but G-60 must
remain disabled until that exact gate is demonstrated. Unit-size enums and
armor-penetration fields do not satisfy the required boolean result.

The next useful experiment requires a concrete native boundary: capture one
normal player's G-50 throw, filtered by resource hash
`0x2d398d1ec35e0838`, and identify the game-side caller that creates the
gameplay entity, initializes its components, and sets ownership. A versioned
function address alone is insufficient without a verified calling convention,
object/parameter sources, and thread or network constraints. Separately,
the G-60 gate needs a native boolean result tied to an actual target, shown
to return `true` for a heavy target and not `true` for a non-heavy target.
An armor number, size enum, or a hand-written threshold is not a substitute
for the user's required explicit game-side result.

On the supported Helldivers 2 build, a read-only Lua addon observed both
`content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone`
and `content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone`
become available when equipped in a mission. `World.units_by_resource` saw
instances of both, and also found the machine-gun Guard Dog at
`content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg`. Its world
position could be read. A separate one-shot experiment called
`World.spawn_unit` once for G-50 two meters above that drone. The call returned
a live unit, but its position remained unchanged for 20 seconds; the test
addon then destroyed its own unit. That generic engine call did not start the
game's native seeker behavior. No G-60 was generated by the experiment.

Unit existence also does not establish whether a seeker still occupies an
airborne slot. Native G-50 instances remained `Unit.alive == true` after their
positions stopped changing. A drone needs an authoritative active-flight or
completion signal, not just resource counts or `Unit.alive`.
Two native G-50 throws were observed transitioning through main animation
states 0, 1, 3, then 4 (`undeploy`) after about 30 seconds. Both still existed
after entering state 4; this is a candidate activity signal, not yet validated
for G-60 or every impact path.

The requested design requires independent magazine and backpack reserves
(G-50: 200/1000, G-60: 100/500), airborne limits (2/1), docking refill,
supply refill, and generation of G-60 only after a target exists and the
game's heavy-target check explicitly returns `true`. Its native seeker logic
should take over after a proper game-entity spawn. An independent stratagem is
preferred; replacing the machine-gun Guard Dog stratagem is a fallback.

The loader's `gameplay` API coordinates independently supplied providers. It
does **not** provide any of these game-native functions. Before a drone addon
can register a working backend, the following must be found and validated:

1. A game-entity throwable creation/activation call that starts native seeker
   behavior, associates the owner, and behaves correctly in multiplayer.
2. A game-side target query and heavy classification that can explicitly
   return `true` before G-60 creation.
3. An active-flight or terminal event for each seeker instance, plus local
   player ownership and drone/backpack/supply events.
4. A supported way to register a new stratagem and its backpack/loadout data;
   otherwise validate the authorized Guard Dog replacement route.

Do not register `World.spawn_unit` as a provider named
`game.entity.spawn_throwable`: the live test showed that would advertise a
capability the game does not actually have.

Follow-up live checks also found `stingray.EntityManager.spawn`, but the
equipped G-50's `Application.can_get('entity', ...)` returned `false`; the
guarded probe therefore did not call that function. The available G-50 unit
resource is not a spawnable `.entity` resource through this interface.
`EntityManager.create` only creates a blank entity. In a later read-only test,
`Network.game_session()` returned a session while native G-50 was present,
but `GameSession.unit_synchronizer(session)` returned `nil`, so the generic
`UnitSynchronizer` path did not expose this seeker either.

The native `ProjectileWeaponComponentData` table offers a different lead:
its `projectile_entity` field instructs a firing weapon to spawn an entity.
The machine-gun Guard Dog weapon currently has this field set to zero.
A read-only in-process check found an exact SHA-256 match between the current
game's complete 176,224-byte projectile-weapon component data and Filediver's
embedded snapshot. This validates the table contents for this game build, but
does not identify the active writable record or show that replacing the field
would initialize the G-50 seeker.

A later controlled runtime experiment temporarily replaced that field with
the G-50 resource hash in every exact-hash table copy found while the Guard Dog
was firing. It restored every field after at most one second and verified the
original table hashes again. The loaded read-only G-50 observer saw no new
G-50 units. This raw-table replacement has therefore not established a usable
spawn backend. No G-60 was generated.

A process-wide read-only search for the Guard Dog weapon record's unique
32-byte prefix found only original DL-table copies: five at the main menu and
four while the equipped Guard Dog fired in a mission. It scanned about 4.3 GB
and 5.8 GB of private writable memory respectively. No separate byte-identical
runtime component was found. The game may use a transformed component layout,
so this does not identify the native creation function.

The current `game.dll` export `get_plugin_api` was inspected in live process
memory without invoking it. It returns a standard Stingray `PluginApi` table
only for API ID 0 and returns null for other IDs. The table contains engine
lifecycle callbacks such as `setup_game` and `units_spawned`; it is not a
queryable Helldivers 2 throwable-creation API. The interpretation uses the
[Stingray engine plugin contract](https://help.autodesk.com/cloudhelp/ENU/Stingray-SDK-Help/sdk_help/extend_engine.html)
and [SDK header](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/master/stingray_sdk/engine_plugin_api/plugin_api.h).
