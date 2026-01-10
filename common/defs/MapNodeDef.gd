class_name MapNodeDef
extends Resource

@export var id: String = ""
@export_enum("ENTRY", "STAGE", "TOWN", "BOSS", "END") var node_type: String = "STAGE"
@export var next_node_ids: Array[String] = []
@export var content_id: String = "" # 연결된 스테이지/마을 ID
