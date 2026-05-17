class_name Town
extends CanvasLayer

## Streamlined between-stage town. Three zones, in descending size:
##   • Top:    4 big offer cards (the actual decision). Buying exhausts that
##             slot until the player rerolls or visits town again.
##   • Middle: a thin feed of party rows — one line each, "[NAME] [stats]
##             [• upgrade • upgrade ...]". Empty hero rows are hidden so the
##             feed only shows recruited members and grows organically.
##   • Bottom: utility bar — Reroll (small), and a prominent Continue.

signal closed

const CARD_SCENE: PackedScene = preload("res://scenes/ui/town_card.tscn")
const LEVEL_UP_STAT_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_stat_panel.tscn")
const LEVEL_UP_PANEL_SCENE: PackedScene = preload("res://scenes/ui/level_up_panel.tscn")
const LOOT_BOX_SCENE: PackedScene = preload("res://scenes/ui/loot_box.tscn")
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
@onready var _slot_party: TownSlot = %SlotParty
@onready var _slot_hero: TownSlot = %SlotHero
@onready var _slot_mage: TownSlot = %SlotMage
@onready var _slot_priest: TownSlot = %SlotPriest
@onready var _slot_thief: TownSlot = %SlotThief

var _cards: Array[TownCard] = []
var _hero_slots_by_id: Dictionary = {}  # StringName -> TownSlot (per-member)
var _all_slots: Array[TownSlot] = []
var _title_override: String = ""
var _stat_panel: LevelUpStatPanel
var _level_up_panel: LevelUpPanel
var _loot_box: LootBox
var _pending_level_up_choice_rounds: int = 0
var _settled_levels_gained: int = 0


func setup(title_override: String = "") -> void:
	_title_override = title_override


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


func _ready() -> void:
	_stage_label.text = _title_override if not _title_override.is_empty() else "Town"
	_settled_levels_gained = GameState.settle_deferred_party_level_ups(false)
	_heal_party_to_full()
	_refresh_gold_label()
	_register_slots()
	_seed_slots_from_active_modifiers()
	_continue_button.pressed.connect(_on_continue_pressed)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	_reroll_button.text = "Reroll  %d G" % REROLL_COST
	_set_shop_visible(false)
	EventBus.gold_changed.connect(_on_gold_changed)
	EventBus.party_changed.connect(_on_party_changed)
	EventBus.party_member_hp_changed.connect(_on_party_member_hp_changed)
	EventBus.party_member_mp_changed.connect(_on_party_member_mp_changed)
	EventBus.modifier_purchase_succeeded.connect(_on_modifier_purchase_succeeded)
	EventBus.modifier_purchase_failed.connect(_on_modifier_purchase_failed)
	if _settled_levels_gained > 0:
		call_deferred("_open_town_level_up_settlement")
	else:
		call_deferred("_open_loot_box_sequence")


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
	var slot: TownSlot = _hero_slots_by_id.get(owner_id, null)
	if slot:
		slot.add_upgrade(mod)


func _refresh_all_slots() -> void:
	for slot in _all_slots:
		slot.refresh()


# ─── Card row ─────────────────────────────────────────────────────────
func _open_shop() -> void:
	if _cards.is_empty():
		_build_top_cards()
	_set_shop_visible(true)
	_refresh_offers()
	_focus_first_available_card()


func _set_shop_visible(is_visible: bool) -> void:
	_top_zone.visible = is_visible
	_reroll_button.visible = is_visible
	_continue_button.visible = is_visible


func _build_top_cards() -> void:
	if not _cards.is_empty():
		return
	_cards.clear()
	# Top zone is now cards-only — reroll lives in the bottom bar.
	for i in CARD_SLOTS:
		var card: TownCard = CARD_SCENE.instantiate()
		card.purchase_requested.connect(_on_card_purchase_requested)
		_top_zone.add_child(card)
		_cards.append(card)


## Full random redraw — used on entry and on reroll. Each visible card is
## unique within the current draw to avoid the visual stutter of duplicates.
func _refresh_offers() -> void:
	var pool: Array[ModifierData] = _offerable_pool()
	pool.shuffle()
	_prioritize_field_movement_offer(pool)
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
		var c: TownCard = _cards[i]
		if c.data:
			displayed[c.data.id] = true
	var candidates: Array[ModifierData] = []
	for mod: ModifierData in _offerable_pool():
		if not displayed.has(mod.id):
			candidates.append(mod)
	var slot: TownCard = _cards[card_index]
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


func _prioritize_field_movement_offer(pool: Array[ModifierData]) -> void:
	var field_move: ModifierData = ModifierDB.get_by_id(GameState.FIELD_MOVEMENT_ID)
	if field_move == null or not GameState.can_add_modifier(field_move):
		return
	for i in pool.size():
		if pool[i] != null and pool[i].id == GameState.FIELD_MOVEMENT_ID:
			pool.remove_at(i)
			break
	pool.push_front(field_move)


# ─── Purchase flow ────────────────────────────────────────────────────
func _on_card_purchase_requested(_card: TownCard, mod: ModifierData) -> void:
	EventBus.modifier_purchase_requested.emit(mod, _card)


func _on_modifier_purchase_succeeded(mod: ModifierData, source: Node) -> void:
	var card := source as TownCard
	if card == null or not is_instance_valid(card):
		return
	_route_to_slot(mod)
	_refresh_all_slots()
	var idx: int = _cards.find(card)
	if idx >= 0:
		card.setup(null)
		_focus_first_available_card()


func _on_modifier_purchase_failed(_mod: ModifierData, source: Node) -> void:
	var card := source as TownCard
	if card == null or not is_instance_valid(card):
		return
	card.mark_unaffordable_flash()


# ─── Deferred Level Settlement ────────────────────────────────────────
func _open_town_level_up_settlement() -> void:
	if _settled_levels_gained <= 0:
		return
	_pending_level_up_choice_rounds = maxi(1, _settled_levels_gained)
	_stat_panel = LEVEL_UP_STAT_PANEL_SCENE.instantiate()
	_stat_panel.setup(_settled_levels_gained, GameState.last_level_up_auto_skills())
	add_child(_stat_panel)
	_stat_panel.confirmed.connect(_on_town_stat_panel_confirmed)
	_stat_panel.tree_exited.connect(func() -> void:
		_stat_panel = null
	)


func _on_town_stat_panel_confirmed() -> void:
	call_deferred("_open_town_level_up_offer_sequence")


func _open_town_level_up_offer_sequence() -> void:
	if _pending_level_up_choice_rounds <= 0:
		_seed_slots_from_active_modifiers()
		_refresh_all_slots()
		call_deferred("_open_loot_box_sequence")
		return
	_pending_level_up_choice_rounds -= 1
	var offers: Array[ModifierData] = GameState.level_up_card_offers()
	if offers.is_empty():
		call_deferred("_open_town_level_up_offer_sequence")
		return
	_level_up_panel = LEVEL_UP_PANEL_SCENE.instantiate()
	_level_up_panel.setup(-1, "파티", offers)
	add_child(_level_up_panel)
	_level_up_panel.modifier_chosen.connect(_on_town_level_up_modifier_chosen)
	_level_up_panel.tree_exited.connect(func() -> void:
		_level_up_panel = null
	)


func _on_town_level_up_modifier_chosen(_member_index: int, mod: ModifierData) -> void:
	if GameState.apply_level_up_modifier(mod):
		_route_to_slot(mod)
		_refresh_all_slots()
	call_deferred("_open_town_level_up_offer_sequence")


# ─── Loot Box ─────────────────────────────────────────────────────────
func _open_loot_box_sequence() -> void:
	var items: Array[ItemData] = GameState.inventory_items()
	if items.is_empty():
		_open_shop()
		return
	_loot_box = LOOT_BOX_SCENE.instantiate()
	_loot_box.setup(items, GameState.inventory_sell_value())
	add_child(_loot_box)
	_loot_box.closed.connect(_on_loot_box_closed)
	_loot_box.tree_exited.connect(func() -> void:
		_loot_box = null
	)


func _on_loot_box_closed() -> void:
	_open_shop()


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
	var same: TownCard = _cards[card_index]
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
