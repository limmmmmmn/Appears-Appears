class_name Town
extends CanvasLayer

## Between-stage town scene.
## Keeps the current 4-choice reward/shop flow, but presents it as a full
## town stop: INN heals the party, party members walk around in front of
## the buildings while the player browses cards.

signal closed

const CARD_SCENE: PackedScene = preload("res://scenes/ui/modifier_card.tscn")
const TOWN_NPC_SCENE: PackedScene = preload("res://scenes/town_npc.tscn")
const OFFER_COUNT: int = 4

## Where party NPCs walk: the green strip in front of the buildings.
const NPC_WALK_Y: float = 142.0
const NPC_WALK_X_MIN: float = 130.0
const NPC_WALK_X_MAX: float = 540.0
## Where new recruits "뿅!" pop in — center stage so the player sees it.
const NPC_RECRUIT_X: float = 320.0

@onready var _stage_label: Label = %StageLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _next_button: Button = %NextButton
@onready var _inn_button: Button = %InnHitArea
@onready var _npc_container: Node2D = %NpcContainer

## character_id -> TownNpc, so we can detect newly recruited members and only
## pop those in (existing NPCs keep walking).
var _npcs: Dictionary = {}
var _title_override: String = ""


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	# The world is paused while the party is in town, but town UI stays live.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	if _title_override.is_empty():
		_stage_label.text = "Field %d Cleared" % GameState.current_stage
	else:
		_stage_label.text = _title_override
	_refresh_gold_label()
	_spawn_offers()
	_sync_party_npcs(false)  # initial spawn — no pop animation
	_next_button.pressed.connect(_on_next_pressed)
	_inn_button.pressed.connect(_on_inn_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.modifier_purchase_succeeded.connect(_on_modifier_purchase_succeeded)
	EventBus.modifier_purchase_failed.connect(_on_modifier_purchase_failed)


# ─── Card offers ──────────────────────────────────────────────────────
func _spawn_offers() -> void:
	var offers: Array[ModifierData] = ModifierDB.get_shop_offers(OFFER_COUNT)
	EventBus.modifier_offered.emit(offers)
	if offers.is_empty():
		_stage_label.text = "%s (no market stock)" % _stage_label.text
		return
	for mod: ModifierData in offers:
		var card: ModifierCard = CARD_SCENE.instantiate()
		card.setup(mod)
		card.purchase_requested.connect(_on_card_purchase_requested)
		_cards_container.add_child(card)


func _on_card_purchase_requested(card: ModifierCard, mod: ModifierData) -> void:
	EventBus.modifier_purchase_requested.emit(mod, card)


func _on_modifier_purchase_succeeded(_mod: ModifierData, source: Node) -> void:
	var card := source as ModifierCard
	if card == null or not is_instance_valid(card):
		return
	var replacement: ModifierData = ModifierDB.get_random_offer_excluding(_displayed_card_ids())
	if replacement == null:
		card.mark_purchased()
		return
	card.setup(replacement)


func _on_modifier_purchase_failed(_mod: ModifierData, source: Node) -> void:
	var card := source as ModifierCard
	if card == null or not is_instance_valid(card):
		return
	card.mark_unaffordable_flash()


func _displayed_card_ids() -> Dictionary:
	var ids: Dictionary = {}
	for child in _cards_container.get_children():
		var card := child as ModifierCard
		if card and card.data:
			ids[card.data.id] = true
	return ids


# ─── Town NPCs ────────────────────────────────────────────────────────
## Drop one walking sprite per party member in front of the buildings.
## Existing NPCs are kept; only members not yet represented are added.
## When `pop` is true the new NPCs play a "뿅!" entrance and spawn at the
## recruit anchor — used when a card just added someone mid-town.
func _sync_party_npcs(pop: bool) -> void:
	for member: CharacterData in GameState.party:
		if _npcs.has(member.id):
			continue
		var npc: TownNpc = TOWN_NPC_SCENE.instantiate()
		npc.setup(member)
		npc.min_x = NPC_WALK_X_MIN
		npc.max_x = NPC_WALK_X_MAX
		var spawn_x: float
		if pop:
			spawn_x = NPC_RECRUIT_X
		else:
			spawn_x = randf_range(NPC_WALK_X_MIN, NPC_WALK_X_MAX)
		npc.position = Vector2(spawn_x, NPC_WALK_Y + randf_range(-3.0, 3.0))
		_npc_container.add_child(npc)
		_npcs[member.id] = npc
		if pop:
			npc.play_pop_in()


func _on_party_changed() -> void:
	# Recruit cards land here. Add an NPC (with pop) for any new member.
	_sync_party_npcs(true)


# ─── INN ──────────────────────────────────────────────────────────────
## Full party heal (revives any downed members). HUD reflects HP via
## party_member_hp_changed signals; we add a green pulse on the town NPCs
## so the player feels the action even if the HUD is glanced past.
func _on_inn_pressed() -> void:
	var any_healed: bool = false
	for i in GameState.party_size():
		var max_hp: int = GameState.effective_max_hp(i)
		if GameState.party_hp[i] < max_hp:
			GameState.heal_party_member(i, max_hp - GameState.party_hp[i])
			any_healed = true
	if any_healed:
		for npc: TownNpc in _npcs.values():
			npc.play_heal_pulse()


# ─── Gold readout ─────────────────────────────────────────────────────
func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold_label()


func _refresh_gold_label() -> void:
	_gold_label.text = "%d G" % GameState.gold


func _on_next_pressed() -> void:
	closed.emit()
	queue_free()
