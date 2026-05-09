class_name ModifierPoolData
extends Resource

enum OfferMode { FIXED_ORDER, RANDOM_UNIQUE, RANDOM_WITH_REPLACEMENT }

@export var offer_mode: OfferMode = OfferMode.FIXED_ORDER
@export var offer_paths: PackedStringArray = []
