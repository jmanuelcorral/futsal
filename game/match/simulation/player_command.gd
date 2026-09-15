class_name PlayerCommand
extends RefCounted

const Rules = preload("res://match/simulation/match_rule_types.gd")

enum Action { NONE, PASS, SHOOT, TACKLE, SWITCH_TEAMMATE, DRIBBLE, KEEPER_THROW, CHOOSE_RESTART_SPOT }

const MAX_SEQUENCE: int = 2147483647

var actor_id: int = 0
var sequence: int = 0
var move: Vector2 = Vector2.ZERO
var aim: Vector2 = Vector2.ZERO
var sprint: bool = false
var close_control: bool = false
var action: Action = Action.NONE
var target_actor_id: int = -1
var shot_charge: float = 0.0
var shot_lift: float = 0.0
var restart_spot_choice: Rules.SpotChoice = Rules.SpotChoice.DEFAULT


func _init(id: int = 0, command_sequence: int = 0) -> void:
	actor_id = id
	sequence = command_sequence


func copy() -> PlayerCommand:
	var result: PlayerCommand = get_script().new(actor_id, sequence)
	result.move = move
	result.aim = aim
	result.sprint = sprint
	result.close_control = close_control
	result.action = action
	result.target_actor_id = target_actor_id
	result.shot_charge = shot_charge
	result.shot_lift = shot_lift
	result.restart_spot_choice = restart_spot_choice
	return result
