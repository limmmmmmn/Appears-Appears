# scripts/defs/unit_data.gd
extends Resource
class_name UnitData

@export var name: String
# @export var job_class: JobClass # 추후 구현
@export var base_stats: StatsData
@export var sprite: Texture2D
@export var skills: Array[Resource] = [] # SkillData 구현 후 교체 권장 [cite: 35]
