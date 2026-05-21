class_name Settlement
extends CanvasLayer

## Field-loop settlement screen.
## Brotato-style: pull 4 random modifier offerings, multi-buy with gold,
## "Return to Field" advances the run.

signal closed

const CARD_SCENE: PackedScene = preload("res://scenes/ui/modifier_card.tscn")
const OFFER_COUNT: int = 4

@onready var _settlement_label: Label = %SettlementLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _cards_container: HBoxContainer = %CardsContainer
@onready var _next_button: Button = %NextButton


func _enter_tree() -> void:
	# The settlement is the only interactive layer while the world is paused.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_settlement_label.text = GameState.field_region_summary()
	_refresh_gold_label()
	_spawn_offers()
	_next_button.pressed.connect(_on_next_pressed)
	EventBus.gold_changed.connect(_on_gold_changed)


func _spawn_offers() -> void:
	var offers: Array[ModifierData] = ModifierDB.get_random_modifiers(OFFER_COUNT)
	if offers.is_empty():
		_settlement_label.text = "%s (no offers - empty DB)" % GameState.field_region_summary()
		return
	for mod: ModifierData in offers:
		var card: ModifierCard = CARD_SCENE.instantiate()
		card.setup(mod)
		card.purchase_requested.connect(_on_card_purchase_requested)
		_cards_container.add_child(card)


func _on_card_purchase_requested(card: ModifierCard, mod: ModifierData) -> void:
	# Validate first — a stale/invalid card (e.g., companion already in party
	# from another offer in the same settlement) must not eat the player's gold.
	if not GameState.can_add_modifier(mod):
		card.mark_unaffordable_flash()
		return
	card.cost = GameState.modifier_purchase_cost(mod)
	if not GameState.spend_gold(card.cost):
		card.mark_unaffordable_flash()
		return
	GameState.add_modifier(mod)
	card.mark_purchased()


func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold_label()


func _refresh_gold_label() -> void:
	_gold_label.text = "%d G" % GameState.gold


func _on_next_pressed() -> void:
	closed.emit()
	queue_free()
