# Local changes (making it run on Godot 4.5.1)

Tested on Godot 4.5.1.stable (macOS, Metal / Apple M4 Pro), headless and windowed.

| File | Change | Why |
|---|---|---|
| scripts/hud.gd:15 | SystemFont list: `"PingFang SC"` → `"Hiragino Sans GB"` | On macOS PingFang lives in `/System/Library/PrivateFrameworks/FontServices.framework/Resources/Reserved/PingFangUI.ttc`, which Godot's FreeType can't open → hundreds of `FreeType: Error loading font: ''` errors at startup and an empty font. Hiragino Sans GB is a normal system CJK font and loads cleanly. |

Verified with a throwaway driver scene (deleted afterwards): 3-hit combo, claw + parry → 十字斩, slam + perfect dodge → 瞬影斩, sweep + jump → 落雷斩, pounce hit, debug keys 1–4, phase 2 transition, boss death + end screen, player death, and `reload_current_scene` restart — no script/runtime errors.

## 2026-11-02 · 主角接上 Quaternius UAL1 + UAL2（免费版）骨骼动画

| File | Change | Why |
|---|---|---|
| assets/ual2/UAL2_Standard.glb, UAL1_Standard.glb, License.txt | 从两个包的 `Unreal-Godot/` 复制过来（都是无根运动版本） | UAL2 提供人偶模型 + 剑招；UAL1 提供待机 / 跑 / 翻滚 / 受击 / 死亡。两者骨骼和轨道路径完全一致，CC0 |
| 两个包文件夹里的 `.gdignore` | 新增空文件 | 不让 Godot 再导入包里的 Unity FBX / RM 版 / 女性人偶，避免重复导入、拖慢编辑器。原文件没动 |
| scripts/player.gd | 新增 `MODEL_PATH`、`EXTRA_ANIMS`、`ANIM` / `ANIM_FALLBACK` 表、`_build_model()`、`_hand()`、`_animate_model()`、`_play()`；`_make_blade()` 多了 parent / 方向参数；`_set_state()` 和落雷斩落地处重置 `cur_anim` | 有 UAL2 glb 就用骨骼人偶，UAL1 的动画以 `ual1/` 前缀并进同一个 AnimationPlayer；双刀挂在 hand_r / hand_l 骨骼上。缺 UAL1 时退回 UAL2 里的替补动作，连 UAL2 都没有就退回原来的方块占位。判定数据（COMBO / COUNTERS）一个数都没改，是用动画起点 + 播放速度去对齐挥刀最快的那一帧 |

动作对应（`player.gd` 的 `ANIM`）：

| 动作 | 动画 |
|---|---|
| 待机 / 跑 | ual1/Sword_Idle（改成循环）/ ual1/Sprint |
| 跳 / 下落 | NinjaJump_Start / NinjaJump_Idle |
| 翻滚 | ual1/Roll（1.9 倍速） |
| 三连击 | Sword_Regular_A / B / C |
| 弹反 | Sword_Block |
| 十字斩 / 瞬影斩 | Sword_Heavy_Combo / Sword_Dash（瞬影斩外加整体自转） |
| 落雷斩 空中 / 落地 | Sword_Regular_C 的不同段 |
| 受击 / 死亡 | ual1/Hit_Chest / ual1/Death01 |

验证：三连击、三种反击、Boss 四招、受击、死亡、`reload_current_scene` 重开，headless + 窗口都无报错；伤害数值和改之前完全一样。

## 2026-11-03 · Boss 接上 Mixamo 骨骼动画（模型 Maw J Laygo + Mutant 动作）

| File | Change | Why |
|---|---|---|
| assets/mixamo/*.fbx | 你从 Mixamo 下载的：Maw J Laygo（With Skin，带 4 张贴图）+ 17 个 Mutant 动作（Without Skin） | Mixamo 免费，可商用；所有 Mixamo 角色骨骼同名，动作通用 |
| scripts/boss.gd | 新增 `MODEL_PATH` / `ANIM_DIR` / `MODEL_SCALE`、`MOVES` 表、`ATTACK_ANIMS` 分段表、`_build_model()`、`_strip_root_motion()`、`_animate_model()`、`_play_move()`、`_play_segment()`、`roaring` 标记；`_build_visual()` 开头先建 `eye_mat` 再判断模型；`stagger()` / `_start_attack()` 重置动画状态；二阶段硬直标记 `roaring = true` | 有模型就用骨骼动画，没有就退回方块狼人。判定数据（ATTACKS）一个数都没改：每招切成几段，段终点 = 动画里出手最快的那一帧，并落在 hits[].t 上；动画时间跟着招式时间 t 走，所以二阶段加速时动画也一起加速 |
| scripts/boss.gd `_strip_root_motion` | 去掉 Hips 的水平位移，并按「Maw 胯高 / Mutant 胯高」缩放上下位移 | 走路 / 跑 / 跳劈自带往前走，和代码控制的位移冲突；动作是在 Mutant 上下载的，Maw 腿短一点，不缩放会脚陷地 |
| scripts/boss.gd 受击闪光材质 | 加法混合 + `disable_fog = true` | 半透明叠加材质会被雾染色，整只 Boss 变成半透明的红色鬼影 |
| scripts/player.gd 受击闪光材质 | `disable_fog = true` | 同上，防止雾色叠到主角人偶上 |

招式 → 动作（`boss.gd` 的 `ATTACK_ANIMS`）：三连爪 = Mutant Punch → Mutant Swiping → 停顿 → Mutant Punch；延迟重劈 = Jump Attack（蹲伏段 0.15 倍慢放憋力 → 跳起砸地）；扑击 = Mutant Jump Attack；低身横扫 = Standing Melee Attack 360 Low。待机 Mutant Breathing Idle、追击 Mutant Run、绕圈 Mutant Walking、硬直 Hit Reaction、二阶段 Mutant Roaring、死亡 Mutant Dying。

验证：三连击、弹反 → 十字斩、完美闪避 → 瞬影斩、跳过横扫 → 落雷斩、扑击命中、二阶段、死亡、R 重开，headless + 窗口都无报错；伤害数值和改之前完全一样。

## 2026-11-03 · Boss 改名「犀渠 · 枯林之主」

| File | Change |
|---|---|
| scripts/hud.gd | 顶部 Boss 名「灰鬃狼人」→「犀渠 · 枯林之主」；二阶段提示、结算文字里的「狼人」→「犀渠」 |
| scripts/boss.gd | 文件头注释更新（名字出处：《山海经·中山经》「其状如牛，苍身，其音如婴儿，是食人」） |

## 2026-11-03 · 犀渠体型放大到 2 倍（攻击范围不变）

| File | Change | Why |
|---|---|---|
| scripts/boss.gd | `MODEL_SCALE` 1.35 → 2.7（约 6.4m 高）；新增 `MODEL_BODY_RADIUS` 1.3 / `MODEL_BODY_HEIGHT` 6.0，`body_height` 变量；`_ready()` 先建外形再按体型建碰撞胶囊 | 更有压迫感。身体碰撞跟着变粗，主角不会钻进模型里 |
| scripts/boss.gd | `ATTACKS` 里的攻击范围、预警圈半径 **一个没改** | 按要求：地面攻击范围不扩大 |
| scripts/boss.gd | 跑 / 走动画播放速度 0.9 / 1.2 → 0.5 / 0.7 | 步子变大 2 倍，不放慢会脚底打滑；顺带显得更沉重 |
| scripts/boss.gd | 两个跳劈的腾空高度 ×0.6（`JUMP_LIFT`，下蹲幅度不变） | 放大后跳得 6 米多高，会飞出镜头 |
| scripts/boss.gd | 扑击落点从「玩家前 1.2m」改成「玩家前 body_radius + 0.3」 | 身体变粗后按原值会直接压在玩家身上 |
| scripts/camera_rig.gd | 距离 6.5 → 7.5、高度 3.2 → 3.4、看向点高度 1.5 → 2.2（`LOOK_HEIGHT`） | 近身时 Boss 的头不被切掉 |

## 2026-11-03 · 主角换皮：Mixamo 的 Ganfaul M Aure（动作仍用 UAL1 / UAL2）

| File | Change | Why |
|---|---|---|
| assets/player/Ganfaul M Aure.fbx | 你从 Mixamo 下载的角色（With Skin，带贴图） | 新外形 |
| assets/retarget/ual_bonemap.tres、mixamo_bonemap.tres | 新增：两份 BoneMap（SkeletonProfileHumanoid），把 UAL 骨骼（pelvis / hand_r …）和 Mixamo 骨骼（mixamorig_Hips …）都映射到 Godot 标准人形骨骼 | 人形骨骼重定向：两套不同命名、不同静止姿势的骨骼，导入后统一成同一套（Hips / RightHand …），UAL 的动作才能直接播在 Mixamo 角色身上 |
| assets/ual2/UAL2_Standard.glb.import、UAL1_Standard.glb.import、assets/player/Ganfaul M Aure.fbx.import | `_subresources` 里给骨骼挂上对应的 BoneMap（其余导入选项是默认值：改名骨骼、骨架节点改名为唯一名 GeneralSkeleton、修正静止姿势轴向、按胯高归一化位移） | 同上。原来的 .import 备份在会话临时目录 |
| scripts/player.gd | `MODEL_PATH` 改为 Ganfaul；新增 `ANIM_SOURCE`（UAL2，提供动作库）、`MODEL_HEIGHT`（按网格高度统一缩放到 1.83m）；换皮时用 UAL2 的动作库替换角色自带的 T-Pose；手骨名改为重定向后的 `RightHand` / `LeftHand` | 外形和动作分开：换角色只改 `MODEL_PATH`；找不到角色时自动退回 UAL2 人偶 |
| scripts/player.gd `_fit_grip()` | 新增：按手骨算握刀方向（小指根 → 食指根穿过拳心，从虎口伸出），刀长抵消模型缩放保持 1m | 重定向后手骨轴向变了，原来写死的偏移会让刀朝下 / 朝后；按骨骼算的话换任何角色都不用重调 |
| scripts/player.gd 受击闪光材质 | 改为加法混合 | Mixamo 角色上半透明叠加的 alpha 不生效，受击 / 弹反时整个人变成纯红 / 纯白 |

Boss（Maw + Mutant 动作）的导入设置没动，仍是原始 Mixamo 骨骼名。

验证：三连击、三种反击、跑、受击、死亡、R 重开，headless + 窗口都无报错，伤害数值和之前一致；截图检查了待机 / 三段攻击 / 翻滚 / 弹反 / 十字斩 / 瞬影斩 / 跳 / 下劈 / 受击 / 死亡。

## 2026-11-03 · 主角武器：双刀 → 右手单手剑 + 左手盾

| File | Change | Why |
|---|---|---|
| scripts/player.gd | 新增 `_make_sword()`（剑身 + 剑尖 + 护手 + 握把 + 剑首）、`_make_shield()`（木质圆盾 + 铁边 + 盾心）、`_fit_shield()`、`_metal()`、`_box()`；骨骼模型下右手挂剑、左手挂盾，取代双刀 | 你选了右手剑左手盾（不镜像）。程序化网格，和场景的灰盒风格一致，不用下载 |
| scripts/player.gd `_fit_shield()` | 按左手骨骼算：盾面朝手背方向（像绑在小臂上），中心在拳头偏手背一侧 | 和握剑一样按骨骼算，换角色不用重调 |
| scripts/player.gd `ANIM` | 待机 `ual1/Sword_Idle` → `Idle_Shield`（举盾警戒）；弹反 `Sword_Block` → `Shield_OneShot`（左手举盾格挡，1.6 倍速） | 弹反改成用盾挡。弹反窗口 / 反击 / 伤害 / 命中帧都没改 |
| scripts/player.gd | 弹反有效窗口的泛白从 0.3 降到 0.15 | 深色角色上太亮，像整个人变白 |

Ganfaul 自带的模型是单一网格，没有单独的武器 / 道具需要隐藏。
没有骨骼模型时退回的方块占位仍然是双刀（只是兜底）。

验证：三连击、弹反（举盾）→ 十字斩、完美闪避 → 瞬影斩、跳过横扫 → 落雷斩、扑击、死亡、R 重开，headless + 窗口都无报错，伤害数值完全一样；截图检查了待机 / 弹反 / 三段攻击 / 十字斩的正面和侧面。

## 2026-11-03 · 左右手切换（左手剑右手盾）

| File | Change | Why |
|---|---|---|
| scripts/player.gd | 新增常量 `LEFT_HANDED`（默认 false = 右手剑左手盾）、变量 `left_handed` / `model_node`、函数 `set_left_handed()`：把角色模型 X 方向缩放取负 = 整个角色左右镜像；按 H 运行中切换，并在屏幕中间提示当前握法 | 镜像后剑到左手、盾到右手，所有动作跟着镜像，不需要左手版动作；判定 / 伤害 / 按键不变 |
| scripts/player.gd | `_fit_grip()` / `_fit_shield()` 的缩放补偿改用 `model.scale.y` | 镜像时 x 是负数，用它补偿会把武器再镜像一次 |
| scripts/main.gd | 注册输入 `swap_hands` = H | 运行中切换 |
| scripts/hud.gd、README.md | 操作说明加上「H 换手」 | |

已知：Ganfaul 不对称的细节（挎包、单边的角）也会跟着换边。负缩放下蒙皮模型的光照 / 阴影截图检查正常，没有翻面。

验证：左手模式下三连击、弹反 → 十字斩、完美闪避 → 瞬影斩、跳过横扫 → 落雷斩、死亡，headless + 窗口无报错，伤害数值和右手模式一致；H 键切换来回正常。

## 2026-11-03 · 按住持续举盾

| File | Change | Why |
|---|---|---|
| scripts/player.gd | 新状态 `S.BLOCK`、`_st_block()`、`_is_guarding()`；`_st_parry()` 结束时还按着 K / 右键就进入举盾；`receive_attack()` 在弹反 / 闪避判定之后、受伤之前加举盾判定；`hurt_time` 变量（普通受击 0.45s，破防 `GUARD_BREAK_TIME`） | 点按仍是原来的 0.2 秒弹反 + 反击（完全没改）；按住则持续举盾 |
| scripts/player.gd 可调参数 | `BLOCK_REDUCTION = 0.7`（可弹反的招减伤 70%）、`BLOCK_ANGLE = 120`（只挡正面 120°）、`BLOCK_MOVE_MULT = 0.35`（举盾移速倍率）、`GUARD_BREAK_TIME = 0.9`（破防硬直秒数） | |
| scripts/player.gd 规则 | 举盾时：慢走、自动转向 Boss；不能攻击、不能翻滚，松开才能行动。可弹反（黄字）的招 → 减伤 + 小推开 + 轻顿帧；不可弹反（红字：延迟重劈、低身横扫）→ **破防**：全额伤害 + 0.9 秒硬直 + 「破防！」提示；背后来的攻击照常吃满 | |
| scripts/player.gd `ANIM["block"]` | `Shield_OneShot` 定格在 0.18 秒（盾举在正前方的那一帧） | |
| scripts/hud.gd、README.md | 操作说明：「K/右键 弹反(按住举盾)」；README 写了举盾规则 | |

验证：点按弹反 → 十字斩（不变）；按住挡三连爪 12+12+15 → 只掉 3.6+3.6+4.5 = 11.7；举盾移动距离约为平时的 1/3；举盾时按攻击 / 翻滚无效；举盾挡延迟重劈 → 破防、全额 28 伤害、硬直 0.9 秒；背后来的攻击照常全额；左手模式同样生效。原有全套战斗测试（连击、三种反击、扑击、死亡、R 重开）数值全部不变，headless + 窗口无报错。

## 2026-11-03 · 环境细化：灰败枯林 + 残雪 + 小雪

| File | Change | Why |
|---|---|---|
| assets/env/models/* | 从 Poly Haven 下载（CC0，1K）：倒木 dead_tree_trunk / dead_tree_trunk_02、树桩 tree_stump_01 / 02、枯枝 dry_branches_medium_01、石头 boulder_01 / rock_07 / rock_09 | 真实扫描的 PBR 模型，风格和 Mixamo 半写实角色一致 |
| assets/env/textures/* | Poly Haven（CC0，1K）：winter_leaves（地面枯叶）、snow_02（雪）、bark_willow_02（树皮） | |
| assets/env/CREDITS.md | 新增：每个素材的来源链接和授权 | |
| assets/env/ground_snow.gdshader | 新增：地面 = 枯叶 + 一块块积雪，按无缝噪声图分布；竞技场中间被踩过，雪少一半 | |
| assets/env/snow_cap.gdshader | 新增：积雪覆盖层（material_overlay），按世界坐标法线朝上的程度盖雪，边缘带噪声 | 树枝顶、石头顶、倒木上都有雪 |
| scripts/arena_builder.gd | 重写：`SNOW_COVER = 0.45`（**一个数控制全部积雪**：地面雪块 + 树 / 石头上的雪）；地面换成 shader；边缘 26 块扫描石头（替换原来的球体）；竞技场外一圈倒木 / 树桩 / 枯枝 25 个，场内散 7 根枯枝（无碰撞）；程序生成的枯树换上真实树皮贴图（三向投影）+ 积雪；新增枯草丛（MultiMesh，只长在没雪的地方）；飘灰换成小雪粒子 | 你的要求：树、草地、白雪。竞技场半径、碰撞、战斗都没动 |
| scripts/arena_builder.gd `_leaves()` | `vertex_color_is_srgb = true`，叶片数 3000 → 700，颜色调暗 | **修了之前「落叶发白」**：调色板是 sRGB 颜色却被当成线性色，显得发白 |

性能（M4 Pro，1280×720，窗口）：约 117 fps，约 2400 次 draw call、200 万三角面（Godot 导入时自动生成 LOD）。
验证：全套战斗测试数值不变、R 重开正常，headless + 窗口无报错。

## 2026-11-03 · 昼夜循环 + 光影；环境物件按规则摆放

| File | Change | Why |
|---|---|---|
| scripts/day_night.gd | 新增：太阳 + 月亮（冷蓝、较暗）两盏带阴影的平行光，按时间转动；天空 / 雾 / 环境光颜色按关键帧插值（午夜蓝黑、日出灰粉、白天灰、日落昏黄）；`DAY_LENGTH_SEC = 240`、`START_TIME = 0.35`、`JUMP_HOURS = 3`、`KEYS`；用真实时间走，不受顿帧 / 慢动作影响 | 你要的光源 + 昼夜 + 光影变化 |
| scripts/arena_builder.gd | `_environment()` 建太阳 / 月亮 / DayNight 节点；加 `@tool`；新增 `ensure_materials()` / `snow_cap()`；`_tree()` 改名为公开的 `make_tree()`；有 `scenes/env_layout.tscn` 时由它摆物件，没有就退回原来的随机摆放 | 摆放器（编辑器里也能跑）要用这些材质和枯树生成函数 |
| scripts/main.gd、hud.gd、README.md | 输入 `time_jump` = T（时间 +3 小时，屏幕提示当前时刻）；操作说明加「T 时间+3h」；README 写了昼夜和摆放器的用法 | |
| scripts/boss.gd | 新增 `_add_eyes()`：头骨上挂两颗发光的眼睛 + 一点暖红光（`EYE_OFFSET` / `EYE_SIZE` 可调）；二阶段眼睛变红（复用原来的 eye_mat） | 夜里也能看清 Boss 头朝哪 |
| scripts/env/scatter_rule.gd | 新增 Resource `ScatterRule`：模型 / 代码枯树、数量范围、ring_min / ring_max、最小间距、大小范围、随机朝向、`clustering`、埋地深度、是否盖雪、是否允许进战斗区 | 每种物件一条规则 |
| scripts/env/env_scatter.gd | 新增 `@tool` 节点 `EnvScatter`：`layout_seed`、`avoid_radius`、`density_noise`、可选 `density_map`（黑白图）、`rules`；检查器里有「重新生成」按钮；按面积均匀取点 → 战斗区剔除 → 按密度和 clustering 取舍 → 和已放物件保持间距 | 不再是纯随机：同一个 seed 结果固定，哪里密哪里稀可控 |
| scenes/env_layout.tscn | 新增：11 条规则（边缘大石 / 石块 / 碎石、粗 / 细倒木、两种树桩、场外 / 场内枯枝、近处 / 远处枯树），数量和原来接近；枯树和倒木设了 clustering，形成林子和空地 | 用现有物件演示 |

验证：午夜 / 日出 / 正午 / 日落截图检查；夜里红色预警圈、Boss 发光眼睛、雪地反月光都清楚；T 键时间 +0.125；全套战斗测试数值不变、R 重开正常；场景里摆了 157 个物件，帧时间约 6.9ms（M4 Pro，900×900）。

## 2026-11-03 · 树改成手工定点（方案 A），A1 放废墟；模型放进文件夹就自动换上

| File | Change | Why |
|---|---|---|
| design/tree_layout_planA.json | 新增：方案 A 的坐标（34 棵树 + 2 根倒木 + 3 个树桩；A1 = 废墟位置，D1 = 倾斜孤树；大小 S / M / L / XL） | 你选的方案 A |
| design/tree_layout_planB.* | 原来 56 棵的版本改名保留（json / png / svg / 生成脚本），没删 | |
| assets/env/tree_layout_planA.json | 上面那份的游戏内副本（design/ 有 .gdignore，游戏读不到） | |
| scripts/env/tree_layout.gd | 新增 `@tool` 节点 `TreeLayout`：按 json 摆每一棵树 / 倒木 / 树桩 / A1 废墟。`ZONE_MODELS` 定每个区用哪个模型文件夹（B → old_tree，C / G → dead_trees_demo，D → spooky_tree，E / H → dead_trees_set，F → tree_stump_scan，树桩 → burnt_stump，A1 → altar_ruins）；套装模型按树的编号自动挑其中一棵；模型按 `TARGET_HEIGHT` 缩放、底部贴地、居中；**文件夹没有模型就自动用代码枯树 / 占位废墟顶替**；检查器里有「重新生成」按钮 | 不随机，哪里几棵就几棵；以后丢模型进去就自动换 |
| scripts/env/tree_layout.gd `_ruins()` | A1 占位废墟：两根断柱 + 歪掉的拱梁 + 倒地断柱 + 石台 + 地基（boulder 贴图三向投影 + 积雪），正面朝竞技场 | 等真正的废墟模型 |
| assets/env/sketchfab/README.md | 新增：每个模型解压到哪个文件夹（文件夹名要对上） | |
| scripts/arena_builder.gd | 场景里加上 TreeLayout 节点 | |
| scenes/env_layout.tscn | 关掉随机摆放的「近处 / 远处枯树、粗 / 细倒木、树桩 A / B、场外枯枝」7 条规则；保留边缘石头和场内枯枝 | 树、倒木、树桩都改由方案 A 决定 |

验证：34 个位置都对；A1 废墟正面朝竞技场；用临时替身模型测了「放进文件夹自动换上」（缩放到目标高度、贴地、套装只显示一棵），测完已删除；全套战斗测试数值不变、R 重开正常，headless + 窗口无报错。

## 2026-11-03 · 接上 Sketchfab 模型；竞技场改成有高低差的石台；去掉草

| File | Change | Why |
|---|---|---|
| assets/env/sketchfab/*.import（贴图） | `process/size_limit` 0 → 2048 | 下载的贴图很多是 4K / 8K，一次开局要加载 7 秒多；限制后 1.6 秒，显存也省很多 |
| scripts/env/tree_layout.gd | `ZONE_MODELS` 改成你实际的文件夹名（dead_trees、4k_tree_stump_megascan）；新增 A1 组合（残拱 + 王座古树 + 两盏石灯）和石台外固定摆件（props）；套装切成单棵：先找贴地的树根再把三角形分给最近的树根，并只保留用到的顶点（`_pack_variants` / `_compact`）；F 区高度 ×0.5；树按地面高度摆 | 不随机，按方案 A；你下载的模型都用上了 |
| assets/env/tree_layout_planA.json、design/tree_layout_planA.json | 新增 `a1_group`（4 件）和 `props`（5 件：两堆乱石、两条长条岩、一个矮树桩） | |
| assets/env/platform_stone.gdshader | 新增：大块石板（Poly Haven cobblestone_large_01），石缝里积雪（用高度图找石缝）+ 几块薄雪 | |
| scripts/arena_builder.gd | 新增 `_platform()`：半径约 18.7 米的石台（边缘不规则、侧面石墙），**北侧往废墟方向缓坡升高 0.6 米**、**西侧一块抬高 0.35 米的石阶**、东南一块微微下沉 0.12 米，坡都 < 12°，直接走上去；碰撞用台面网格；`ground_height()` 给出脚下高度；`GROUND_LAYER` 渲染层；去掉草；落叶只撒在石台外 | 你要的石头台面 + 高低差，不要草 |
| scripts/boss.gd | 预警圈从平的圆片改成 **Decal 投射**（只投到地面层，带发光，夜里也清楚）；扑击落点的高度 = 落点地面高度；跳过低扫 / 跳太高的判断改成「离玩家脚下地面多高」；`floor_snap_length = 0.6` | 石台不平：圆片会浮空 / 陷进去；站在高处不应该算「跳过了」 |
| scripts/player.gd | `floor_y` / `air_height()`；`floor_snap_length = 0.5`；和 Boss 分开的判断改成相对高度 | 同上 |
| scripts/main.gd | 出生点高度 = 石台高度 | |
| scenes/env_layout.tscn | 关掉场内枯枝规则 | 枯枝会插进石台里 |
| assets/env/CREDITS.md | 加上 2 张石头贴图和 14 个 Sketchfab 模型的授权 / 署名 | CC-BY 必须署名 |

验证：全套战斗测试数值不变；在北侧高台上、西侧石阶上都能跳过低扫（落雷斩窗口正常打开）；站在坡上高处但没跳时，低扫照样打中（16 伤害）；扑击落地贴地；在坡上走路不会离地；预警圈贴着石台、夜里发光；M4 Pro 1280×720 约 7ms 一帧（约 140 fps，画面约 900 万三角面）。

## 2026-11-04 · 可破坏物、Boss 绕障 / 撞断、镜头防穿模、能跑到树林里（布局待确认）

| File | Change | Why |
|---|---|---|
| scripts/env/destructible.gd | 新增 `Destructible`（组 destructible）：树 / 灯 / 拱门三种；HP 按「挨几下」算（重劈、扑击算 2 下）；`damaged_by` 决定哪些招能打坏；被打会抖；**树**以树根为轴往被打的反方向倒下、落地激起雪雾、倒下后不再挡路；**灯**碎成几块（带物理）、灯光熄灭；**拱门**用简化盒子碰撞（不用 194 万面的网格），塌下来变成一堆带物理的石块 + 雪雾，原地留下有碰撞的碎石堆（扫描石头） | 你要的「能躲、能被 Boss 打坏」 |
| scripts/boss.gd | `_hit_destructibles()`：每次出招检查攻击范围里的可破坏物并打坏它们；**挡在 Boss 和玩家之间的树 / 灯 / 拱门会替玩家挡下爪击和低扫**；`_steer_around()`：追玩家时绕开撞不断的大树 / 拱门；走路撞上小树（S 号）和灯直接撞断 | |
| scripts/camera_rig.gd | 从玩家头顶往镜头位置打射线，碰到树 / 拱门 / 地面就把镜头拉到它前面 | 镜头不穿进树里 |
| scripts/main.gd | `PLAY_RADIUS = 26`：玩家 / Boss 能跑到树林里（以前被限制在石台 18 米内） | |
| scripts/player.gd | 软边界：离边界 1.5 米内往外走的速度逐渐被抵消，到 25.5 米硬挡住 | |
| scripts/arena_builder.gd | 石台边缘改成 2 米缓坡降到地面（去掉侧面石墙） | 能跑出石台以后，原来 0.25 米的台阶会卡住人 |
| scripts/env/tree_layout.gd | 在能跑到的范围里（< 27 米）的树自动变成可破坏物（树干碰撞，S / M / L 挨 1 / 2 / 3 下，S 号小树 Boss 撞上就断）；倒木、树桩加碰撞；石灯加暖色灯光并可破坏；拱门在范围里时可破坏 | 换布局时只改坐标，不用改代码 |
| scripts/day_night.gd | 灯（组 lamp_light）夜里亮、白天暗 | |

**还没动**：树 / 拱门 / 灯的位置、石台大小（等你确认新布局 v2）。现在的布局里只有 6 棵树和 2 盏灯在能跑到的范围内。

验证：可破坏物逐项测试——树挡爪击（挡 2 下后倒，第 3 下打到玩家）、重劈打倒树、Boss 撞断小树、Boss 绕开大树追到玩家、低扫打碎灯（灯灭）、拱门被重劈 3 下后倒塌成碎石堆、镜头在树前拉近（7.5 → 4.9 米）、软边界停在 25.5 米、从树林走回石台不卡；全套战斗测试数值不变、R 重开正常；M4 Pro 1280×720 约 7ms 一帧（夜里灯全亮也一样）。

## 2026-11-04 · 布局 v2 上线

| File | Change | Why |
|---|---|---|
| design/tree_layout_v2.json、assets/env/tree_layout_v2.json | 新增：你确认的布局 v2——19 棵近景树（N 老枯树 / E、W 写实枯树 / D1 扭曲孤树倾斜 / D2、S 烧焦断树）、68 棵远景树（原 69 棵，去掉 1 棵离古树 / 别的树不到 3 米的）、拱门 (0,-20)、王座古树 (0,-30) 当远景、10 盏石灯、2 根倒木、3 个树桩、石台外的乱石 / 长条岩 / 矮树桩 | |
| scripts/env/tree_layout.gd | 读 v2；每棵树可以单独指定模型（`model`）；远景树（`far`）不带碰撞 | 方案 A 的文件还在（tree_layout_planA.json） |
| scripts/arena_builder.gd | 石台半径 18.7 → 12；北侧高台从 z = -4.5 开始 3 米缓坡升 0.6 米；西侧石阶挪到 (-7, 2)；东南小凹地挪到 (6, 6)；小雪和落叶范围扩大到整个树林 | |
| scripts/main.gd | 石台半径 12；玩家出生 (0, 7)、Boss 出生 (0, -4) | |
| scenes/env_layout.tscn | 边缘石头挪到 26.3 ~ 27.6 米（能跑范围的边界）；不往 26 米以内放 | 当成边界的标记 |
| scripts/env/destructible.gd、scripts/camera_rig.gd | 挡住镜头的树变半透明（不拉镜头）；拱门 / 地面还是会把镜头拉近；碎块 / 雪雾的计时器挂在它们自己身上 | 树多了以后镜头老被挡；重开场景时不再报错 |

验证：19 棵树 + 10 盏灯 + 拱门都可破坏；大树 W1 挡下了三连爪（玩家 0 伤害，树挨满 3 下倒下）；两次重劈砸倒 N1；Boss 重劈打碎拱门；爪击打碎灯；在树林里追 30 秒最多卡 1 秒，顺手撞断 / 打坏 6 ~ 8 个；全套战斗测试数值不变、R 重开正常；M4 Pro 1280×720 白天 / 夜里都约 7ms 一帧。

## 2026-11-04 · 修「树浮在空中」和穿模

| File | Change | Why |
|---|---|---|
| scripts/env/tree_layout.gd `_trunk_base()` | 树按**树干底部**贴地（离地 15~35% 高度那段树干的中心 → 中心附近最低的顶点），再往地里埋 0.25 米（`TRUNK_SINK`）；树桩同样 | **原因**：以前按模型包围盒的底部对齐。老枯树、扭曲枯树这些模型树根往外往下伸得很长，树根尖碰到地，树干却悬在 1~2 米高的地方，看起来就是「浮在空中」。现在树根多出来的部分埋进土里。检查脚本：97 个物件里所有树的树干底部都 ≤ 地面（中位数埋 0.25 米） |
| scripts/env/destructible.gd、scripts/boss.gd | Boss 身体挤进树冠（距离 < 体宽 + 树冠半径的一半）：树抖一下、树冠上掉一团雪；小树（S 号）直接撞断；每棵树 0.8 秒最多一次 | **原因**：近景树只有树干有碰撞，6.4 米高的 Boss 的胳膊 / 角会穿过树枝；现在穿过去时树有反应，看起来是故意的 |
| scripts/env/tree_layout.gd `_spread_canopies()` | 量出每棵近景树缩放后的树冠半径；树冠互相穿插、或者穿进拱门 / 石灯的，往外挪（离布局坐标最多 1.5 米） | 检查结果：布局 v2 本身间距够，0 处树冠互相穿插、0 处穿进拱门 / 灯，所以这次没有挪任何树；以后改布局时会自动挪 |
| scripts/camera_rig.gd | 镜头在树冠里时，那棵树也变半透明 | 在林子里镜头会钻进树冠 |

没做：给玩家加树枝碰撞——这些树最低的树枝大多在 2 米以上（主角 1.8 米），加了容易卡住人和镜头，暂时只保留树干碰撞。

验证：全套战斗测试数值不变、R 重开正常；M4 Pro 1280×720 约 7ms 一帧。

## 2026-11-04 · 树会被推弯（弹簧）；准备布局 v3（未应用）

| File | Change | Why |
|---|---|---|
| scripts/env/destructible.gd | 新增 `push()` 和弹簧弯曲：有东西挤进树冠时，树以树根为轴往反方向弯，角度 ≈ 把树冠推开「挤进来的深度」需要的角度（深度 / 树冠高度 × 2）；没人推了带阻尼弹回来（稍微晃过头一点）；参数 `BEND_STIFF = 28`、`BEND_DAMP = 5.5`；被打时的抖动叠加在弯曲上；倾斜孤树保留原本的倾斜 | 你选的「树会被推弯」。不需要骨骼，整棵树绕树根转 |
| scripts/boss.gd | Boss 每帧推身边的树：最多弯 0.3 弧度（约 17°）；掉雪 / 小树撞断保留 | |
| scripts/player.gd | 主角穿过树冠也会推：最多 0.06 弧度（约 3°） | 轻微反馈 |
| design/tree_layout_v3.json | 新增（**没有应用**，等你确认）：只改近景树——16 棵分成 6 簇（半径 18~24 米），石台外留 ≥7 米的环形通道，簇之间 6~8 米空隙；其余同 v2 | 给 Boss 留通道 |

测试：Boss 擦过大树 N1 时弯约 4°，挤得深时弯约 14°，离开后约 0.5 秒弹回原位；全套战斗测试数值不变、R 重开正常。

## 2026-11-04 · 再修「树浮在空中」

| File | Change | Why |
|---|---|---|
| scripts/env/tree_layout.gd `_trunk_base()` | 改成「切片量宽度」：底部 40% 高度切 16 片，每片取顶点到树干中心距离的 80% 分位当宽度，从下往上第一片 ≤ 最窄片 × 1.4 的就是树干起点；对准地面后再埋 `TRUNK_SINK` 0.25 米 | 旧方法在树根散得很开 / 树干歪的模型上找偏，用户截图里还有树根悬空。逐棵检查（90 个：近景 19、远景 68、树桩 3，含切套装每一棵）：树干一圈内最低顶点相对射线地面全部 ≤ -0.15 米，中位数 -1.6 米 |

验证：低角度截图 10 个方向；全套战斗测试数值不变（三连后 292 → 弹反 266 → 幻影 244 → 下劈 214），R 重开正常。

## 2026-11-04 · 石台边加石头小台子

| File | Change | Why |
|---|---|---|
| assets/env/ledges_v1.json（副本 design/ledges_v1.json） | 新增：4 块 rock_formation_scan_2 小台子 L1~L4，方位角 54° / -112° / 116° / -52°、离中心 12.5~13 米，长边沿石台边缘，长 5.5~7.5 米、高 0.55~1.2（实际露出地面 0.3~0.95 米）；另存 2 块 wooden_terrain_thing_scan（W1、W2，`enabled: false`，不生成） | 用户要「石头小台子加在中间平台边上，让地貌更丰富」，选了 rock_formation_scan_2；木桩弧形台子留着备用 |
| scripts/env/tree_layout.gd `_ledges()` | 读 LEDGES_JSON：按长度缩放、高度单独压扁到 height；贴脚下最低的地面再埋 0.08 米；碰撞直接用模型三角面（ConcavePolygonShape3D）；网格放进 GROUND_LAYER，预警圈能投上去；带雪 | |
| assets/env/CREDITS.md | rock_formation_scan_2、wooden_terrain_thing_scan 补上链接和用途 | |

布局（沿 r≈12.5 米量弧长）：北边拱门方向空 ~23 米、南边出生方向空 ~16 米；东（L1↔L3）、西（L4↔L2）各空 ~7 米，中间各立着一盏石灯（石灯 5 / 6）。
验证：Boss 从里往外追过每一块都不卡（2.4~2.5 秒跑 12 米，和平地一样快）；主角跳得上全部 4 块，最矮的 L3 能直接走上去；Boss 重劈的红色预警圈能投在台子上；全套战斗测试数值不变（292 → 266 → 244 → 214），R 重开正常；1280×720 约 8.2ms 一帧（之前约 7ms，台子的三角面碰撞 + 高精度扫描网格）。

## 2026-11-04 · 换上布局 v3

| File | Change | Why |
|---|---|---|
| scripts/env/tree_layout.gd | `LAYOUT_JSON` → `assets/env/tree_layout_v3.json`（从 design/tree_layout_v3.json 复制）：近景树分 6 簇（离中心 19.5~25 米），石台外留 ≥7 米的环形通道；道具 / 远景树 / 树桩和 v2 一样 | 用户确认「可以换 v3」。v2、方案 A 的文件都还留着 |
| scripts/boss.gd `_step_up()` | Boss 顶到石头小台子（组 `ledge`）时直接迈上去：往前方身体边缘外一点向下打射线，台阶 ≤ 1.3 米就抬高 | 检查时 Boss 斜着撞到 L4（最高那块）的侧面会卡住 |
| scripts/boss.gd `_steer_around()` | 绕障碍时不再把拱门当成一整个圆绕开 | 拱门中间空约 6 米宽，Boss 原来被推到柱子上卡住（v2 也有这个问题） |
| scripts/env/tree_layout.gd `_ledges()` | 台子碰撞体加进组 `ledge` | 给上面的迈步用 |
| assets/env/tree_layout_v3.json、design/tree_layout_v3.json | v3 里两棵近景树的编号 T1、T2 改成 K1、K2 | 和树桩 T1、T2 重名，Godot 会把后加的节点自动改名，检查脚本漏查 |

验证：87 个（近景 16 + 远景 68 + 树桩 3）逐棵量树干底 vs 射线地面，全部 ≤ -0.15 米，0 棵浮空；近景树和 L1~L4 最近也隔 9.4 米，树冠不碰台子；Boss 从中心往 8 个方向追到 22 米外的玩家，5.3~5.6 秒追到、0 次卡住（修之前 2 个方向卡住）；全套战斗测试数值不变（292 → 266 → 244 → 214）、R 重开正常；1280×720 这次量到约 3.3ms 一帧。

## 2026-11-05 · 石头台阶改成「从树林走上石台」的入口

| File | Change | Why |
|---|---|---|
| assets/env/ledges_v1.json（副本 design/ledges_v1.json） | L1~L4 改成 `mode: "approach"`：方位角 65° / -65° / 108° / -108°（v3 树簇之间的 4 个空当），台阶高的一头落在离中心 10.6 米，宽 7 / 7 / 6.5 / 6.5 米 | 用户：方向不对，要的是让玩家从森林里走上石台。模型的台阶是沿短边 -X 一级级升高的，之前沿石台边缘摆，高的一头朝外，看起来像一堵墙 |
| scripts/env/tree_layout.gd `_ledges()` | approach 模式：模型 -X（高的一头）朝中心；高度自动算——最高一级和那里的石台面齐平（+3 厘米），最低一级埋进林地 5 厘米 | |
| scripts/arena_builder.gd | `PLATFORM_TOP` 0.25 → 0.5；边缘缓坡从 2 米收到 1.2 米（北边高台那边 2.5 米），坡度都在 35° 以内 | 石台边只高 0.25 米时，台阶压扁后几乎看不出一级级的 |
| scripts/player.gd `_step_up()` | 顶到东西时，前方 0.5 米处的落脚点是平的、高 ≤ 0.35 米就迈上去 | 台阶每一级比胶囊体能自己滑上去的高；台阶和石台缓坡交界处也会挡人 |

验证：主角从树林经 4 个台阶都能直接走上石台（2.6~2.7 秒走 10 米），从别的地方走上石台也正常；Boss 8 个方向追人 0 次卡住；全套战斗测试数值不变（292 → 266 → 244 → 214）、R 重开正常。

## 2026-11-05 · 拱门碎石换成 70_stylized_rocks

| File | Change | Why |
|---|---|---|
| scripts/env/destructible.gd `_rock_pool()` / `_rock_node()` / `_rock_chunk()` | 从 70_stylized_rocks 里挑 14 块长宽高差不多的「块状」石头（`ROCK_PICK`），每块挪到自己中心，颜色乘 `ROCK_TINT`（压暗一点贴近拱门）；拱门的 `_ready` 就把它们准备好 | 用户下载了这个包，想要拱门被打碎的感觉 |
| scripts/env/destructible.gd `_collapse()` | 飞出 22 块：8 块大的（0.9~1.5 米）落地停稳后冻结、留在原地；14 块小的 5~8 秒后缩小消失；飞出 12 米外或 7 秒还没停的也缩小消失。碎石堆的碰撞盒里堆 3~7 块石头（带雪）。找不到石头包时还用原来的方块 + 扫描大石头 | |
| scripts/env/destructible.gd | 碎块直接给初速度，不用 `apply_central_impulse` | 刚加进场景的刚体用冲量时物理服务器按质量 1 算，大石头会被打飞几十米、冻在半空 |
| scripts/env/destructible.gd `RUBBLE_LAYER`、scripts/player.gd | 碎石堆和留下的大石块放在第 8 碰撞层：只挡主角（主角 mask 加上这一层），Boss 直接踩过去 | Boss 走上碎石堆会卡住，追不到拱门后面的人 |
| scripts/boss.gd `_step_up()` | 除了撞墙，这一帧几乎没往前走也算「顶住了」，试着往上迈 | 卡在台阶棱上时不一定算撞墙 |
| assets/env/CREDITS.md | 加上 70_stylized_rocks（CC-BY-4.0，要署名） | |

验证：Boss 实际重劈 2 下（4.1 秒）打碎拱门；10 秒后剩 8 块大石头，都在拱门 4.4 米内；打碎那一帧 ~30ms，之后约 3ms 一帧；Boss 能穿过碎石堆追到拱门后面的玩家（3 秒）；主角会被碎石堆挡住（可以绕开或跳）；全套战斗测试数值不变（292 → 266 → 244 → 214）、R 重开正常。

## 2026-11-05 · 修「特别卡」：台阶碰撞换成简化高度网

| File | Change | Why |
|---|---|---|
| scripts/env/tree_layout.gd `_ledge_collision()` | 石头台阶的碰撞不再用模型三角面（每段约 30 万个三角形），改成在台阶上铺 0.3 米一格的高度网（每格取顶点最高点，外圈贴地成陡坡），几百个三角形；台阶外观不变 | 主角 / Boss 在台阶附近时，物理一帧要几百毫秒 |

测量（M4 Pro，2560×1440 窗口，主角绕石台边跑 1.5 圈经过 4 段台阶、Boss 追）：
- 修之前：平均 118 ms 一帧，95% 分位 694 ms，最慢 3.4 秒；物理 95% 分位 162 ms
- 只去掉台阶碰撞：平均 7.3 ms → 确认就是台阶碰撞
- 修之后：平均 7.3 ms（约 130 fps），95% 分位 13 ms，最慢 29 ms；物理 95% 分位 15 ms

验证：主角从 4 段台阶都能走上石台（2.7 秒）；Boss 8 个方向追人都不卡（5.3~5.6 秒）；全套战斗测试数值不变（292 → 266 → 244 → 214）、R 重开正常。
还可以再省的（没动）：画面一帧约 1900 万个图元——拱门模型 194 万面、王座古树 84 万面，加上太阳和月亮两盏平行光都开阴影；M4 Pro 上还跑得动，以后要上低配机器再减面 / 关月光阴影。

## 2026-11-06 · 镜头在石灯前一拉一放

| File | Change | Why |
|---|---|---|
| scripts/camera_rig.gd | 镜头防穿模的射线不再因为石灯拉近（和树一样排除掉），石灯挡在中间时变半透明；被挡住拉近以后停 0.3 秒（`PULL_HOLD`）再放长 | 用户：在石灯前翻滚、被石灯卡住时镜头 zoom in 又 zoom out。石灯很细，主角贴着它翻滚时射线一下打中一下打不中 |

复现测试（10 盏石灯 × 3 个角度，主角背对石灯往后翻滚两次）：
- 修之前：10 次出现镜头猛拉近再推远，最近拉到离主角头 0.1 米，一帧最多跳 1 米
- 修之后：镜头离主角始终 6.6~7.9 米（只是正常跟随），一帧最多变 0.29 米
拱门、地面、台阶照样会把镜头拉近。全套战斗测试数值不变（292 → 266 → 244 → 214）、R 重开正常。

## 2026-11-06 · 建 git 仓库，把现在的东西都存成一个基线

- 这个项目之前不是 git 仓库（没有分支可以合并）。在本地建了仓库，分支 `main`，第一个提交 `160f4b6` 就是截至 11-06 的全部内容；没有远程仓库，什么都没推上去
- `.gitignore`：忽略 `.godot/`（缓存）、`.DS_Store`、两个下载来的原始动画包文件夹（`Universal Animation Library*[Standard]`，游戏用的是 `assets/ual2` 里复制过来的那份）、临时测试脚本；**保留** `*.import`（主角 / Boss 的骨骼重定向设置写在 .import 里，丢了动画就坏了）。原来的 .gitignore 忽略了 *.import，改掉了
- 仓库 512 个文件，.git 约 708 MB（大部分是 Sketchfab 模型贴图）。没开 Git LFS
- 提交后从仓库状态跑全套战斗测试：数值不变（292 → 266 → 244 → 214）、R 重开正常

没用到 / 重复的文件（都还在，没删）：
| 位置 | 大小 | 说明 |
|---|---|---|
| assets/env/sketchfab/the_ancient_gnarled_tree_3d_model_free/rock_formation_scan_2/ | 97 MB | rock_formation_scan_2 的重复副本 |
| assets/env/sketchfab/ruined_stone_bridge_broken_arch/wooden_terrain_thing_scan/ | 72 MB | wooden_terrain_thing_scan 的重复副本 |
| assets/env/sketchfab/medieval_ruin_entrance/ | 1 MB | 下载了没用（砂岩颜色不搭） |
| design/tree_layout_planA.json、planB、v2 | 很小 | 旧布局，留着可以换回去 |
| ~/Downloads/werewolf_boss_demo、werewolf_boss_demo.zip | | 最早的旧副本，别用 |
| ~/Downloads/ 里的 wooden_terrain_thing_scan*.zip、70_stylized_rocks.zip 等 | | 已经解压进项目的原始压缩包 |

## 2026-11-06 · 清掉重复 / 没用的文件

全部移进了 macOS 废纸篓（还能找回），共腾出约 916 MB：
- 项目里：古树文件夹里重复的 rock_formation_scan_2（97 MB）、拱门文件夹里重复的 wooden_terrain_thing_scan（72 MB）、没用的 medieval_ruin_entrance（CREDITS.md 里那行一起删了）。删之前查过没有场景 / 脚本 / json 引用它们
- ~/Downloads：最早的旧项目副本 werewolf_boss_demo（文件夹 + zip），以及已经解压进项目的 Sketchfab / 动画包压缩包（18 个 zip）
- 没动：design/ 里的旧布局、Downloads 里和这个项目无关的文件

重新导入后跑全套战斗测试：数值不变（292 → 266 → 244 → 214）、R 重开正常。

## 2026-11-06 · 打击特效（第一批，还没有音效）

| File | Change | Why |
|---|---|---|
| scripts/fx.gd（新） | 特效管理节点（组 `fx`）：火花、闪光、血雾、地面冲击环、裂地、贴地尘土、爪痕弯月、落雷光柱、残影烟、死亡灰烬、屏幕边缘泛色 | 全部代码生成，不用外部贴图。粒子开局建好放池子里轮流用（中途新建粒子会编译着色器卡一下）；冲击环 / 裂纹用 Decal 投到地面；不加任何碰撞体 |
| scripts/fx_trail.gd（新） | 拖尾带子：每帧记两个点，连成渐隐的条带 | 主角刀光、Boss 爪光 |
| scripts/main.gd | 生成 Fx 节点；完美闪避慢动作期间屏幕四周发暗偏蓝 | |
| scripts/player.gd | 刀光（普攻白蓝、反击金色）；砍中出火花 + 血雾（≥20 伤害多一道刀弧）；弹反金色火花 + 光环 + 金色泛光；盾挡小火花；破防白色碎闪；受击血雾 + 屏幕泛红；翻滚起尘；瞬影斩起点终点蓝烟；落雷斩落地光柱 + 冲击环 + 裂地 + 尘土 | |
| scripts/boss.gd | 爪击时对应的手拖爪光（双手砸地的招不拖，像光柱）；爪击出弯月爪痕；重劈 / 扑击落地冲击环 + 裂地 + 尘土 + 加重震屏；横扫贴地一圈尘；二阶段咆哮红色大冲击环 + 屏幕泛红；死亡飘灰烬；二阶段爪光变红 | |
| tools/fx_shots.gd / .tscn（新） | 开窗口跑，12 个关键时刻截图存到 `user://fx_shots/`，最后打印帧时间 | |

测试：全套战斗测试数值不变（292 → 266 → 244 → 214，ALL DONE）。帧时间（1280×720，M4 Pro，开垂直同步）：加特效前平均 8.0ms / p99 16.7–17.9ms，加特效后 8.0ms / p99 16.7–18.6ms，没有可见差别；最差的那一帧（约 140ms）两边都有，是截图存盘造成的。

- 11-06 追加：地面光环（冲击环）亮边收细到原来约一半（`fx.gd` 的 ring 贴图 0.7–1.0 → 0.86–1.0，贴图 128 → 256 防锯齿）

## 2026-11-06 · 音效（第一批）

| File | Change | Why |
|---|---|---|
| assets/audio/sfx/（新，19 个 .ogg） | Freesound 的 CC0 音效（高质量试听版） | 出处、作者、链接都在 `assets/audio/CREDITS.md` |
| assets/audio/kenney/（新） | Kenney RPG Audio 里的 2 个布料声、2 个脚步 + License.txt | CC0；kenney.nl 拦脚本下载，从 OpenGameArt 上 Kenney 自己发的同款包拿的 |
| assets/audio/sfx/wind_loop.ogg.import | `loop=true` | 背景风声循环（在代码里 duplicate 再开 loop，退出时会报泄漏） |
| scripts/sfx.gd（新） | 音效管理节点（组 `sfx`）：名字 → 几个变体随机挑 + 音高随机抖；16 个 3D 播放器轮流用（镜头是听者）+ 8 个不分方向的；背景风声 | 每个文件按「最响的 0.1 秒」量过响度再定音量（原始素材差 20 多 dB） |
| scripts/main.gd | 生成 Sfx 节点 | |
| scripts/player.gd | 挥刀（第三下和反击是低沉的重挥）、砍中、反击重击、弹反、盾挡、破防、受击、死亡、翻滚 / 起跳布料声、完美闪避（降调破风）、落雷斩雷声 + 砸地 | |
| scripts/boss.gd | 每次抬爪破风声（横扫更低沉）、重劈 / 扑击起手低吼、落地砸地、二阶段咆哮叠一层压低的哭声、死亡 | |
| assets/env/CREDITS.md | 末尾指向音效出处 | |

测试：战斗测试数值不变（292 → 266 → 244 → 214，ALL DONE）；帧时间不变（平均 8.0ms）。无窗口测试退出时偶尔（约 1/7）报风声的 Ogg 播放对象泄漏：退出那一刻音频线程还拿着它，不影响游戏。
**还没听过**：我这边没法听声音，音量是按测出来的响度定的，需要 Xiaoting 实际玩一下再调。

- 11-06 追加：重劈 / 扑击起手的低吼换成 Monster snarl 3（pikachu09，CC0）；原来那个听着像风声（Xiaoting 反馈）
- 11-06 追加：低吼按 Xiaoting 选的换成 B：MonsterGrowl（yatoimtop，CC0）
- 11-06 追加：低吼原声结尾是硬切的，加了 1.2 秒淡出（`sfx.gd` 的 BANK 支持结尾淡出 / 起播位置）；砸地声跳过原声前 0.35 秒的空白；三连爪起手加短吼（Goblin Growl，qubodup），横扫起手加嘶吼（Monster snarl 3，pikachu09），都是 CC0

## 2026-11-06 · 延迟重劈：裂地更明显 + 震晕

| File | Change | Why |
|---|---|---|
| scripts/boss.gd | 重劈的判定加 `"quake": [5.5, 0.7]`：没被砸中、但站在落点 5.5 米内的地上 → 震晕 0.7 秒（不掉血）；砸地特效换成大裂坑 + 两道震波 + 碎石崩飞 + 大尘圈，震屏 0.5 → 0.9，砸地声叠两层 | Xiaoting 要重劈落地更有震动感 |
| scripts/player.gd | 新增 `receive_quake()`：进入受击硬直、头顶转星星、屏幕四周发暗、提示「震晕！」。跳起来、翻滚无敌、反击中、已经在硬直里都不受影响 | 给玩家留应对方法：跳 / 滚 |
| scripts/fx.gd | 裂纹贴图生成改成函数，多一张「大裂纹」（13 条更宽的裂缝 + 中间一个坑，裂缝红光更亮、留 4 秒左右）；新增碎石粒子池、`dizzy()` 头顶星星 | |
| tools/fx_shots.gd | 多两张图：13_quake、14_dizzy（站在 9 米外被震晕，确认不掉血） | |

测试：战斗测试数值不变；截图里被震晕、掉血 0；帧时间平均 8.0ms 不变。
- 11-06 追加：重劈 / 震晕特效换成 Kenney Particle Pack 的贴图（CC0，见 `assets/vfx/CREDITS.md`）：砸地改成落点闪光 + 翻滚烟尘（smoke_07，随机旋转、边飘边变大）+ 飞溅碎土（dirt_03）；去掉灰色小方块碎石（看着像积木）；震晕改成三颗黄色五角星绕头转 + 头顶旋涡 + 零星闪光（星星不做深度测试，不被模型挡住）。Xiaoting 反馈原来的粒子不生动

## 2026-11-06 · 背景音乐

| File | Change | Why |
|---|---|---|
| assets/audio/music/epic_boss_battle.wav（新，21 MB 原文件；导入后 QOA 约 4 MB） | Juhani Junkala「Epic Boss Battle」，CC0，原作就是无缝循环 | 出处见 assets/audio/CREDITS.md；备选还有 The Final Battle（skrjablin）、QaziJamJam（emmama），都是 CC0，等 Xiaoting 试听 |
| .import | `edit/loop_mode=2` 循环 | |
| scripts/sfx.gd | 开场 3 秒淡入到 -16 dB；`music_fade_out()` | 原曲平均 -8.5 dB，很响，压低垫在音效下面 |
| scripts/main.gd | 赢 / 输时音乐 2.5 秒淡出 | |
- 11-06 追加：背景音乐按 Xiaoting 选的换成 B：The Final Battle（skrjablin，CC0，Ogg 2.8 MB），音量 -10 dB 是估的；删掉 A 的 21 MB wav
- 11-06 追加：背景音乐 -10 → -4 dB（Xiaoting 试听说太小）
- 11-06 追加：重劈改成溅小石子：用拱门碎石那包石头（70_stylized_rocks）缩成 0.2 米的粒子网格，3 种形状；加了 GPUParticlesCollisionHeightField3D（只在 GPU 上算、只在挪动时重画），石子落地弹一下停住再缩没；Kenney 碎土贴图减到 12 个
- 11-06 追加：重劈的「白色水蒸气」：粒子材质没开 vertex_color_is_srgb，深褐色被当成线性色提亮成浅灰。所有非发光粒子都开了（尘土 / 血雾 / 碎土跟着变深一点）；重劈烟团也减量、贴地、更透明
- 11-06 追加：通用尘土（扑击落地、横扫、翻滚、落雷斩、二阶段咆哮）也从浅灰换成深褐色 + Kenney 烟团贴图（Xiaoting：扑击后也有白烟）
- 11-06 追加：翻滚脚下扬尘：起滚蹬地一团、翻滚中每 0.07 秒在脚下扬一小团往身后飘、收势往前扑一团（新粒子池 kick，Kenney 烟团贴图，褐色）；fx_shots 加 01b_roll_dust。帧时间 8.0ms / p99 16.7ms 不变
- 11-06 追加：主角砍中改成金色长火花（新粒子池 gold：48 个、0.8 米长、飞 7~15 m/s、0.65 秒、往两侧散开，加 Kenney 闪光）；修了所有火花都立成竖线的问题：材质上的 FIXED_Y 公告板换成 GPUParticles3D.transform_align = Z_BILLBOARD_Y_TO_VELOCITY，火花沿飞行方向拉长
- 11-06 追加：金色火花改成顺着挥剑方向扇形喷出：记剑尖最近 5 帧的位置（主角局部坐标，去掉身体移动），位移 = 挥剑方向，剑身 × 挥剑方向 = 扇面法线；发射器转到这个朝向，spread 40° + flatness 0.85 压成扇面；火花不做深度测试（不被 Boss 身体挡住）
- 11-06 追加：砍中的金色火花（像打铁）换成「暗红血花 + 少量橙红余烬」，仍按挥剑方向扇形甩出（fx.gd 的 slash_spray，粒子池 gash / ember_spray）；闪光改成暗红橙

## 2026-11-06 · 镜头与慢动作

| File | Change | Why |
|---|---|---|
| scripts/main.gd | 顿帧 / 慢动作合成一套：`_base_scale` 底速 + `_freeze()`，`hitstop(dur, then_scale, then_dur)` 可接慢放，`slowmo(..., prio, tint)` 带优先级；新增 `cam_punch` / `cam_quick_turn` / `_on_phase`；Boss 死后慢放 + 侧面镜头，约 2 秒后才 `show_end` | 原来慢动作里的顿帧被吞、慢动作结束强行回 1 倍；死亡没有收尾 |
| scripts/camera_rig.gd | 按系统时钟算真实时间；近身压迫镜头 `CLOSE_*`；`punch()` / `quick_turn()` / `frame_boss()` / `death_cam()`；方向按角度插值 | 慢动作时镜头不拖；瞬影斩转 180° 不穿零点 |
| scripts/player.gd | 弹反、反击打中、落雷斩打中改为顿帧接慢放 + 镜头往里冲；瞬影斩瞬移后快速转身 | |
| scripts/boss.gd | 去掉弹反时 Boss 这边重复的顿帧 | 会顶掉主角那边带慢放的顿帧 |
| tools/combat_test.gd | Boss 死后等结算出现（最多 2000 帧） | 结算延后约 2 秒 |
| tools/cam_shots.gd/.tscn | 新增：镜头截图 + 帧时间 | |

测试：全套战斗测试数值不变（292 → 266 → 244 → 214，ALL DONE）；2560×1440 窗口跑 cam_shots 平均 9.8 ms、p99 13.4 ms。

## 2026-11-06 · 镜头第二版（更夸张）+ 开场 Boss 亮相

| File | Change | Why |
|---|---|---|
| scripts/camera_rig.gd | 近身镜头加大（`CLOSE_*`、新增 `CLOSE_FOV` 70°）、推近加大、二阶段放低仰拍；新增 `intro()` / `intro_skip()` / `_intro_shot()` | Xiaoting：更夸张；开场亮相 |
| scripts/player.gd | 慢放加大；`cinematic` 期间不吃输入（`_physics_process` 拆成 `_state_step` / `_after_step`） | |
| scripts/main.gd | 二阶段 / 死亡慢放加大；`play_intro`、`_intro()` 时间轴、`_skip_intro()` | |
| scripts/boss.gd | `intro_hold`、`intro_roar()`、`head_pos()`（记下头骨骨骼） | |
| scripts/hud.gd | 上下黑边、大字 Boss 名，`cinematic()` / `show_title()` | |
| tools/*.gd | 测试 / 截图脚本跳过开场；`cam_shots` 加 `intro` 参数 | |

测试：战斗测试数值不变；2560×1440 平均 9.8 ms、p99 14.1 ms。

## 2026-11-06 · Boss 死亡推近 + 化成灰

| File | Change | Why |
|---|---|---|
| scripts/boss.gd | `_prepare_crumble()` / `_crumble()`：死后复制模型材质改成 ALPHA_HASH，先变暗变灰再一粒粒散掉；叠加层透余烬橙光并一起散掉；眼睛熄灭；`model_root` | Xiaoting：死亡要 zoom in 之后缓慢消亡 |
| scripts/camera_rig.gd | 死亡镜头从侧面 11 米慢慢推近到 6.5 米、抬高往下看，视角 62° → 44°；开场 / 死亡计时用不截断的真实时间 | |
| scripts/main.gd | 结算延后到约 7.5 秒 | |
| scripts/fx.gd | `ashes()` 多一个时长参数 | 余烬一直飘到化完 |
| tools/cam_shots.gd | 死亡拍 9 张 | |

测试：战斗测试数值不变。

## 2026-11-06 · 镜头第四版：贴近 + 主角偏左的弹性构图

| File | Change | Why |
|---|---|---|
| scripts/camera_rig.gd | 平时镜头 7.5 → 3.8 米、高 3.4 → 2.3 米；近身 3.6 / 3.0 米、64°；新增 `FRAME_*`：镜头和看向点一起平移到主角右边，主角横移时在画面里先偏、停下慢慢回左 | Xiaoting 参考魂类截图：镜头近、主角偏左、弹性范围 |
| tools/cam_shots.gd | 加左右跑的截图（02b ~ 02e） | |

测试：战斗测试数值不变；2560×1440 平均 10.6 ms、p99 18 ms（截图帧除外）。

## 2026-11-06 · 镜头第五版：背部高度仰拍

| File | Change | Why |
|---|---|---|
| scripts/camera_rig.gd | `HEIGHT` 2.3 → 1.3、`LOOK_HEIGHT` 2.0 → 1.9；近身 `CLOSE_DISTANCE` 3.4、`CLOSE_HEIGHT` 1.1、`CLOSE_LOOK_HEIGHT` 2.4、`CLOSE_LOOK_TO_BOSS` 0.25 | Xiaoting：从主角背部高度往上看，更有压迫感 |

测试：战斗测试数值不变；2560×1440 平均 9.1 ms、p99 14.8 ms。
