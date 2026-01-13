extends Node

# 상태 저장 금지. 변수 만들면 규칙 위반.
signal inventory_changed()
signal gold_changed(new_gold: int)
signal party_changed()
signal equipment_changed(hero_id: String)
signal field_state_changed()
signal save_completed(slot: int)
signal load_completed(slot: int)
