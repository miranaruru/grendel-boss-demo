# 犀渠 · 枯林之主 / Grendel · Lord of the Withered Wood

A 3D action boss-fight demo made in Godot 4.5.1 (GDScript). A sword-and-shield hero faces Grendel, a horned man-eating beast, in his lair in the withered wood. Each of the boss's four attacks has its own rhythm, and most of your damage comes from parries, perfect dodges and jump counters. The game supports English and Chinese (press **G** to switch).

## Agent Prompt

A prompt that lets an agent design and build a boss fight demo from a one-line request (e.g. "I want to make a Dark Souls-like boss fight"): [docs/boss_fight_agent_prompt.md](docs/boss_fight_agent_prompt.md)

## How to run

1. Install **Godot 4.5.1** (the standard build; the .NET build isn't needed): <https://godotengine.org/download/archive/4.5.1-stable/>
   Other versions are untested, and anything below 4.5 won't open the project (it uses 4.5 features).
2. Clone the repo. Large files (models, textures, audio) are stored in Git LFS, so install [Git LFS](https://git-lfs.com) first:
   ```bash
   git lfs install
   git clone <repo URL>
   ```
   If models show up as text files a few hundred bytes long after cloning, LFS didn't download them. Run `git lfs pull` inside the repo.
3. Open Godot, click **Import** in the project manager, and pick `project.godot` in the repo.
4. The first launch imports every asset, which takes a while. When it finishes, press **F5** to run (the main scene is `main.tscn`).

## Controls

| Keyboard / mouse | Gamepad | Action |
|---|---|---|
| WASD / arrow keys | Left stick | Move (camera-relative) |
| Space | A | Jump |
| Shift / L | B | Roll (invulnerable at the start) |
| J / left mouse | X | Attack (3-hit combo, can be cancelled into a roll) |
| K / right mouse | RB | Parry; hold to block |
| R | Start | Restart |
| G | | Switch English / Chinese |
| H | | Swap hands (sword and shield change sides) |
| T | | Debug: skip time ahead 3 hours (day/night cycle) |
| 1 / 2 / 3 / 4 | | Debug: choose the boss's next attack |

The camera faces the boss automatically.

## Combat basics

| Counter | Trigger | Effect |
|---|---|---|
| Cross Slash | Parry just before a parryable boss attack lands | Hitstop, the boss staggers, and the hero dashes in with a cross slash |
| Shadowstep Slash | Get attacked right as a roll starts (perfect dodge) | Slow motion; press attack to teleport behind the boss and slash |
| Thunderfall Slash | Jump over the boss's Low Sweep | Press attack in the air to fly at the boss and strike down |

| Boss attack | How to answer |
|---|---|
| Triple Claw Flurry | Parryable; the third claw comes deliberately late |
| Delayed Cleave | Not parryable; held for a long time before the slam, so roll late |
| Pounce | Parry or perfect-dodge |
| Low Sweep | Not parryable; jump over it, then Thunderfall Slash |

Normal attacks don't interrupt the boss, but enough accumulated damage staggers it briefly. Below half health it enters phase 2 and every attack gets faster.

## Project layout

```
project.godot / main.tscn   entry scene
scripts/                    game logic: main (entry, input, hitstop), player, boss, camera_rig, hud,
                            lair_builder (boss lair scene), arena_builder, day_night, fx, sfx, loc (EN/ZH text)
scenes/                     environment layout scenes
assets/                     models, animations, textures, audio, VFX (Git LFS)
design/                     layout sketches and data
docs/                       agent prompt
tools/                      helper scenes for screenshots and combat tests
```

## Asset credits

- Hero model: Mixamo; hero animations: Quaternius Universal Animation Library 1 & 2 (CC0)
- Boss model and animations: Mixamo
- Environment models and textures: Poly Haven (CC0) and Sketchfab; see `assets/env/CREDITS.md` and the `license.txt` in each Sketchfab asset folder
- Sound effects: Kenney, Freesound (CC0); see `assets/audio/CREDITS.md`
- VFX: Kenney; see `assets/vfx/CREDITS.md`

Third-party assets remain the property of their original authors and are used for this demo only.
