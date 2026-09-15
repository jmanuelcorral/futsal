class_name MatchEvent
extends RefCounted

const Rules = preload("res://match/simulation/match_rule_types.gd")

enum Kind { GOAL, PASS, SHOT, SAVE, RESTART, END, POSSESSION, TACKLE, BALL_CONTACT, FOCUS_CHANGED, RESTART_CHANGED, DRIBBLE, FOUL }

var event_id: int = 0
var tick: int = 0
var kind: Kind = Kind.RESTART
var actor_id: int = -1
var team_id: int = -1
var target_actor_id: int = -1
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
var score: Vector2i = Vector2i.ZERO
var success: bool = true
var reason: StringName = &""
var shot_charge: float = 0.0
var restart: Rules.RestartState = Rules.RestartState.new()
var launch_kind: Rules.LaunchKind = Rules.LaunchKind.FOOT_PASS
var gesture_kind: Rules.GestureKind = Rules.GestureKind.NONE
var foul_verdict: Rules.FoulVerdict = Rules.FoulVerdict.NONE
var contact_id: int = -1
var contact_point: Vector3 = Vector3.ZERO
