# 追踪雷无人机：原型与待验证接口

此目录目前只实现弹药与空中单位的状态逻辑，**不是可安装、可运行的游戏 Mod**。
`src/inventory.lua` 不创建实体，也不改动游戏文件。独立新战备的注册、无人机
与 G-50/G-60 的生成、回包动画、补给事件和联机同步，都需要当前游戏版本的
资源与实机接口验证后才能接入。

## 已实现的规则

| 类型 | 无人机弹仓 | 背包储备 | 同时在空中 |
| --- | ---: | ---: | ---: |
| G-50 寻踪者 | 200 | 1000 | 2 |
| G-60 反坦克追踪者 | 100 | 500 | 1 |

两种追踪雷分别占用空中位置。实体生成成功才扣无人机弹药；命中、销毁或消失时
释放位置。`maintain(spawn, find_target, is_heavy)` 可调用游戏适配层填满空位，
但真正的实体创建函数尚未找到。G-60 仅在找到目标且 `is_heavy(target)` 明确
返回 `true` 时生成；生成后的寻敌与攻击由游戏原有逻辑处理。`reconcile(still_airborne)`
需要游戏提供真实的空中状态；不能只用 `Unit.alive`，查询失败时不会误生成。某种弹药耗尽且
背包有储备时，无人机需要回包；实际完成回包后，
两种弹药都尽量补满，不超过背包剩余数量。补给事件把背包储备补到 1000/500，
不会凭空增加无人机当前弹药或空中单位。

## 需要确认的游戏接口

1. 当前游戏能否登记独立战备及独立背包；用户允许在确实无法新增时，以替换机枪护卫犬战备作为兜底。
2. 怎样从无人机位置生成游戏原有的 G-50/G-60 实体，并取得稳定实体 ID。
3. 怎样可靠接收这两种实体的命中、过期和销毁事件，以释放空中位置。
4. 无人机回包、玩家换包或死亡，以及使用补给箱时的事件与联机所有权。
5. 怎样从当前游戏取得目标与重甲判定，以满足 G-60 的生成前检查。

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
