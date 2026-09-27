# Seeker drone backend: verified boundary

This note records what the new gameplay coordination API can and cannot do
for a proposed G-50/G-60 drone. It is a development note, not an installable
drone mod.

## Decision gate

The complete drone is **no-go with the currently verified interfaces**.
The loader's capability broker can coordinate a backend, but no provider yet
creates a native active seeker. The current design lets G-60 use its own
post-spawn targeting logic; it no longer requires a pre-spawn heavy-target
boolean.
Further Lua API enumeration or scans for byte-identical raw component records
do not address the missing native spawn operation.

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
Its bytes are high-entropy and have no plaintext DL magic `0x444C444C`.
Filediver's embedded decoded snapshot is 46,612,588 bytes with that magic; the
verified current-build projectile-weapon subtable matches that snapshot.
The game's own data loader hashes the **decoded full file** with MurmurHash64A
seed `0xDEADBEEFABAD1DEA`; its expected result is
`0xEBFD607F348CFC7F`. The Filediver decoded snapshot produces exactly that
result, establishing whole-file compatibility with the current game's
expected content hash. This is not a byte-for-byte SHA-256 comparison with
the encrypted installed file. The extra 48 bytes are now explained: the
engine resource callback at RVA `0xA85F0` passes the installed file to a
[libsodium sealed-box decoder](https://github.com/jedisct1/libsodium/blob/master/src/libsodium/crypto_box/crypto_box_seal.c)
at RVA `0x91EE30`. Its format adds a 32-byte ephemeral public key and 16-byte
authentication overhead. Offline verification decoded three installed
files (entities, projectile settings, damage settings) and matched each
decoded result byte-for-byte to the corresponding Filediver snapshot.
Re-encrypting the unchanged snapshot also passed an offline sealed-box
round-trip. No game data or key material is included in this repository.
The loader's archive writer emits Lua resources only; the installed data file
has not been edited.
The engine resource-read callback at RVA `0xA85F0` formats a
`data/game/<filename>` path, converts it to UTF-16, and opens it with a
read-binary mode string. This observed loose-file path gives no evidence that
a Lua archive or Arsenal patch archive could override these DL files.
The live image used for this offline analysis was 74,727,424 bytes, with no
unreadable pages, and was kept only in ignored local development artifacts.

The loader at RVA `0xFDB440` calls its resource-read callback, verifies the
decoded buffer at RVA `0x1269820`, then parses its DL structure. A mismatch
calls an engine error handler at RVA `0x3187B0`, whose code invokes another
handler and then executes `int3`. This is not a safe, ignorable warning path.
The offline
`tools/plan_projectile_entity.py --decoded-full` mode checks the original
full-file SHA-256 and game-side content hash, then reports the exact G-50
candidate field offset and resulting hashes without writing modified data.
The one-field candidate changes the game content hash from
`0xEBFD607F348CFC7F` to `0x0E28FCBD0A79611F`; authentic encryption alone
would therefore not make it pass the game's integrity check. A separate
**local-only** experiment changed an empty index slot as well and restored
the expected whole-file hash. It preserved all 271 existing projectile-weapon
index lookups in an offline model, then passed a sealed-box encrypt/decrypt
round-trip. The change adds a new index alias pointing to an existing record;
the loader may enumerate or reject that alias despite unchanged old lookups.
This does not establish that the game's parser accepts the modified index,
that its other integrity checks accept the file,
or that firing the Guard Dog creates an active G-50. The candidate, original
data, and encryption keys remain in ignored local development artifacts; no
replacement was installed on the game computer. Testing a replacement would
also carry game-integrity and account risk, so this is not a supported Mod
distribution route.

The native lookup for this exact component table was subsequently located at
`game.dll` RVA `0x514C10`. It reads the table pointer at component manager
offset `0xF12E80`, starts at `resource_hash % 542`, probes 16-byte entries
until the key matches or is zero, then returns the 616-byte record selected by
the entry's index. In the checked function, entry padding is not read and
duplicate record indices are not rejected. The unchanged 271 resource keys
resolve to their original record addresses under this **actual native lookup**;
the candidate Guard Dog record resolves to a `ProjectileEntity` field containing
the G-50 hash. RVA `0x61AF10` copies a selected 616-byte record while applying
**entity deltas**; its caller traverses the separately loaded
`generated_entity_deltas.dl_bin`. It is a configuration consumer, not an
entity creation function. A scan found no other direct reference to
the table pointer, but indirect or generic consumers have not been ruled out.
This narrows the index risk without verifying candidate loading or seeker
activation in-game.

The actual weapon-fire branch provides a stronger creation lead. At RVA
`0x6143CD`, the game tests whether the `ProjectileEntity` field is nonzero;
that branch calls RVA `0x615940`. This routine reads the projectile entity
hash from its weapon configuration and passes it as the third argument to
RVA `0xFDC140` at `0x6164D4`. The latter stores a game entity record and calls
the generic entity/component instantiation dispatchers at RVAs `0x581320`
and `0x581780`. Its other arguments include a game-generated 32-bit entity ID
and a writable creation request. Its ownership and network semantics have not
been mapped. The known head has two flags at
`+0/+1`, a 32-bit value at `+4` (the observed firing path writes `0x7FFF`),
a 64-byte transform at `+8..+0x47`, and pointers at `+0x48` and `+0x50`.
The first pointer refers to a large per-component initialization area built
by the firing path; the second refers to another prepared auxiliary block.
Neither pointer can safely be replaced with an empty/default value merely
to call the function.
The function does not return an entity handle; the ID is an input. A separate
wrapper at RVA `0xFDC0C0` obtains that ID and then calls the same function.
The G-50 and G-60 root entity definitions each contain 25 component IDs;
this dispatch path traverses their registered component IDs, including
Throwable (`259`) and Behavior (`284`). After correcting the callback-table
base to be relative to the component manager, the checked first/later callback
RVAs are Unit `0x523460`/`0x523650`, Throwable `0x544AF0`/`0x544CA0`,
Behavior `0x549020`/`0x549110`, and Motion `0x5506D0`/`0x550910`.
Their later stages read far into the `+0x48` initialization area: Throwable
reads at least `+0x418`, Behavior reads `+0x66C..+0x680`, and Motion reads
`+0x6A0/+0x6A8`. A minimal transform-only request cannot reproduce this
component setup. The weapon-fire path writes a direction vector at
`init+0x418/+0x420` and the source weapon instance ID at `init+0x428`.
Throwable's later-stage path (`0x544CA0` → `0x6C3370` → `0x6C5BC0`)
consumes those fields, calculates motion, submits vectors to an engine physics
backend, and publishes event hash `0x94FD1FEB`. The backend methods have not
been named or verified as seeker activation. This is stronger than merely
registering a component, but still does **not** prove autonomous flight or
targeting. The creation request, owner/network contract, and any throw-action
transition remain unverified. Calling `0xFDC140` directly from LuaJIT FFI
would therefore be unsafe and would not yet prove G-50 or G-60 activation.

A lower-impact live check can read the entity manager's existing 2,048-entry
creation ring at `+0xF32F18`: each 24-byte record stores a resource hash and
instance ID. The read-only diagnostic
`addons/seeker_drone/tools/read_spawn_ring.py` reports new G-50/G-60 entries
without installing a hook. Observing both equipment and the eventual throw
can establish whether a new entity is created on release or whether the game
acts on an already held entity. This ring does not retain the full creation
request or prove that the instance flies.

In a first read-only mission sample, the pre-throw ring's next slot was `471`
and it contained no G-50 record. After the requested ordinary G-50 throw, a
new G-50 record appeared in slot `471` with instance ID `532` at observer
elapsed time 19.03 seconds. A later G-50 record appeared in slot `472` with
ID `533`; the number of player throws in that interval is not yet established,
so this second record is not attributed to a specific action. The
observer also saw a zero-ID intermediate entry and now ignores such entries.
These observations support creation at throw time for the first instance,
but do not identify the throw-action call stack or prove how its seeker AI
starts. The game was then closed; no code hook, game file edit, or remote
diagnostic file was installed.

The bundled Filediver bulk projectile-weapon parser is unsuitable for this
field comparison: its Go struct reads 388 bytes per record while the current
DL type and native lookup use 616. A separate full-entity parse of original
versus candidate decoded files accepted both; after controlling for the
parser's baseline repeat differences, only the Guard Dog weapon entity
changed. This third-party parse remains weaker evidence than a game load.

The complete image also allowed a focused heavy-target search. References to
`tag_spot_enemy_gen_character_heavy` and
`tag_spot_enemy_anyfac_patrol_heavy` are in a hash-to-string lookup, not a
function accepting a target. The `TargetingComponent` name leads to component
storage growth/copy code; `BugArmored` is among spawn-configuration labels.
No checked candidate both accepts an actual target and returns a heavy-target
boolean. This historical search is no longer a release blocker: the user
subsequently removed the pre-spawn heavy gate and chose to rely on G-60's own
targeting after a proper native spawn.

The next useful experiment must determine whether an ordinary G-50 throw
creates an entity at `0xFDC140` or acts on a held entity created earlier,
then identify the state transition that starts flight. The resource hash
`0x2d398d1ec35e0838` and generated instance ID can constrain that trace.
A versioned function address alone is insufficient without a verified request
layout, owner/network contract, and thread constraints. The same
creation/activation path then needs validation for G-60; no separate
pre-spawn target-classification interface is required.

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
supply refill, and generation of either type whenever its air slot is vacant
and ammunition remains. Each grenade's native seeker logic should take over
after a proper game-entity spawn. An independent stratagem is
preferred; replacing the machine-gun Guard Dog stratagem is a fallback.

The loader's `gameplay` API coordinates independently supplied providers. It
does **not** provide any of these game-native functions. Before a drone addon
can register a working backend, the following must be found and validated:

1. A game-entity throwable creation/activation call that starts native seeker
   behavior, associates the owner, and behaves correctly in multiplayer.
2. An active-flight or terminal event for each seeker instance, plus local
   player ownership and drone/backpack/supply events.
3. A supported way to register a new stratagem and its backpack/loadout data;
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
