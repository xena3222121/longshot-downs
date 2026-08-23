class_name Horse
extends Resource

## Persistent identity only. Race-day performance stats are rolled fresh
## per race (see race sim) and are NOT stored here — a horse's speed today
## says nothing about its speed next race.
@export var id: int
@export var horse_name: String
@export var jockey_name: String
@export var silk_primary: Color
@export var silk_secondary: Color
