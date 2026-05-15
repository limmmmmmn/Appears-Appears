class_name Town2
extends CanvasLayer

## Streamlined between-stage town. Three zones, in descending size:
##   • Top:    4 big offer cards (the actual decision). Buying exhausts that
##             slot until the player rerolls or visits town again.
##   • Middle: a thin feed of party rows — one line each, "[NAME] [stats]
##             [• upgrade • upgrade ...]". Empty hero rows are hidden so the
##             feed only shows recruited members and grows organically.
##   • Bottom: utility bar — Reroll (small), and a prominent Continue.

signal closed

const CARD_SCENE: PackedScene = preload("res://scenes/ui/town2_card.tscn")
const CARD_SLOTS: int = 4
const REROLL_COST: int = 5

## Stat-card ids that don't get a Trello row — the owner's stat panel already
## shows the buff (ATK number going up), so an extra "ATK ×3" line would be
## redundant noise.
const SILENT_STAT_IDS: Dictionary = {
	&"atk_up": true,
	&"hero_atk_10p": true,
	&"mage_atk_10p": true,
	&"priest_atk_10p": true,
	&"thief_atk_10p": true,
	&"hp_up": true,
	&"agi_up": true,
}

@onready var _stage_label: Label = %StageLabel
@onready var _gold_label: Label = %GoldLabel
@onready var _top_zone: HBoxContainer = %TopZone
@onready var _reroll_button: Button = %RerollButton
@onready var _continue_button: Button = %ContinueButton
@onready var _slot_party: Town2Slot = %SlotParty
@onready var _slot_hero: Town2Slot = %SlotHero
@onready var _slot_mage: Town2Slot = %SlotMage
@onready var _slot_priest: Town2Slot = %SlotPriest
@onready var _slot_thief: Town2Slot = %SlotThief

var _cards: Array[Town2Card] = []
var _hero_slots_by_id: Dictionary = {}  # StringName -> Town2Slot (per-member)
var _all_slots: Array[Town2Slot] = []
var _title_override: String = ""


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_stage_label.text = _title_override if not _title_override.is_empty() else "Town"
	_heal_party_to_full()
	_refresh_gold_label()
	_register_slots()
	_seed_slots_from_active_modifiers()
	_build_top_cards()
	_refresh_offers()
	_continue_button.pressed.connect(_on_continue_pressed)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	_reroll_button.text = "Reroll  %d G" % REROLL_COST
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_mp_changed.connect(_on_party_member_mp_changed)
	EventBus.modifier_purchase_succeeded.connect(_on_modifier_purchase_succeeded)
	EventBus.modifier_purchase_failed.connect(_on_modifier_purchase_failed)
	_focus_first_available_card()


# ─── Slot wiring ──────────────────────────────────────────────────────
func _register_slots() -> void:
	_all_slots = [_slot_party, _slot_hero, _slot_mage, _slot_priest, _slot_thief]
	_hero_slots_by_id = {
		&"hero": _slot_hero,
		&"mage": _slot_mage,
		&"priest": _slot_priest,
		&"thief": _slot_thief,
	}
	for slot in _all_slots:
		slot.refresh()


## On entry, populate each slot's upgrade list from what the player already
## owns — modifiers persist across town visits, so the list should reflect
## that history rather than starting empty each time.
func _seed_slots_from_active_modifiers() -> void:
	for slot in _all_slots:
		slot.clear_upgrades()
	for mod: ModifierData in GameState.active_modifiers:
		_route_to_slot(mod)


## Place the modifier's title in its target slot. Companion cards intentionally
## skip routing — the recruited member's own slot transitioning from EMPTY to
## PRESENT *is* the visual feedback, and routing them all to PARTY would just
## stack duplicate "Recruit" lines. Plain stat-up cards (ATK +6, HP +10) also
## skip routing because the slot's stat panel already reflects the buff.
func _route_to_slot(mod: ModifierData) -> void:
	if mod.category == ModifierData.Category.COMPANION:
		return
	if SILENT_STAT_IDS.has(mod.id):
		return
	var owner_id: StringName = mod.required_party_member_id
	if owner_id == &"":
		_slot_party.add_upgrade(mod)
		return
	var slot: Town2Slot = _hero_slots_by_id.get(owner_id, null)
	if slot:
		slot.add_upgrade(mod)


func _refresh_all_slots() -> void:
	for slot in _all_slots:
		slot.refresh()


# ─── Card row ─────────────────────────────────────────────────────────
func _build_top_cards() -> void:
	_cards.clear()
	# Top zone is now cards-only — reroll lives in the bottom bar.
	for i in CARD_SLOTS:
		var card: Town2Card = CARD_SCENE.instantiate()
		card.purchase_requested.connect(_on_card_purchase_requested)
		_top_zone.add_child(card)
		_cards.append(card)


## Full random redraw — used on entry and on reroll. Each visible card is
## unique within the current draw to avoid the visual stutter of duplicates.
func _refresh_offers() -> void:
	var pool: Array[ModifierData] = _offerable_pool()
	pool.shuffle()
	for i in CARD_SLOTS:
		_cards[i].setup(pool[i] if i < pool.size() else null)


## Replace just one slot with a new offer the player doesn't already see in
## another card. Kept for future targeted redraws; purchases intentionally do
## not call this so the shop cannot refill forever.
func _redraw_card(card_index: int) -> void:
	var displayed: Dictionary = {}
	for i in CARD_SLOTS:
		if i == card_index:
			continue
		var c: Town2Card = _cards[i]
		if c.data:
			displayed[c.data.id] = true
	var candidates: Array[ModifierData] = []
	for mod: ModifierData in _offerable_pool():
		if not displayed.has(mod.id):
			candidates.append(mod)
	var slot: Town2Card = _cards[card_index]
	if candidates.is_empty():
		slot.setup(null)
	else:
		slot.setup(candidates.pick_random())


func _offerable_pool() -> Array[ModifierData]:
	var out: Array[ModifierData] = []
	for mod: ModifierData in ModifierDB.get_all():
		if ModifierDB.is_shop_offer(mod) and GameState.can_add_modifier(mod):
			out.append(mod)
	return out


# ─── Purchase flow ────────────────────────────────────────────────────
func _on_card_purchase_requested(_card: Town2Card, mod: ModifierData) -> void:
	EventBus.modifier_purchase_requested.emit(mod, _card)


func _on_modifier_purchase_succeeded(mod: ModifierData, source: Node) -> void:
	var card := source as Town2Card
	if card == null or not is_instance_valid(card):
		return
	_route_to_slot(mod)
	_refresh_all_slots()
	var idx: int = _cards.find(card)
	if idx >= 0:
		card.setup(null)
		_focus_first_available_card()


func _on_modifier_purchase_failed(_mod: ModifierData, source: Node) -> void:
	var card := source as Town2Card
	if card == null or not is_instance_valid(card):
		return
	card.mark_unaffordable_flash()


# ─── Reroll / Recovery ────────────────────────────────────────────────
func _on_reroll_pressed() -> void:
	if not GameState.spend_gold(REROLL_COST):
		_flash_red(_reroll_button)
		return
	_refresh_offers()
	_focus_first_available_card()


func _heal_party_to_full() -> void:
	for i in GameState.party_size():
		var max_hp: int = GameState.effective_max_hp(i)
		if GameState.party_hp[i] < max_hp:
			GameState.heal_party_member(i, max_hp - GameState.party_hp[i])
	GameState.restore_party_mp_to_full()


# ─── Reactive plumbing ────────────────────────────────────────────────
func _on_party_changed() -> void:
	_seed_slots_from_active_modifiers()
	_refresh_all_slots()


func _on_party_member_hp_changed(_index: int, _new_hp: int, _max_hp: int) -> void:
	_refresh_all_slots()


func _on_party_member_mp_changed(_index: int, _new_mp: int, _max_mp: int) -> void:
	_refresh_all_slots()


func _on_gold_changed(_new_gold: int) -> void:
	_refresh_gold_label()


func _refresh_gold_label() -> void:
	_gold_label.text = "%d G" % GameState.gold


# ─── Focus / arrow cursor ─────────────────────────────────────────────
func _focus_first_available_card() -> void:
	for card in _cards:
		if not card.disabled:
			card.grab_focus()
			return
	_continue_button.grab_focus()


func _focus_after_purchase(card_index: int) -> void:
	var same: Town2Card = _cards[card_index]
	if not same.disabled:
		same.grab_focus()
		return
	_focus_first_available_card()


func _flash_red(target: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(target, "modulate", Color(1, 0.4, 0.4, 1), 0.1)
	tween.tween_property(target, "modulate", Color.WHITE, 0.2)


func _on_continue_pressed() -> void:
	closed.emit()
	queue_free()
