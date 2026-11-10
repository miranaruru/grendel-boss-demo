# Sketchfab 模型

每个模型一个文件夹，Sketchfab 下载的 glTF 解压进去即可（scene.gltf + textures/）。用在哪里由 `scripts/env/tree_layout.gd` 的 `ZONE_MODELS` 和 `assets/env/tree_layout_planA.json`（a1_group / props）决定，授权和署名见 `assets/env/CREDITS.md`。

| 文件夹 | 用在 |
|---|---|
| old_tree/ | B 西北林 |
| dead_trees_demo/ | C 东北林、G 西（套装，自动切成单棵） |
| spooky_tree/ | D 倾斜孤树 |
| dead_trees/ | E 东南、H 外圈剪影（套装，自动切成单棵） |
| 4k_tree_stump_megascan/ | F 南远处 |
| burnt_stump/ | 树桩 S1–S3 |
| ruined_stone_bridge_broken_arch/ | A1 残拱 |
| the_ancient_gnarled_tree_3d_model_free/ | A1 王座古树 |
| japanese_stone_lantern_scan_2/ | A1 两侧石灯 |
| moss_covered_rock_pile/、rock_formation_scan_2/、stump_scan_5/ | 石台外的固定摆件（props） |

贴图导入时限制在 2048 像素以内（原图很多是 4K / 8K，加载要 7 秒多，限制后 1.6 秒）。
文件夹不存在 / 是空的 → 自动用代码生成的枯树 / 占位废墟顶替。
