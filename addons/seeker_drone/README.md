# 追踪雷无人机：原型与待验证接口

此目录目前只实现弹药与空中单位的状态逻辑，**不是可安装、可运行的游戏 Mod**。
`src/inventory.lua` 不创建实体，也不改动游戏文件。独立新战备的注册、无人机
与 G-50/G-60 的生成、回包动画、补给事件和联机同步，都需要当前游戏版本的
资源与实机接口验证后才能接入。

主路线是**独立战备、独立背包和无人机控制逻辑**。机枪护卫犬仅是现成实体的
定位参照与最后兜底，不再把修改其开火当成追踪雷生成的前提。独立战备能让
补给、双弹仓和空中数量由自己的控制器管理，但不会自动解决原版 G-50/G-60
玩法实体的创建与激活；这个生成接口仍是两条路线共同的阻塞点。

## 已实现的规则

| 类型 | 无人机弹仓 | 背包储备 | 同时在空中 |
| --- | ---: | ---: | ---: |
| G-50 寻踪者 | 200 | 1000 | 2 |
| G-60 反坦克追踪者 | 100 | 500 | 1 |

两种追踪雷分别占用空中位置。实体生成成功才扣无人机弹药；命中、销毁或消失时
释放位置。`maintain(spawn)` 可调用游戏适配层填满空位，G-60 无需先查询目标或
重甲判定；生成后的寻敌与攻击由游戏原有逻辑处理。真正的实体创建函数尚未找到。
`reconcile(still_airborne)`
需要游戏提供真实的空中状态；不能只用 `Unit.alive`，查询失败时不会误生成。某种弹药耗尽且
背包有储备时，无人机需要回包；实际完成回包后，
两种弹药都尽量补满，不超过背包剩余数量。补给事件把背包储备补到 1000/500，
不会凭空增加无人机当前弹药或空中单位。

## 需要确认的游戏接口

1. 当前游戏能否登记独立战备及独立背包；用户允许在确实无法新增时，以替换机枪护卫犬战备作为兜底。
2. 怎样从无人机位置生成游戏原有的 G-50/G-60 实体，并取得稳定实体 ID。
3. 怎样可靠接收这两种实体的命中、过期和销毁事件，以释放空中位置。
4. 无人机回包、玩家换包或死亡，以及使用补给箱时的事件与联机所有权。

游戏接入前，不应把这个原型打包成可安装 ZIP。

`probe.lua` 是另一个只读诊断入口，可用 `python addons/seeker_drone/build_probe.py`
打包；它仅检查 Lua 运行时可见的资源和引擎接口，将结果写入
`SeekerDroneProbe.log`，不会生成手雷或修改游戏数据。探针结果用于决定下一步
如何接入真正的实体生成。

`src/engine_adapter.lua` 则是未部署的实验适配层：调用者必须提供当前无人机的
世界与发射位置，它才会尝试使用引擎的 `World.spawn_unit` 生成原有 G-50/G-60
资源。实机测试已确认，该通用接口不能单独触发 G-50 的原版飞行与寻敌，
因此**不能用作本 Mod 的正式生成回调**。
`src/resource_loader.lua` 预备了加载两种原版投掷物资源包的非阻塞流程；
它同样尚未部署或实机验证，卸载前必须确认相关单位都已消失。
`src/drone_context.lua` 仅供“暂时占用机枪护卫犬位置”的实验路径使用：
只有世界中恰好一架匹配无人机时才返回其位置，多架时不会猜测本地玩家的那架。

[Filediver 的 `DepositComponent` 解析器](https://github.com/xypwn/filediver/blob/master/datalibrary/deposit_component.go)
显示原版背包数据有一组 `Capacity`、`RefillAmount` 和 `DronePath` 字段；
它本身不足以直接表达本设计中 G-50 与 G-60 两套独立弹仓和储备，因此这部分
仍需游戏逻辑接入。该结构也不能单独证明可新增独立战备。

使用 Filediver 仓库随附的实体数据快照进一步核对（尚未证明它与远端游戏
当前版本完全一致）：机枪护卫犬背包的
`capacity/start_amount/refill_amount` 均为 8，`drone_path` 指向
`content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg`；
G-50/G-60 均有 `BehaviorComponentData`、`TargetingComponentData`、
`ThrowableComponentData` 和 `ExplosiveComponentData`，但后两者当前解析器
未实现，且 `ExplosiveComponentData.start_active=false`。这使
`World.spawn_unit` 的返回值不足以证明追踪雷已被原版投掷/激活流程接管。

## 2026-09-26 只读资源核对

在用户提供的远端游戏目录确认，`helldivers2.exe` 和 `game.dll` 的 SHA-256 与
本仓库 `scripts/archive.py` 中支持的版本一致。游戏资源索引包含：

- `content/fac_helldivers/equipment/throwables/self_destruct_drone/self_destruct_drone`
- `content/fac_helldivers/equipment/throwables/at_self_destruct_drone/at_self_destruct_drone`
- `content/fac_helldivers/equipment/backpacks/drone_mg/drone_mg_backpack`
- `packages/generated/loadout/self_destruct_drone`
- `packages/generated/loadout/at_self_destruct_drone`
- `packages/generated/loadout/drone_mg_backpack`

名称和存在性已核对，但没有从名称推定这些资源能被普通 Lua 插件直接生成、
注册为新战备或正确同步到其他玩家。没有修改远端游戏安装。
当前版本的 [OTL 武器研究](https://helldiversotl.com/research/ironclad-weapons)
也记录了 G-60 与 G-50 使用相同的已检查寻踪控制组件；这支持复用原有寻踪
行为的方向，仍不能证明普通 Lua 插件可负责生成和联机所有权。

纯逻辑测试可用本机 LuaJIT 运行：

```text
luajit addons/seeker_drone/tests/test_inventory.lua addons/seeker_drone/src
```

## 运行时探针结果

远端曾临时部署 `mods/tzy/seeker_drone_probe` 进行只读检查，随后已移除该探针
及备份；未修改 Arsenal 的 Mod 配置。加载器确认探针启动，Lua 中能看到
`Application.main_world`、`World.spawn_unit` 和 `Unit.alive` 函数。第二次测试
采到 19 次世界状态（单位数 1–2394），G-50/G-60 的 `can_get('unit', ... )`
始终为 false，也未观察到对应单位。用户随后确认当时进入了任务并投掷过 G-60。
旧探针只检查 `main_world` 且每 10 秒采样一次，所以不能据此断定游戏没有生成
G-60。v4 探针改为每 0.1 秒检查全部游戏世界，并且只在状态变化时记录。
后续需要
实机确认资源包加载、实体生成后的寻踪/伤害，以及独立新战备的注册路径。

## v4 探针：已确认 G-60 实体

用户进入任务投掷 G-60 后，v4 探针在游戏启动约 18.28 秒时看到
`Application.can_get('unit', G-60)` 从 `false` 变为 `true`；约 67.76 秒时在
第 11 个世界短暂看到 1 个 G-60 单位，约 108.59 秒后又在 `main_world`
看到 G-60 单位，计数随后升至 3。由此确认 Lua 可见该原版资源，
`World.units_by_resource` 也能枚举其实体。旧探针未捕捉到实体是采样
频率和世界选择不足，不能用来否定生成路径。

随后用户切换手雷并投掷 G-50，约 339.79 秒时也观察到它的
`can_get` 从 `false` 变为 `true`，任务世界中出现 1 个 G-50 实体。
两种原版投掷物资源和实体因此都确认可由 Lua 看见。

此结果尚未证明直接调用 `World.spawn_unit` 会启动原版追踪/爆炸逻辑，
也未证明实体消失时机与投掷物的“空中占用”相同。
观察到的 G-60 世界实体计数曾从 1 增加到 4，且数十秒内未回落；
不能单靠 `Unit.alive` 或资源实例数量判定是否仍在空中。

## 受控生成测试

单独的 `spawn_probe.lua` 在任务中检测到唯一一架机枪护卫犬及已加载的 G-50
后，从护卫犬上方调用了一次 `World.spawn_unit`。调用返回单位，日志也确认它
存活，但其世界坐标在 20 秒观察期内完全不变；随后探针成功销毁该测试单位。
这证明“创建 Stingray Unit”和“走游戏的投掷物生成/激活路径”不是同一件事。
探针没有生成 G-60。下一步必须定位游戏侧的实体创建/激活接口，
否则无法把这两个原版追踪雷交给原有逻辑处理。

## 武器生成路径调查（2026-09-26）

[Filediver 的 `ProjectileWeaponComponent`](https://github.com/xypwn/filediver/blob/master/datalibrary/projectile_weapon_component.go)
提供 `ProjectileEntity` 字段；其源码注释说明，非零时开火会生成实体，而不是
交给普通弹丸管理器。扫描 Filediver **内置快照**的 271 个此类武器组件，其中
12 个设置了该字段。机枪护卫犬的 `drone_mg_weapon` 则为零，现有开火路径是普通
弹丸。快照中没有武器直接将 G-50 (`0x2d398d1ec35e0838`) 或 G-60
(`0x8e325c933e55bf62`) 设为 `ProjectileEntity`。

这提供了一个待验证的游戏原生生成候选路径，但不能据此认定改掉护卫犬武器后
追踪雷会自动完成投掷物初始化、归属、寻敌和联机同步。机枪护卫犬本体与武器是
两个实体，且原版武器没有这个字段配置。当前游戏资源索引中，护卫犬武器有
`.unit`、`.bones`、`.physics` 等资源，却没有可供 Filediver 直接导出的
`.entity` 文件。Filediver 的组件解析数据来自它随程序内置的
`generated_entities.dl_bin.gz`；不能仅凭导出工具版本就认定它等于当前游戏。
随后做了整表校验：用户当前运行中的 `ProjectileWeaponComponentData` 子数据块
大小为 176,224 字节，连同 28 字节 DL 头的 SHA-256 为
`7648d8dbe9d0fe91693ee8608a5ce09a425f8436d86f986772a09d224ae1d510`，
与 Filediver 内置对应子数据块**逐字节一致**。因此这一张表的上述数值已
针对用户游戏版本核对；此结论不能外推至其他组件表。

只读内存定位还确认，`game.dll` 映像内没有 G-50、G-60 或护卫犬武器资源哈希，
配置数据处于独立内存分配中。找到的数份完整组件表副本都与 Filediver 一致，
但尚未证实哪一份被游戏实际读取，也未确认它们是否可安全覆盖。
因此暂不生成或安装“改 `ProjectileEntity`”的实机补丁。
离线 `tools/plan_projectile_entity.py` 对当前版本整张 DL 表的 SHA-256、
护卫犬武器哈希和索引逐项校验后，定位到该 8 字节字段距 DL 实例起点
`124548` 字节，原值全零。将它替换为 G-50 资源哈希后，候选整表 SHA-256
为 `c63a9af4c53a334b5754f4df4891c471eb5734c2f275a0ce5648944c2bf73821`。
这只是**离线变更方案**；工具不写游戏文件或进程内存，尚未证明当前运行时
哪一份表被护卫犬开火逻辑读取，更未验证开火能正确生成追踪雷。
后续只读扫描在主菜单找到 4 份、任务中找到 5 份相互独立且整表哈希完全一致的
原始数据副本。受控实验在玩家确认机枪护卫犬持续开火时，将这些副本中的
`ProjectileEntity` 临时替换为 G-50 哈希（最长 1 秒），随后逐份恢复并
重新核对整表哈希；三次实验均确认恢复成功。期间已加载的只读飞行探针
**没有观察到新增 G-50**。因此目前不能把这一原始数据字段的内存替换
作为可用生成后端；游戏可能在更早阶段把配置解析到别处，也可能还需其他
开火/实体初始化条件。未生成 G-60，也未留下运行时数据修改。
随后使用护卫犬武器记录的 32 字节唯一前缀，对游戏进程的私有可写内存
进行了完整只读扫描：主菜单约 4.3 GB、任务中护卫犬开火时约 5.8 GB。
两次扫描分别仅命中 5 份和 4 份可校验的原始 DL 表记录；没有发现相同布局的
表外记录。此结果不能排除运行时组件以不同结构存储，但说明继续按原始
`ProjectileWeaponComponent` 字节序列查找活跃副本不会得到更直接的入口。

另对当前 `game.dll` 的 `get_plugin_api` 导出进行运行时只读核对：其代码仅在
API ID 为 0 时返回标准插件回调表，其他 ID 返回空指针。回调表包含
`setup_game`、`units_spawned` 等标准生命周期入口；这不是一个可直接按
API ID 查询的 Helldivers 2 专用追踪雷生成服务。此处依据
[Stingray 插件 API 约定](https://help.autodesk.com/cloudhelp/ENU/Stingray-SDK-Help/sdk_help/extend_engine.html)
和 [官方 SDK 头文件](https://github.com/AutodeskGames/stingray-plugin-api-samples/blob/master/stingray_sdk/engine_plugin_api/plugin_api.h)
解释函数签名与回调表。继续做原生接入需要识别游戏内部玩法函数及其对象、
所有权和联机约束，不能把标准插件回调直接当作生成器。

已准备只读 `api_probe.lua`，在下一次任务内枚举 Lua 可见的目标、装甲和武器接口，
以寻找真正的重甲 `true` 判定和投掷物激活入口。它不调用这些接口，也不创建实体。

## 运行时接口清单

只读 API 探针实机列出了 `stingray.EntityManager.spawn`、
`stingray.GameSession.unit_synchronizer` 与 `stingray.UnitSynchronizer.spawn_unit`。
它没有发现可直接调用的目标查询或“重甲目标返回 true”函数。
其中 [`EntityManager.spawn` 的引擎文档](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/ns_stingray_EntityManager.html)
要求 `.entity` 资源，而当前游戏资源索引未列出 G-50/G-60 对应的 `.entity`；
[`UnitSynchronizer`](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_UnitSynchronizer.html)
需要游戏网络配置中预先定义对象类型，只负责常见单位状态同步，不能据此推定
追踪雷被激活。因此后续的 `entity_probe.lua` 先用 `Application.can_get('entity', G50)`
确认资源；只有返回 `true` 才生成一次，且会清理自己的实体。它不会生成 G-60。

实机结果：任务中已装备 G-50 并呼叫机枪护卫犬，探针记录
`g50_entity_available=false`，随后明确跳过生成。因而不能将
`EntityManager.spawn` 直接作为此 G-50 的生成器；没有调用它，也没有遗留测试实体。

## G-50 飞行状态观察（2026-09-26）

从用户当前游戏资源提取的 G-50 与 G-60 `.state_machine` 均有 `closed`、
`deploy`、`move`、`open`、`undeploy` 五个主层状态，索引依次为 0–4。
只读 `flight_probe.lua` 使用 `Unit.animation_get_state` 观察用户投掷的两枚
原版 G-50：两枚均由 `0/0/0` 经过 `1/1/1` 到 `3/1/1`，约 30 秒后
转为 `4/0/0`。第一枚进入 `4/0/0` 后仍被 `World.units_by_resource`
枚举，且 `Unit.alive` 继续返回 `true` 至少 60 秒；第二枚也在该状态下
继续存活。这实证说明实体存活数不能充当“空中追踪雷数”。

`4/0/0` 与原版资源中的 `undeploy` 一致，可作为**候选**结束信号；
当前只观察了两枚 G-50，尚未核对 G-60 的实机状态，也未验证命中目标时
是否遵循同一状态路径。正式计数仍需将生成时拿到的实体句柄与状态关联，
并确认结束时机，避免过早释放空中位置。`flight_probe.lua` 仅用于诊断，
不会生成追踪雷；其 ZIP 不属于可安装的正式 Mod。
`src/flight_state.lua` 因此只给出三值候选判定：主层状态 0–3 为活动中、
4 为退出中，API 缺失或异常时返回 `nil`，让弹药模块保留占位。

## 原生生成链路补充核对

只读导出当前游戏版本的 G-50 与 G-60 `.unit` 主数据后，确认两者分别约
13.6 KiB 与 14.5 KiB；其中有状态机资源引用，但未发现可读的 Flow 脚本或
玩法组件定义。[Filediver 的 `.unit` 解析器](https://github.com/xypwn/filediver/blob/master/stingray/unit/unit.go)
也只把这类数据解析为模型、骨骼、材质和状态机信息。因此即使通过 Lua
`World.spawn_unit` 创建相同的 `.unit`，也不能据此推断游戏已创建追踪雷的
`ThrowableComponentData`、寻敌和联机对象；实机的静止单位结果与这一限制一致。

官方 [Stingray EntityManager 文档](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/ns_stingray_EntityManager.html)
说明 `create` 只创建无组件空实体，`spawn` 则要求可加载的 `.entity` 资源；
实机已确认当前 G-50 的 `can_get('entity', ...)` 为 `false`。
[GameSession 文档](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_GameSession.html)
说明 `create_game_object` 创建的是按 `.network_config` 类型同步的字段表，
也不是自动初始化 Helldivers 2 玩法组件的入口。这些通用引擎 API 暂不能
替代游戏自己的追踪雷投掷/生成流程。

随后部署的只读 `network_probe.lua` 在任务中看到玩家投掷的原版 G-50，
但 `Network.game_session()` 虽返回会话，
`GameSession.unit_synchronizer(session)` 返回 `nil`；该 G-50 的
`Unit.id(unit)` 也返回 `nil`。因此当前会话没有暴露可用于这枚追踪雷的
`UnitSynchronizer`，不能凭通用同步器 API 为 Mod 创建或跟踪它。
此结果只排除已观察到的 Lua 接口，不代表游戏内部没有自己的联机对象。
