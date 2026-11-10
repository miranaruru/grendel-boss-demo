@tool
class_name ScatterRule
extends Resource
## 一种环境物件怎么摆：数量、范围、间距、大小、扎堆程度。在 EnvScatter 的 rules 里编辑。

enum Kind { MODEL, DEAD_TREE }

@export var label := ""                       ## 备注名（只给人看）
@export var enabled := true
@export var kind: Kind = Kind.MODEL           ## MODEL = 用下面的模型文件；DEAD_TREE = 代码生成的枯树
@export_file("*.gltf", "*.glb", "*.tscn", "*.fbx") var scene_path := ""
@export_group("数量 / 范围")
@export var count_min := 5
@export var count_max := 8
@export var ring_min := 20.0                  ## 离竞技场中心最近多少米
@export var ring_max := 26.0                  ## 离竞技场中心最远多少米
@export var ignore_avoid := false             ## 允许放进战斗区域（只当装饰，没有碰撞）
@export_group("摆放")
@export var min_spacing := 2.0                ## 和其他物件至少隔多远（米）
@export_range(0.0, 1.0) var clustering := 0.0 ## 0 = 均匀撒；越大越跟着密度图 / 噪声扎堆，留出空地
@export var scale_min := 0.8
@export var scale_max := 1.2
@export var random_rotation := true
@export var y_offset := -0.05                 ## 往地里埋一点，避免浮空
@export var snow := true                      ## 盖积雪覆盖层
