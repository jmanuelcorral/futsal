extends SceneTree

const MatchAI = preload("res://match/simulation/match_ai.gd")
const Simulation = preload("res://match/simulation/match_simulation.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const Rules = preload("res://match/simulation/match_rules.gd")

const EXPECTED_CHECKS: int = 176
const EXPECTED_NEGATIVE_CASES: int = 51

var _checks: Array[Dictionary] = []
var _refusals: Array[Dictionary] = []
var _negative_cases: int = 0
var _decisions: int = 0
var _started_ms: int = 0
var _completed: bool = false
var _tuning: Tuning = Tuning.new()


func _initialize() -> void:
	_started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - _started_ms > 30000:
		push_error("AI tactics watchdog exceeded 30 seconds")
		quit(2)
	return false


func _run() -> void:
	_check("native_headless_jolt_sixty_hz_environment", DisplayServer.get_name() == "headless"
		and Engine.physics_ticks_per_second == Tuning.PHYSICS_HZ
		and ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics")
	_test_home_owner_facings()
	_test_recipient_choices()
	_test_possession_timing()
	_test_carry_support_and_recovery()
	_test_away_policy()
	_test_inactive_phases()
	_test_read_only_decisions()
	_test_restart_policy()
	_test_mirrored_play_and_hands()
	_test_recent_pass_history()
	_test_bounded_distribution()
	await _test_caller_filter(Setup.Mode.MICRO_1V1)
	await _test_caller_filter(Setup.Mode.PREVIEW_5V5)
	_check("production_caller_reports_zero_unexpected_command_refusals", _refusals.is_empty())
	var names: Dictionary[String, bool] = {}
	for item: Dictionary in _checks:
		names[String(item["name"])] = true
	_check("report_semantic_check_names_are_unique", names.size() == _checks.size())
	_check("report_negative_case_count_matches_contract", _negative_cases == EXPECTED_NEGATIVE_CASES)
	_check("report_semantic_case_count_matches_contract", _checks.size() + 1 == EXPECTED_CHECKS)
	_completed = true
	_finish()


func _test_home_owner_facings() -> void:
	var facings: Array[Vector2] = [
		Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2.UP, Vector2(-1, -1).normalized(),
		Vector2.LEFT, Vector2(-1, 1).normalized(), Vector2.DOWN, Vector2(1, 1).normalized(),
	]
	var directions: Array[String] = ["east", "northeast", "north", "northwest", "west", "southwest", "south", "southeast"]
	var roles: Dictionary[int, String] = {0: "field", 2: "keeper", 4: "left_support", 6: "right_support", 8: "cover"}
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		var home_ids: Array[int] = [0, 2]
		if mode == Setup.Mode.PREVIEW_5V5:
			home_ids.append_array([4, 6, 8])
		for id: int in home_ids:
			for index: int in facings.size():
				var selected: int = 2 if id == 0 else 0
				var state: Snapshot = _fixture(mode, id, selected)
				_clear_opponents(state)
				state.actor(id).position = Vector3(16, 0, 0)
				state.actor(id).forward = Vector3(facings[index].x, 0, facings[index].y)
				state.actor(selected).position = Vector3(12, 0, 4)
				_set_owner(state, id)
				var command: Command = _decide(state, id, 2.0)
				_check("%s_home_%s_facing_%s_passes_to_selected_human_without_finishing" % [
					_mode_name(mode), roles[id], directions[index]],
					_is_pass_to(command, state, selected) and _valid_home_command(command, state.actor(id)))


func _test_recipient_choices() -> void:
	var state: Snapshot = _passing_fixture()
	_check("safe_selected_human_has_priority_over_nearer_ai_outlet",
		_is_pass_to(_decide(state, 4, 2.0), state, 0))

	state = _passing_fixture()
	state.actor(1).position = Vector3(3, 0, 2)
	_check("blocked_human_lane_selects_safe_explicit_alternate",
		_is_pass_to(_decide(state, 4, 2.0), state, 6), true)

	state = _passing_fixture()
	state.actor(1).position = state.actor(0).position + Vector3(0.5, 0, 0)
	_check("pressured_human_receiver_is_not_a_safe_pass_target",
		_is_pass_to(_decide(state, 4, 2.0), state, 6), true)

	state = _passing_fixture()
	state.actor(0).position = Vector3(20.3, 0, 0)
	_check("human_beyond_goal_line_cannot_disguise_a_shot_as_a_pass",
		_is_pass_to(_decide(state, 4, 2.0), state, 6), true)

	state = _passing_fixture()
	state.actor(0).position = Vector3(8, 0, 0)
	state.actor(6).position = Vector3(4, 0, 0)
	_check("intervening_teammate_becomes_explicit_receiver_instead_of_false_human_target",
		_is_pass_to(_decide(state, 4, 2.0), state, 6), true)

	state = _passing_fixture()
	state.actor(0).position = Vector3(18, 0, 0)
	state.actor(1).position = state.actor(0).position
	state.actor(6).position = Vector3(4, 0, 4)
	state.actor(8).position = Vector3(4, 0, -4)
	var first: Command = _decide(state, 4, 2.0)
	state.actors.reverse()
	var reversed: Command = _decide(state, 4, 2.0)
	_check("equal_alternate_scores_use_actor_id_not_snapshot_iteration_order",
		_is_pass_to(first, state, 6) and _is_pass_to(reversed, state, 6))

	state = _fixture(Setup.Mode.PREVIEW_5V5, 2)
	_clear_opponents(state)
	state.actor(0).position = Vector3(14, 0, 6)
	_check("keeper_uses_safe_field_outlet_when_human_is_out_of_pass_range",
		_is_pass_to(_decide(state, 2, _tuning.keeper_return_delay), state, 6), true)

	state = _passing_fixture()
	state.actor(0).position = Vector3(12, 0, 0)
	state.actor(1).position = state.actor(0).position
	state.actor(6).position = Vector3(4, 0, 4)
	state.actor(8).position = Vector3(2, 0, -4)
	state.actor(7).position = state.actor(8).position
	first = _decide(state, 4, 2.0)
	_set_owner(state, 6)
	var return_command: Command = _decide(state, 6, 1.2)
	_check("alternate_reception_does_not_ping_pong_without_a_new_human_lane_or_outlet",
		first.action == Command.Action.PASS and first.target_actor_id == 6
		and return_command.action == Command.Action.NONE and return_command.target_actor_id == -1
		and not return_command.move.is_zero_approx(), true)

	state = _passing_fixture()
	state.selected_actor_id = 1
	_check("opponent_id_cannot_be_selected_as_a_friendly_pass_receiver",
		_is_pass_to(_decide(state, 4, 2.0), state, 0), true)

	state = _passing_fixture()
	state.actor(0).position = Vector3(1, 0, 0)
	state.actor(6).position = Vector3(-2, 0, 4)
	_check("crowded_short_human_pass_uses_a_safe_alternate_with_an_onward_lane",
		_is_pass_to(_decide(state, 4, 2.0), state, 6), true)


func _test_possession_timing() -> void:
	var state: Snapshot = _passing_fixture()
	_check("field_keeps_ball_until_thirty_six_possession_ticks",
		_decide(state, 4, 35.0 / 60.0).action == Command.Action.NONE, true)
	_check("field_can_pass_after_thirty_six_possession_ticks",
		_is_pass_to(_decide(state, 4, 36.0 / 60.0), state, 0))
	state.actor(4).action_cooldown = 0.01
	_check("active_action_cooldown_blocks_even_a_settled_safe_pass",
		_decide(state, 4, 2.0).action == Command.Action.NONE, true)
	state.actor(4).action_cooldown = 0.0
	_check("new_reception_resets_settling_instead_of_repeating_same_ball_pass",
		_decide(state, 4, 0.0).action == Command.Action.NONE, true)

	state = _fixture(Setup.Mode.MICRO_1V1, 2)
	_clear_opponents(state)
	_check("micro_keeper_waits_for_existing_return_delay",
		_decide(state, 2, 35.0 / 60.0).action == Command.Action.NONE, true)
	_check("micro_keeper_returns_to_selected_field_at_existing_return_delay",
		_is_pass_to(_decide(state, 2, 36.0 / 60.0), state, 0))
	_tuning.keeper_return_delay = 1.25
	_check("keeper_honours_configured_longer_return_delay",
		_decide(state, 2, 74.0 / 60.0).action == Command.Action.NONE, true)
	_check("keeper_passes_at_configured_longer_return_delay",
		_is_pass_to(_decide(state, 2, 75.0 / 60.0), state, 0))
	_tuning.keeper_return_delay = 0.6

	state = _passing_fixture()
	state.actor(1).position = Vector3(3, 0, 2)
	_check("ai_to_ai_outlet_waits_longer_than_human_delivery",
		_decide(state, 4, 71.0 / 60.0).action == Command.Action.NONE, true)
	_check("settled_ai_to_ai_outlet_executes_after_seventy_two_ticks",
		_is_pass_to(_decide(state, 4, 72.0 / 60.0), state, 6))


func _test_carry_support_and_recovery() -> void:
	var state: Snapshot = _blocked_near_goal()
	var command: Command = _decide(state, 4, 1.5)
	_check("blocked_field_owner_retreats_laterally_instead_of_entering_goal",
		_is_controlled_carry(command) and command.move.x < 0.0 and command.aim.x < 0.0, true)

	state = _fixture(Setup.Mode.MICRO_1V1, 2)
	state.actor(0).position = Vector3(-10, 0, 0)
	state.actor(1).position = Vector3(-14, 0, 0)
	command = _decide(state, 2, 1.5)
	_check("blocked_keeper_carries_laterally_without_free_goalward_pass",
		_is_controlled_carry(command) and is_zero_approx(command.move.x) and absf(command.move.y) > 0.5, true)

	state = _blocked_near_goal()
	state.actor(4).position.z = 8.5
	_set_owner(state, 4)
	state.actor(0).position = Vector3(11, 0, 8.5)
	state.actor(1).position = Vector3(14, 0, 8.5)
	state.actor(6).position = Vector3(11, 0, 7)
	state.actor(5).position = Vector3(14, 0, 7.75)
	command = _decide(state, 4, 1.5)
	_check("blocked_sideline_owner_turns_inward_instead_of_running_out",
		_is_controlled_carry(command) and command.move.x < 0.0 and command.move.y < 0.0, true)

	state = _fixture(Setup.Mode.MICRO_1V1, 0, 2)
	state.actor(0).position = Vector3(-18, 0, 0)
	state.actor(2).position = Vector3(-18.5, 0, 0)
	_set_owner(state, 0)
	command = _decide(state, 0, 1.5)
	_check("field_owner_near_own_goal_escapes_area_instead_of_back_carrying_into_net",
		_is_controlled_carry(command) and command.move.x > 0.0, true)

	state = _fixture(Setup.Mode.PREVIEW_5V5, 0)
	state.actor(0).position = Vector3(18, 0, 0)
	state.actor(4).position = Vector3(17, 0, 0)
	state.actor(4).spawn_position = state.actor(4).position
	_set_owner(state, 0)
	command = _decide(state, 4, 0.0)
	_check("friendly_support_leaves_attacking_goal_area_and_offers_width",
		command.action == Command.Action.NONE and command.move.x < 0.0 and command.move.y < 0.0)

	state = _fixture(Setup.Mode.MICRO_1V1, 2, 2)
	state.actor(0).position = Vector3(-17, 0, 0)
	state.actor(0).spawn_position = state.actor(0).position
	command = _decide(state, 0, 0.0)
	_check("micro_field_supports_human_keeper_outside_defensive_goal_area",
		command.action == Command.Action.NONE and command.move.x > 0.0)

	state = _fixture(Setup.Mode.MICRO_1V1, -1, 2)
	state.actor(0).position = Vector3.ZERO
	state.ball_position = Vector3(3, 0.12, 3)
	command = _decide(state, 0, 0.0)
	_check("micro_free_ball_recovery_remains_active_and_never_shoots",
		command.action == Command.Action.NONE and command.move.x > 0.0 and command.move.y > 0.0)

	state = _fixture(Setup.Mode.PREVIEW_5V5, -1)
	state.actor(0).position = Vector3(0.8, 0, 0)
	state.actor(4).position = Vector3.ZERO
	state.ball_position = Vector3(1, 0.12, 0)
	var chaser: Command = _decide(state, 4, 0.0)
	var supporter: Command = _decide(state, 6, 0.0)
	_check("preview_effective_ai_chaser_recovers_while_other_field_player_supports",
		chaser.close_control and chaser.move.x > 0.0 and chaser.action == Command.Action.NONE
		and not supporter.close_control and supporter.action == Command.Action.NONE)

	state = _fixture(Setup.Mode.MICRO_1V1, 1, 2)
	state.actor(0).position = Vector3.ZERO
	state.actor(1).position = Vector3(0.8, 0, 0)
	state.ball_position = Vector3(0.6, 0.12, 0)
	command = _decide(state, 0, 0.0)
	_check("home_field_can_challenge_opponent_possession_without_finishing",
		command.action == Command.Action.TACKLE and command.shot_charge == 0.0 and command.shot_lift == 0.0)


func _test_away_policy() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		var ids: Array[int] = [1]
		if mode == Setup.Mode.PREVIEW_5V5:
			ids.append_array([5, 7, 9])
		for id: int in ids:
			var state: Snapshot = _fixture(mode, id)
			state.actor(id).position = Vector3(-14, 0, 0)
			_set_owner(state, id)
			var command: Command = _decide(state, id, 0.0)
			_check("%s_away_field_%d_retains_original_shot_and_charge" % [_mode_name(mode), id],
				command.action == Command.Action.SHOOT and is_equal_approx(command.shot_charge, 0.72)
				and is_equal_approx(command.shot_lift, 0.12) and command.move.x < 0.0)
			state.actor(id).position = Vector3(4, 0, 0)
			_set_owner(state, id)
			command = _decide(state, id, 0.0)
			_check("%s_away_field_%d_still_carries_towards_goal_from_distance" % [_mode_name(mode), id],
				command.action == Command.Action.NONE and command.move.x < -0.9 and command.aim.x < -0.9)
		var keeper_state: Snapshot = _fixture(mode, 3)
		var keeper_command: Command = _decide(keeper_state, 3, _tuning.keeper_return_delay)
		var receiver_id: int = 1 if mode == Setup.Mode.MICRO_1V1 else 9
		var offset: Vector3 = keeper_state.actor(receiver_id).position - keeper_state.actor(3).position
		_check("%s_away_keeper_preserves_original_field_return" % _mode_name(mode),
			keeper_command.action == Command.Action.PASS and keeper_command.target_actor_id == receiver_id
			and keeper_command.aim.is_equal_approx(Vector2(offset.x, offset.z).normalized()))


func _test_inactive_phases() -> void:
	var phases: Dictionary[Snapshot.Phase, String] = {
		Snapshot.Phase.READY: "ready", Snapshot.Phase.GOAL_PAUSE: "goal_pause",
		Snapshot.Phase.RESTART_PAUSE: "restart_pause", Snapshot.Phase.PAUSED: "paused",
		Snapshot.Phase.FINISHED: "finished",
	}
	for phase: Snapshot.Phase in phases:
		var state: Snapshot = _passing_fixture()
		state.phase = phase
		var command: Command = _decide(state, 4, 3.0)
		_check("home_playing_policy_is_inert_during_" + phases[phase],
			command.action == Command.Action.NONE and command.target_actor_id == -1
			and command.move.is_zero_approx() and command.aim.is_zero_approx(), true)


func _test_read_only_decisions() -> void:
	var state: Snapshot = _passing_fixture()
	var before: Array = _fingerprint(state)
	var parameters: Array = [_tuning.move_speed, _tuning.ai_interval, _tuning.action_cooldown, _tuning.keeper_return_delay]
	var first: Command = _decide(state, 4, 2.0)
	var second: Command = _decide(state, 4, 2.0)
	_check("policy_does_not_mutate_snapshot_selection_sequences_or_ai_intent", before == _fingerprint(state))
	_check("policy_does_not_mutate_shared_tuning",
		parameters == [_tuning.move_speed, _tuning.ai_interval, _tuning.action_cooldown, _tuning.keeper_return_delay])
	first.target_actor_id = -1
	first.move = Vector2.ZERO
	_check("identical_snapshot_decisions_are_detached_and_keep_next_actor_sequence",
		first != second and _is_pass_to(second, state, 0)
		and second.sequence == state.actor(4).last_command_sequence + 1)


func _test_restart_policy() -> void:
	var kinds: Dictionary[Types.RestartKind, String] = {
		Types.RestartKind.KICK_IN: "kick_in", Types.RestartKind.CORNER: "corner",
		Types.RestartKind.GOAL_CLEARANCE: "goal_clearance", Types.RestartKind.DIRECT_FREE_KICK: "direct_free_kick",
		Types.RestartKind.INDIRECT_FREE_KICK: "indirect_free_kick", Types.RestartKind.PENALTY_6M: "penalty",
		Types.RestartKind.ACCUMULATED_FREE_KICK: "sixth",
	}
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		var prefix: String = _mode_name(mode) + "_restart_"
		for kind: Types.RestartKind in kinds:
			var state: Snapshot = _restart_fixture(mode, kind, Snapshot.Team.AWAY)
			var command: Command = _decide(state, state.restart.taker_actor_id, 0.0)
			var mandatory: bool = true
			if kind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
				mandatory = command.action == Command.Action.SHOOT
			elif kind == Types.RestartKind.GOAL_CLEARANCE:
				mandatory = command.action == Command.Action.KEEPER_THROW
			_check(prefix + kinds[kind] + "_effective_away_taker_uses_legal_launch",
				mandatory and _legal_restart_launch(command, state))
		var state: Snapshot = _restart_fixture(mode, Types.RestartKind.CORNER, Snapshot.Team.AWAY)
		state.tick = state.restart.ready_tick + _tuning.ai_restart_delay_ticks - 1
		_check(prefix + "waits_for_fixed_authoritative_ready_interval",
			_decide(state, state.restart.taker_actor_id, 0.0).action == Command.Action.NONE, true)
		state.tick = state.restart.deadline_tick
		_check(prefix + "never_launches_at_or_after_deadline",
			_decide(state, state.restart.taker_actor_id, 0.0).action == Command.Action.NONE, true)
		state = _restart_fixture(mode, Types.RestartKind.CORNER, Snapshot.Team.AWAY)
		state.ai_actor_ids.clear()
		_check(prefix + "does_not_enable_suspended_away_ai",
			_decide(state, state.restart.taker_actor_id, 0.0).action == Command.Action.NONE
			and state.ai_actor_ids.is_empty(), true)
		state = _restart_fixture(mode, Types.RestartKind.GOAL_CLEARANCE, Snapshot.Team.HOME)
		_check(prefix + "home_keeper_taker_waits_for_human_control",
			_decide(state, state.restart.taker_actor_id, 5.0).action == Command.Action.NONE, true)
		state = _restart_fixture(mode, Types.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.HOME)
		state.selected_actor_id = 2
		state.ai_actor_ids.append(state.restart.taker_actor_id)
		_check(prefix + "home_field_taker_never_automatically_finishes",
			_decide(state, state.restart.taker_actor_id, 5.0).action == Command.Action.NONE, true)
		for stage: Types.RestartStage in [Types.RestartStage.STOPPED, Types.RestartStage.PLACEMENT]:
			state = _restart_fixture(mode, Types.RestartKind.GOAL_CLEARANCE, Snapshot.Team.AWAY)
			state.restart.stage = stage
			var command: Command = _decide(state, state.restart.taker_actor_id, 5.0)
			_check(prefix + ("stopped" if stage == Types.RestartStage.STOPPED else "placement") + "_has_no_ai_launch_or_movement",
				command.action == Command.Action.NONE and command.move.is_zero_approx(), true)
		state = _restart_fixture(mode, Types.RestartKind.PENALTY_6M, Snapshot.Team.AWAY)
		state.tick = state.restart.ready_tick + 300
		_check(prefix + "ordinary_penalty_remains_executable_after_four_seconds",
			_legal_restart_launch(_decide(state, state.restart.taker_actor_id, 0.0), state))
		state = _restart_fixture(mode, Types.RestartKind.DIRECT_FREE_KICK, Snapshot.Team.AWAY)
		var defender_id: int = 2 if mode == Setup.Mode.MICRO_1V1 else 4
		var defender: Command = _decide(state, defender_id, 0.0)
		var speed: float = _tuning.keeper_speed if state.actor(defender_id).role == Snapshot.Role.KEEPER else _tuning.move_speed
		var displacement: Vector3 = Vector3(defender.move.x, 0.0, defender.move.y) * speed / Tuning.PHYSICS_HZ
		_check(prefix + "non_taker_support_respects_motion_constraints_and_cannot_tackle",
			defender.action == Command.Action.NONE and displacement.is_equal_approx(
				Rules.constrain_displacement(defender_id, displacement, state, _tuning)))
		state = _restart_fixture(mode, Types.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.AWAY)
		state.restart.has_spot_choice = true
		state.restart.offence_spot = Vector3(-12, Tuning.BALL_RADIUS, 0)
		state.restart.spot_choice = Types.SpotChoice.TEN_METRE
		state.tick = state.restart.ready_tick + 18
		var choice: Command = _decide(state, state.restart.taker_actor_id, 0.0)
		_check(prefix + "sixth_chooses_legal_closer_central_offence_spot_once",
			choice.action == Command.Action.CHOOSE_RESTART_SPOT
			and choice.restart_spot_choice == Types.SpotChoice.OFFENCE_SPOT and choice.target_actor_id == -1)
		state = _restart_fixture(mode, Types.RestartKind.ACCUMULATED_FREE_KICK, Snapshot.Team.AWAY)
		state.period_state = Types.PeriodState.EXTENDED_KICK
		state.extended_restart_id = state.restart.id
		state.tick = state.restart.deadline_tick
		_check(prefix + "expired_extended_kick_does_not_start_another_attack",
			_decide(state, state.restart.taker_actor_id, 0.0).action == Command.Action.NONE, true)


func _test_mirrored_play_and_hands() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for id: int in [0, 2]:
			var selected: int = 2 if id == 0 else 0
			var state: Snapshot = _fixture(mode, id, selected, Setup.TrainingExercise.CORNER_NEG_X_NEG_Z)
			_clear_opponents(state)
			state.actor(id).position = Vector3(-16, 0, 0)
			state.actor(id).attack_direction = Vector3.RIGHT
			state.actor(id).forward = Vector3.LEFT
			state.actor(selected).position = Vector3(-12, 0, 4)
			for teammate: Snapshot.ActorSnapshot in state.actors:
				if teammate.team_id == Snapshot.Team.HOME and teammate.actor_id not in [id, selected]:
					teammate.position = Vector3(14, 0, float(teammate.actor_id) - 5.0)
			_set_owner(state, id)
			_check("%s_mirrored_home_%s_pass_uses_exercise_not_stale_actor_direction" % [
				_mode_name(mode), "keeper" if id == 2 else "field"],
				_is_pass_to(_decide(state, id, 2.0), state, selected))
		var state: Snapshot = _fixture(mode, 0, 2, Setup.TrainingExercise.CORNER_NEG_X_NEG_Z)
		state.actor(0).position = Vector3(-17, 0, 0)
		state.actor(0).attack_direction = Vector3.RIGHT
		state.actor(0).forward = Vector3.LEFT
		state.actor(2).position = Vector3(-18, 0, 0)
		for teammate: Snapshot.ActorSnapshot in state.actors:
			if teammate.team_id == Snapshot.Team.HOME and teammate.actor_id not in [0, 2]:
				teammate.position = Vector3(14, 0, float(teammate.actor_id) - 5.0)
		_set_owner(state, 0)
		var carry: Command = _decide(state, 0, 1.5)
		_check(_mode_name(mode) + "_mirrored_blocked_owner_retreats_away_from_negative_goal",
			_is_controlled_carry(carry) and carry.move.x > 0.0, true)
		state = _fixture(mode, 2)
		_clear_opponents(state)
		# Keep the human outlet clear of the preview's central teammate.
		state.actor(0).position = Vector3(-12.0, 0.0, 4.0)
		state.actor(2).ball_in_hands = true
		var release: Command = _decide(state, 2, _tuning.keeper_return_delay)
		_check(_mode_name(mode) + "_live_keeper_hands_use_throw_without_changing_return_delay",
			release.action == Command.Action.KEEPER_THROW and release.target_actor_id == 0
			and release.shot_charge == 0.0 and release.shot_lift == 0.0)


func _test_recent_pass_history() -> void:
	var state: Snapshot = _passing_fixture()
	state.actor(1).position = Vector3(3, 0, 2)
	state.last_pass_actor_id = 6
	state.last_pass_target_actor_id = 4
	state.last_pass_tick = state.tick - 12
	var command: Command = _decide(state, 4, 2.0)
	_check("recent_ai_passer_is_not_immediately_selected_for_return_loop",
		command.target_actor_id != 6 and command.action != Command.Action.SHOOT, true)
	state.last_pass_tick = state.tick - 120
	_check("previous_passer_becomes_eligible_again_after_recycle_interval",
		_is_pass_to(_decide(state, 4, 2.0), state, 6))


func _test_bounded_distribution() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		var owner: int = 0 if mode == Setup.Mode.MICRO_1V1 else 4
		var human: int = 2 if mode == Setup.Mode.MICRO_1V1 else 0
		var state: Snapshot = _fixture(mode, owner, human)
		_clear_opponents(state)
		for teammate: Snapshot.ActorSnapshot in state.actors:
			if teammate.team_id == Snapshot.Team.HOME and teammate.actor_id not in [owner, human]:
				teammate.position = Vector3(-18, 0, float(teammate.actor_id) - 4.0)
		state.actor(owner).position = Vector3(17, 0, 0)
		state.actor(human).position = Vector3(11, 0, 2)
		state.actor(1).position = Vector3(14, 0, 1)
		_set_owner(state, owner)
		_check(_mode_name(mode) + "_blocked_owner_protects_ball_before_distribution_deadline",
			_is_controlled_carry(_decide(state, owner, 119.0 / 60.0)), true)
		_check(_mode_name(mode) + "_blocked_owner_attempts_explicit_human_pass_after_bounded_wait",
			_is_pass_to(_decide(state, owner, 120.0 / 60.0), state, human))
		state = _fixture(mode, 2)
		_clear_opponents(state)
		state.actor(0).position = Vector3(-10, 0, 0)
		state.actor(1).position = Vector3(-14, 0, 0)
		state.actor(2).ball_in_hands = true
		for teammate: Snapshot.ActorSnapshot in state.actors:
			if teammate.team_id == Snapshot.Team.HOME and teammate.actor_id not in [0, 2]:
				teammate.position = Vector3(14, 0, float(teammate.actor_id) - 5.0)
		var release: Command = _decide(state, 2, 2.0)
		_check(_mode_name(mode) + "_blocked_keeper_eventually_distributes_with_hands_to_real_receiver",
			release.action == Command.Action.KEEPER_THROW and release.target_actor_id == 0
			and release.shot_charge == 0.0 and release.shot_lift == 0.0)
	var state: Snapshot = _passing_fixture()
	state.actor(1).position = state.actor(0).position
	state.actor(6).position = Vector3(-4, 0, -4)
	_check("safe_backward_outlet_is_deferred_during_initial_anti_ping_pong_window",
		_decide(state, 4, 119.0 / 60.0).action == Command.Action.NONE, true)
	_check("bounded_distribution_targets_human_instead_of_indefinite_backward_ai_circulation",
		_is_pass_to(_decide(state, 4, 120.0 / 60.0), state, 0))


func _test_caller_filter(mode: Setup.Mode) -> void:
	var simulation: Simulation = Simulation.new()
	root.add_child(simulation)
	simulation.command_rejected.connect(func(id: int, code: Error, message: String) -> void:
		_refusals.append({"actor_id": id, "code": code, "message": message}))
	var setup: Setup = Setup.new() if mode == Setup.Mode.MICRO_1V1 else Setup.preview_5v5()
	setup.ai_actor_ids = []
	var result: Error = simulation.start(setup)
	var prefix: String = "caller_" + _mode_name(mode)
	_check(prefix + "_starts_with_all_ai_disabled", result == OK
		and simulation.get_snapshot().ai_actor_ids.is_empty() and simulation.get_snapshot().ai_intent_actor_ids.is_empty())
	var actor_id: int = 2 if mode == Setup.Mode.MICRO_1V1 else 4
	var initial: Snapshot = simulation.get_snapshot()
	await _frames(12)
	var disabled: Snapshot = simulation.get_snapshot()
	_check(prefix + "_disabled_ai_does_not_produce_commands",
		disabled.actor(actor_id).last_command_sequence == initial.actor(actor_id).last_command_sequence, true)
	result = simulation.set_ai_actor_ids([0, actor_id])
	var enabled: Snapshot = simulation.get_snapshot()
	_check(prefix + "_effective_mask_excludes_selected_human_without_erasing_intent",
		result == OK and enabled.ai_actor_ids == [actor_id] and enabled.ai_intent_actor_ids == [0, actor_id], true)
	await _frames(12)
	enabled = simulation.get_snapshot()
	_check(prefix + "_only_enabled_ai_advances_its_command_sequence",
		enabled.actor(actor_id).last_command_sequence > disabled.actor(actor_id).last_command_sequence
		and enabled.actor(0).last_command_sequence == disabled.actor(0).last_command_sequence)
	result = simulation.set_ai_actor_ids([0])
	var stopped_sequence: int = simulation.get_snapshot().actor(actor_id).last_command_sequence
	await _frames(12)
	disabled = simulation.get_snapshot()
	_check(prefix + "_disabling_ai_stops_further_policy_commands",
		result == OK and disabled.actor(actor_id).last_command_sequence == stopped_sequence, true)
	_check(prefix + "_disable_preserves_configured_human_intent_and_selection",
		disabled.ai_actor_ids.is_empty() and disabled.ai_intent_actor_ids == [0] and disabled.selected_actor_id == 0)
	simulation.queue_free()
	await process_frame


func _fixture(mode: Setup.Mode, owner_id: int, selected_id: int = 0, exercise: Setup.TrainingExercise = Setup.TrainingExercise.FREE_PLAY) -> Snapshot:
	var setup: Setup = Setup.for_exercise(mode, exercise)
	var state: Snapshot = Snapshot.new()
	state.mode = mode
	state.training_exercise = exercise
	state.phase = Snapshot.Phase.PLAYING
	state.selected_actor_id = selected_id
	state.tick = 600
	state.seconds_remaining = 110.0
	state.restart = Types.RestartState.new()
	state.restart.kind = Types.RestartKind.NONE
	state.restart.stage = Types.RestartStage.NONE
	for id: int in setup.actor_positions:
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.team_id = id % 2
		actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
		actor.human_controlled = id == selected_id
		actor.attack_direction = setup.attack_direction(actor.team_id)
		actor.position = setup.actor_positions[id]
		actor.spawn_position = actor.position
		actor.forward = actor.attack_direction
		actor.last_command_sequence = 10 + id
		actor.last_command_tick = 593
		state.actors.append(actor)
		state.ai_intent_actor_ids.append(id)
		if id != selected_id:
			state.ai_actor_ids.append(id)
	_set_owner(state, owner_id)
	return state


func _restart_fixture(mode: Setup.Mode, kind: Types.RestartKind, team: int) -> Snapshot:
	var state: Snapshot = _fixture(mode, -1)
	var setup: Setup = Setup.for_exercise(mode, Setup.TrainingExercise.FREE_PLAY)
	var attack: Vector3 = setup.attack_direction(team)
	state.phase = Snapshot.Phase.RESTART_PAUSE
	state.restart.id = 19
	state.restart.kind = kind
	state.restart.stage = Types.RestartStage.PLACEMENT
	state.restart.awarded_team_id = team
	state.restart.taker_actor_id = team + 2 if kind == Types.RestartKind.GOAL_CLEARANCE else team
	state.restart.stage_started_tick = 60
	state.restart.placement_end_tick = 120
	state.restart.spot = Vector3(attack.x * 8, Tuning.BALL_RADIUS, 0)
	match kind:
		Types.RestartKind.KICK_IN:
			state.restart.spot = Vector3(0, Tuning.BALL_RADIUS, 10)
			state.restart.border = Types.Border.POS_Z
		Types.RestartKind.CORNER:
			state.restart.spot = Vector3(attack.x * 19.88, Tuning.BALL_RADIUS, -9.88)
		Types.RestartKind.GOAL_CLEARANCE:
			state.restart.spot = Vector3(-attack.x * 18, _tuning.keeper_hand_height, 0)
		Types.RestartKind.PENALTY_6M:
			state.restart.spot = Vector3(attack.x * 14, Tuning.BALL_RADIUS, 0)
		Types.RestartKind.ACCUMULATED_FREE_KICK:
			state.restart.spot = Vector3(attack.x * 10, Tuning.BALL_RADIUS, 0)
			state.restart.spot_choice = Types.SpotChoice.TEN_METRE
	state.restart.offence_spot = state.restart.spot
	state.restart.has_spot_choice = false
	var placements: Array[Types.ActorPlacement] = Rules.placement_plan(state, _tuning)
	for item: Types.ActorPlacement in placements:
		state.actor(item.actor_id).position = item.position
		state.actor(item.actor_id).forward = Vector3(item.forward.x, 0, item.forward.y)
	state.restart.stage = Types.RestartStage.READY
	state.restart.ready_tick = 120
	state.restart.stage_started_tick = 120
	state.restart.deadline_tick = -1 if kind == Types.RestartKind.PENALTY_6M else 360
	state.tick = 156
	state.ball_position = state.restart.spot
	state.ball_velocity = Vector3.ZERO
	state.actor(state.restart.taker_actor_id).ball_contact_reachable = true
	state.actor(state.restart.taker_actor_id).ball_in_hands = kind == Types.RestartKind.GOAL_CLEARANCE
	return state


func _legal_restart_launch(command: Command, state: Snapshot) -> bool:
	if command.action not in [Command.Action.PASS, Command.Action.SHOOT, Command.Action.KEEPER_THROW]:
		return false
	var velocity: Vector3 = Vector3(command.aim.x, 0.0, command.aim.y) * 10.0
	return command.action in Rules.allowed_actions(command.actor_id, state) \
		and Rules.launch_error(command, state, velocity, command.target_actor_id, _tuning) == OK


func _passing_fixture() -> Snapshot:
	var state: Snapshot = _fixture(Setup.Mode.PREVIEW_5V5, 4)
	_clear_opponents(state)
	state.actor(4).position = Vector3.ZERO
	state.actor(0).position = Vector3(6, 0, 4)
	state.actor(6).position = Vector3(3, 0, -5)
	_set_owner(state, 4)
	return state


func _blocked_near_goal() -> Snapshot:
	var state: Snapshot = _passing_fixture()
	state.actor(4).position = Vector3(17, 0, 0)
	state.actor(0).position = Vector3(11, 0, 2)
	state.actor(6).position = Vector3(11, 0, -2)
	state.actor(1).position = Vector3(14, 0, 1)
	state.actor(5).position = Vector3(14, 0, -1)
	_set_owner(state, 4)
	return state


func _clear_opponents(state: Snapshot) -> void:
	for actor: Snapshot.ActorSnapshot in state.actors:
		if actor.team_id == Snapshot.Team.AWAY:
			actor.position = Vector3(-14.0 + actor.actor_id * 0.2, 0, -8.0 + actor.actor_id * 0.75)


func _set_owner(state: Snapshot, id: int) -> void:
	state.ball_owner_id = id
	for item: Snapshot.ActorSnapshot in state.actors:
		item.ball_contact_reachable = item.actor_id == id
	if id >= 0:
		var actor: Snapshot.ActorSnapshot = state.actor(id)
		state.ball_position = actor.position + actor.forward * 0.55 + Vector3.UP * 0.12


func _decide(state: Snapshot, id: int, held_seconds: float) -> Command:
	_decisions += 1
	return MatchAI.decide(state.actor(id), state, _tuning, held_seconds)


func _is_pass_to(command: Command, state: Snapshot, target_id: int) -> bool:
	if command.action != Command.Action.PASS or command.target_actor_id != target_id:
		return false
	var recipient: Snapshot.ActorSnapshot = state.actor(target_id)
	var offset: Vector3 = recipient.position - state.ball_position
	var aim: Vector2 = Vector2(offset.x, offset.z).normalized()
	return command.aim.is_equal_approx(aim) and command.target_actor_id != command.actor_id


func _valid_home_command(command: Command, actor: Snapshot.ActorSnapshot) -> bool:
	return command.actor_id == actor.actor_id and command.sequence == actor.last_command_sequence + 1 \
		and command.move.is_finite() and command.move.length_squared() <= 1.00001 \
		and command.aim.is_finite() and command.aim.length_squared() <= 1.00001 \
		and command.action != Command.Action.SHOOT and command.shot_charge == 0.0 and command.shot_lift == 0.0


func _is_controlled_carry(command: Command) -> bool:
	return command.action == Command.Action.NONE and command.target_actor_id == -1 and command.close_control \
		and not command.sprint and not command.move.is_zero_approx() and command.move.length_squared() <= 1.00001 \
		and command.aim.dot(command.move.normalized()) > 0.99 and command.shot_charge == 0.0 and command.shot_lift == 0.0


func _fingerprint(state: Snapshot) -> Array:
	var result: Array = [state.mode, state.phase, state.tick, state.selected_actor_id,
		state.ai_intent_actor_ids.duplicate(), state.ai_actor_ids.duplicate(), state.ball_owner_id,
		state.ball_position, state.ball_velocity, state.last_touch_actor_id]
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.actor_id, actor.team_id, actor.role, actor.human_controlled,
			actor.position, actor.spawn_position, actor.velocity, actor.forward,
			actor.last_command_sequence, actor.last_command_tick, actor.action_cooldown])
	return result


func _mode_name(mode: Setup.Mode) -> String:
	return "micro" if mode == Setup.Mode.MICRO_1V1 else "preview"


func _frames(count: int) -> void:
	for index: int in count:
		await physics_frame
		await process_frame


func _check(label: String, passed: bool, negative: bool = false) -> void:
	if negative:
		_negative_cases += 1
	_checks.append({"name": label, "passed": passed, "negative": negative})
	print(("PASS " if passed else "FAIL ") + label)


func _finish() -> void:
	var failures: Array[Dictionary] = _checks.filter(func(item: Dictionary) -> bool: return not bool(item["passed"]))
	var result: Dictionary = {
		"ok": _completed and failures.is_empty(), "complete": _completed,
		"total": _checks.size(), "passed": _checks.size() - failures.size(), "expected_checks": EXPECTED_CHECKS,
		"negative_cases": _negative_cases, "expected_negative_cases": EXPECTED_NEGATIVE_CASES,
		"expected_refusals": 0, "observed_refusals": _refusals.size(), "command_refusals": _refusals,
		"expected_errors": 0, "expected_warnings": 0, "policy_decisions": _decisions,
		"production_entrypoint": "MatchAI.decide", "scope": "playing-and-restart-ai-policy-with-caller-filter",
		"authority_guard_tested": false, "headless": DisplayServer.get_name() == "headless",
		"engine": Engine.get_version_info()["string"], "physics": "Jolt Physics",
		"physics_hz": Engine.physics_ticks_per_second, "process_id": OS.get_process_id(),
		"wall_seconds": float(Time.get_ticks_msec() - _started_ms) / 1000.0,
		"failures": failures, "checks": _checks,
	}
	print("FUTSAL_MATCH_AI_TACTICS_TESTS ", JSON.stringify(result))
	quit(0 if _completed and failures.is_empty() else 1)


func _finalize() -> void:
	if not _completed:
		printerr("FUTSAL_MATCH_AI_TACTICS_TESTS_INCOMPLETE")
