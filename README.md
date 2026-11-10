> **Boss fight agent prompt / 生成 Boss 战的 Agent Prompt：[docs/boss_fight_agent_prompt.md](docs/boss_fight_agent_prompt.md)**

# 犀渠 · 枯林之主 / Grendel · Lord of the Withered Wood

一个 3D 动作 Boss 战 Demo（Godot 4.5.1，GDScript）。双刀主角在枯林深处的巢穴里单挑狼人 Boss「犀渠」。Boss 的四种招式节奏各不相同，主要输出靠弹反、完美闪避和跳跃躲招后的反击。

A 3D action boss-fight demo made in Godot 4.5.1 (GDScript). A dual-blade hero faces the werewolf boss Grendel in his lair in the withered wood. Most of your damage comes from parries, perfect dodges and jump counters. The game supports Chinese and English (press **G** to switch).

## 运行 / How to run

1. 安装 **Godot 4.5.1**（标准版即可，不需要 .NET 版）：<https://godotengine.org/download/archive/4.5.1-stable/>
   其他版本没测过，4.5 以下打不开（项目用了 4.5 的特性）。
2. 克隆仓库。大文件（模型、贴图、音频）放在 Git LFS 里，需要先装 [Git LFS](https://git-lfs.com)：
   ```bash
   git lfs install
   git clone <仓库地址>
   ```
   如果克隆后模型是几百字节的文本文件，说明 LFS 没拉下来，在仓库里运行 `git lfs pull`。
3. 打开 Godot，在项目管理器里点 **导入（Import）**，选仓库里的 `project.godot`。
4. 第一次打开会导入所有素材，要等一会儿。导入完按 **F5** 运行（主场景是 `main.tscn`）。

English: install Godot 4.5.1 and Git LFS, clone the repo, import `project.godot` in the Godot project manager, wait for the first asset import to finish, then press F5.

## 操作 / Controls

| 键盘鼠标 | 手柄 | 动作 |
|---|---|---|
| WASD / 方向键 | 左摇杆 | 移动（相对镜头） |
| 空格 | A | 跳 |
| Shift / L | B | 翻滚（前段无敌） |
| J / 鼠标左键 | X | 攻击（三段连击，出刀后可翻滚取消） |
| K / 鼠标右键 | RB | 弹反；按住举盾 |
| R | Start | 重开 |
| G | | 切换中文 / English |
| H | | 换手（剑盾左右对调） |
| T | | 调试：时间往后跳 3 小时（昼夜循环） |
| 1 / 2 / 3 / 4 | | 调试：指定 Boss 下一招 |

镜头自动锁定 Boss。

## 战斗要点

| 反击 | 触发 | 效果 |
|---|---|---|
| 弹反 · 十字斩 | Boss「可弹反」的招式命中前一瞬按弹反 | 顿帧，Boss 硬直，主角冲上去十字斩 |
| 瞬影斩 | 翻滚刚开始时被攻击（完美闪避） | 慢动作，此时按攻击瞬移到 Boss 背后斩击 |
| 落雷斩 | 跳起躲过 Boss 的低身横扫 | 空中按攻击，飞向 Boss 下劈 |

| Boss 招式 | 应对 |
|---|---|
| 快速三连爪 | 可弹反，第三下故意晚 |
| 延迟重劈 | 不可弹反，憋很久才砸，晚一点再滚 |
| 扑击 | 可弹反 / 完美闪避 |
| 低身横扫 | 不可弹反，跳起来躲，接落雷斩 |

普通攻击打不断 Boss，但累计伤害会让它小硬直。血量低于一半进入二阶段，所有招式变快。

## 目录结构

```
project.godot / main.tscn   入口场景
scripts/                    游戏逻辑：main（入口、输入、顿帧）、player、boss、camera_rig、hud、
                            lair_builder（Boss 巢穴场景）、arena_builder、day_night、fx、sfx、loc（中英文）
scenes/                     环境布局场景
assets/                     模型、动画、贴图、音频、特效（Git LFS）
design/                     场景布局草图和数据
tools/                      截图 / 战斗测试用的辅助场景
```

## 素材来源

- 主角人偶和动作：Quaternius Universal Animation Library 1 & 2（CC0）
- Boss 模型和动作：Mixamo
- 环境模型和贴图：Poly Haven（CC0）和 Sketchfab，见 `assets/env/CREDITS.md` 和各 Sketchfab 素材目录下的 `license.txt`
- 音效：Kenney、Freesound（CC0），见 `assets/audio/CREDITS.md`
- 特效：Kenney，见 `assets/vfx/CREDITS.md`

第三方素材版权归原作者所有，仅用于本 Demo。
