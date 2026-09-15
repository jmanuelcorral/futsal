extends SceneTree

const Rules = preload("res://match/simulation/match_rules.gd")
const Types = preload("res://match/simulation/match_rule_types.gd")
const Snapshot = preload("res://match/simulation/match_snapshot.gd")
const Command = preload("res://match/simulation/player_command.gd")
const Setup = preload("res://match/simulation/match_setup.gd")
const Tuning = preload("res://match/simulation/match_tuning.gd")

var _tuning: Tuning = Tuning.new()
var _checks: Array[Dictionary] = []
var _groups: Array[Dictionary] = []
var _negative_cases: int = 0
var _expected_checks: int = 2
var _expected_negatives: int = 0
var _group: String = ""
var _completed: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check("native_headless_environment", DisplayServer.get_name() == "headless")
	_run_group("crossings", _test_crossings, 14, 7)
	_run_group("boundaries", _test_boundaries, 31, 4)
	_run_group("direct_goals", _test_direct_goals, 30, 11)
	_run_group("fouls", _test_fouls, 28, 8)
	_run_group("foul_tuning_addendum", _test_foul_tuning_addendum, 13, 8)
	_run_group("spots", _test_spots, 22, 4)
	_run_group("expiry", _test_expiry, 26, 18)
	_run_group("second_touch_and_extension", _test_second_touch_and_extension, 28, 24)
	_run_group("g10_episode_identity", _test_g10_episode_identity, 44, 20)
	_run_group("placement_and_guards", _test_placement_and_guards, 55, 18)
	_run_group("corner_orientations", _test_corner_orientations, 8, 0)
	_run_group("copies", _test_copies, 4, 0)
	_group = ""
	var names: Dictionary[String, bool] = {}
	for check: Dictionary in _checks:
		names[String(check["name"])] = true
	_check("semantic_names_are_unique", names.size() == _checks.size())
	_completed = true
	_finish()


func _run_group(label: String, test: Callable, expected: int, negatives: int) -> void:
	_group = label
	var before: int = _checks.size()
	var negatives_before: int = _negative_cases
	test.call()
	var actual: int = _checks.size() - before
	var negative_actual: int = _negative_cases - negatives_before
	_expected_checks += expected + 2
	_expected_negatives += negatives
	_groups.append({"name": label, "expected": expected, "actual": actual, "expected_negatives": negatives, "actual_negatives": negative_actual})
	_check("exact_case_count", actual == expected)
	_check("exact_negative_count", negative_actual == negatives)


func _test_crossings() -> void:
	var borders: Array[Types.Border] = [Types.Border.NEG_X, Types.Border.POS_X, Types.Border.NEG_Z, Types.Border.POS_Z]
	for border: Types.Border in borders:
		var axis: int = 0 if border in [Types.Border.NEG_X, Types.Border.POS_X] else 2
		var end: float = -1.0 if border in [Types.Border.NEG_X, Types.Border.NEG_Z] else 1.0
		var edge: float = 20.0 if axis == 0 else 10.0
		var from: Vector3 = Vector3(0, Tuning.BALL_RADIUS, 0)
		var to: Vector3 = from
		from[axis] = end * (edge - 0.2)
		to[axis] = end * (edge + 0.4)
		var crossing: Types.BoundaryCrossing = Rules.first_crossing(from, to, _tuning)
		_check(_border_name(border) + "_whole_sphere_crossing", crossing.border == border
			and is_equal_approx(crossing.position[axis], end * (edge + Tuning.BALL_RADIUS))
			and crossing.fraction > 0.0 and crossing.fraction < 1.0)
		to[axis] = end * (edge + Tuning.BALL_RADIUS)
		_check(_border_name(border) + "_tangent_ball_remains_in_play",
			Rules.first_crossing(from, to, _tuning).border == Types.Border.NONE, true)
	var first: Types.BoundaryCrossing = Rules.first_crossing(Vector3(19, 0.105, 9.8), Vector3(21, 0.105, 11), _tuning)
	_check("touchline_before_end_line_wins_on_diagonal", first.border == Types.Border.POS_Z)
	first = Rules.first_crossing(Vector3(19.105, 0.105, 9.105), Vector3(21.105, 0.105, 11.105), _tuning)
	_check("exact_corner_tie_uses_end_line", first.border == Types.Border.POS_X)
	first = Rules.first_crossing(Vector3(19.105, 0.105, 9.10501), Vector3(21.105, 0.105, 11.10501), _tuning)
	_check("slightly_earlier_touchline_is_not_rounded_into_corner_tie", first.border == Types.Border.POS_Z)
	_check("stationary_ball_does_not_cross", Rules.first_crossing(Vector3.ZERO, Vector3.ZERO, _tuning).border == Types.Border.NONE, true)
	_check("already_out_ball_does_not_generate_a_second_crossing",
		Rules.first_crossing(Vector3(21, 0.105, 0), Vector3(22, 0.105, 0), _tuning).border == Types.Border.NONE, true)
	_check("nonfinite_geometry_cannot_create_a_crossing",
		Rules.first_crossing(Vector3.INF, Vector3.ZERO, _tuning).border == Types.Border.NONE, true)


func _test_boundaries() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for mirrored: bool in [false, true]:
			var state: Snapshot = _state(mode, mirrored)
			for team: int in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
				var prefix: String = _case_prefix(mode, mirrored, team)
				var end: float = _attack(team, state).x
				state.last_touch_actor_id = team
				var goal: Types.RuleDecision = Rules.boundary_decision(_goal_crossing(end), state, _tuning)
				_check(prefix + "_goal_team_comes_from_exercise_orientation",
					goal.kind == Types.DecisionKind.GOAL and goal.scoring_team_id == team)
				var out: Types.BoundaryCrossing = _goal_crossing(end, 4.0)
				state.last_touch_actor_id = 1 - team
				var corner: Types.RuleDecision = Rules.boundary_decision(out, state, _tuning)
				_check(prefix + "_defender_last_touch_awards_corner", corner.kind == Types.DecisionKind.RESTART
					and corner.restart.kind == Types.RestartKind.CORNER and corner.restart.awarded_team_id == team)
				state.last_touch_actor_id = team
				var clearance: Types.RuleDecision = Rules.boundary_decision(out, state, _tuning)
				_check(prefix + "_attacker_last_touch_awards_clearance",
					clearance.restart.kind == Types.RestartKind.GOAL_CLEARANCE and clearance.restart.awarded_team_id == 1 - team)
	var state: Snapshot = _state()
	_check("ball_overlapping_post_opening_is_not_a_goal",
		Rules.boundary_decision(_goal_crossing(1.0, 1.5 - Tuning.BALL_RADIUS + 0.005), state, _tuning).kind != Types.DecisionKind.GOAL, true)
	var high: Types.BoundaryCrossing = _goal_crossing(1.0)
	high.position.y = 2.0 - Tuning.BALL_RADIUS + 0.005
	_check("ball_above_crossbar_is_not_a_goal", Rules.boundary_decision(high, state, _tuning).kind != Types.DecisionKind.GOAL, true)
	var fabricated: Types.BoundaryCrossing = _goal_crossing(1.0)
	fabricated.position.x = 0.0
	_check("border_label_without_matching_crossing_plane_cannot_score",
		Rules.boundary_decision(fabricated, state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.last_touch_actor_id = 1
	state.ball_owner_id = 0
	_check("possession_proximity_does_not_replace_last_physical_touch",
		Rules.boundary_decision(_goal_crossing(1.0, 4.0), state, _tuning).restart.kind == Types.RestartKind.CORNER)
	var sideline: Types.BoundaryCrossing = Rules.first_crossing(Vector3(2, 0.105, 9.8), Vector3(2, 0.105, 10.4), _tuning)
	_check("touchline_beneficiary_is_opposite_last_physical_team",
		Rules.boundary_decision(sideline, state, _tuning).restart.awarded_team_id == Snapshot.Team.HOME)
	state.phase = Snapshot.Phase.PAUSED
	_check("paused_snapshot_cannot_award_a_goal",
		Rules.boundary_decision(_goal_crossing(1.0), state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.phase = Snapshot.Phase.PLAYING
	var awarded: Types.RestartState = Rules.boundary_decision(sideline, state, _tuning).restart
	_check("award_reserves_minimum_placement_time_without_starting_four_seconds",
		awarded.stage == Types.RestartStage.STOPPED and awarded.placement_end_tick == state.tick + 60
		and awarded.ready_tick == -1 and awarded.deadline_tick == -1)


func _test_direct_goals() -> void:
	var kinds: Array[Types.RestartKind] = [Types.RestartKind.KICK_IN, Types.RestartKind.CORNER,
		Types.RestartKind.GOAL_CLEARANCE, Types.RestartKind.DIRECT_FREE_KICK, Types.RestartKind.INDIRECT_FREE_KICK,
		Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]
	for kind: Types.RestartKind in kinds:
		for own_net: bool in [false, true]:
			var state: Snapshot = _restart_state(kind)
			_put_in_play(state)
			var end: float = -1.0 if own_net else 1.0
			var decision: Types.RuleDecision = Rules.boundary_decision(_goal_crossing(end), state, _tuning)
			var allowed: bool = not own_net and kind in [Types.RestartKind.CORNER, Types.RestartKind.DIRECT_FREE_KICK,
				Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]
			var expected: Types.RestartKind = Types.RestartKind.CORNER if own_net else Types.RestartKind.GOAL_CLEARANCE
			_check(_kind_name(kind) + ("_own_net_direct" if own_net else "_opponent_net_direct"),
				(decision.kind == Types.DecisionKind.GOAL if allowed else decision.kind == Types.DecisionKind.RESTART
					and decision.restart.kind == expected and decision.restart.awarded_team_id == Snapshot.Team.AWAY), not allowed)
			state.restart.other_actor_touched = true
			decision = Rules.boundary_decision(_goal_crossing(end), state, _tuning)
			_check(_kind_name(kind) + ("_own_net_after_deflection" if own_net else "_opponent_net_after_deflection"),
				decision.kind == Types.DecisionKind.GOAL and decision.scoring_team_id == (1 if own_net else 0))
	var state: Snapshot = _restart_state(Types.RestartKind.KICK_IN)
	_put_in_play(state)
	var post: Types.ContactEvidence = _ball_contact(state, -1, state.tick + 10)
	var ignored: Types.RuleDecision = Rules.contact_decision(post, state, _tuning)
	_check("post_contact_does_not_clear_direct_goal_restriction", ignored.kind == Types.DecisionKind.NONE
		and not state.restart.other_actor_touched
		and Rules.boundary_decision(_goal_crossing(1.0), state, _tuning).kind != Types.DecisionKind.GOAL, true)
	state = _state()
	state.last_touch_actor_id = 0
	state.last_pass_actor_id = 0
	state.last_pass_target_actor_id = 2
	_check("accidental_goal_from_ordinary_home_pass_is_preserved",
		Rules.boundary_decision(_goal_crossing(1.0), state, _tuning).kind == Types.DecisionKind.GOAL)


func _test_fouls() -> void:
	var state: Snapshot = _state()
	var contact: Types.ContactEvidence = _body_contact(state)
	var decision: Types.RuleDecision = Rules.contact_decision(contact, state, _tuning)
	_check("real_body_first_challenge_is_late_direct_foul", decision.kind == Types.DecisionKind.FOUL
		and decision.foul_verdict == Types.FoulVerdict.LATE and decision.counts_as_accumulated_foul)
	contact.ball_touched_first = true
	decision = Rules.contact_decision(contact, state, _tuning)
	_check("moderate_recent_ball_first_challenge_is_clean",
		decision.kind == Types.DecisionKind.NONE and decision.foul_verdict == Types.FoulVerdict.CLEAN, true)
	contact.actor_velocity = Vector3(-10.5, 0, 0)
	decision = Rules.contact_decision(contact, state, _tuning)
	_check("dangerous_closing_speed_is_reckless_even_when_ball_was_first",
		decision.kind == Types.DecisionKind.FOUL and decision.foul_verdict == Types.FoulVerdict.RECKLESS)
	contact.actor_velocity = Vector3(-4, 0, 0)
	contact.ball_touch_tick = contact.tackle_started_tick - 1
	_check("stale_ball_contact_does_not_excuse_late_body_challenge",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.LATE)
	contact.tackle_started_tick = -1
	_check("ordinary_bump_without_challenge_is_not_a_foul",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact.actor_velocity = Vector3(10, 0, 0)
	_check("fast_separation_is_not_reckless_closing",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact.actor_velocity = Vector3.ZERO
	contact.other_velocity = Vector3(8, 0, 0)
	_check("stationary_actor_is_not_blamed_for_victim_velocity_alone",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact = _body_contact(state)
	contact.other_actor_id = 3
	_check("same_team_body_contact_is_not_a_direct_foul",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact = _ball_contact(state, 1, state.tick)
	contact.tackle_started_tick = state.tick - 2
	_check("tackle_without_rival_body_contact_does_not_invent_a_foul",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	_check("missing_contact_evidence_is_explicitly_rejected",
		Rules.contact_decision(null, state, _tuning).reason == &"invalid_contact", true)
	contact = _body_contact(state)
	state.accumulated_fouls.y = 4
	_check("four_prior_direct_fouls_produce_ordinary_fifth",
		Rules.contact_decision(contact, state, _tuning).restart.kind == Types.RestartKind.DIRECT_FREE_KICK)
	state.accumulated_fouls.y = 5
	_check("five_prior_direct_fouls_produce_sixth_without_wall",
		Rules.contact_decision(contact, state, _tuning).restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK)
	state.accumulated_fouls.y = 4
	contact = _body_contact(state, Vector3(15, 0.8, 0))
	decision = Rules.contact_decision(contact, state, _tuning)
	_check("penalty_foul_does_not_increment_accumulated_count_2025_26",
		decision.restart.kind == Types.RestartKind.PENALTY_6M and not decision.counts_as_accumulated_foul
		and state.accumulated_fouls.y == 4)
	contact = _body_contact(state)
	_check("direct_foul_after_four_plus_penalty_is_still_fifth",
		Rules.contact_decision(contact, state, _tuning).restart.kind == Types.RestartKind.DIRECT_FREE_KICK)
	var repeated: Types.RuleDecision = Rules.contact_decision(contact, state, _tuning)
	decision = Rules.contact_decision(contact, state, _tuning)
	_check("physical_episode_id_is_preserved_for_core_dedup_without_local_counter_mutation",
		repeated != decision and repeated.contact_id == decision.contact_id and state.accumulated_fouls.y == 4)
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for mirrored: bool in [false, true]:
			for team: int in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
				state = _state(mode, mirrored)
				var own_end: float = -_attack(team, state).x
				contact = _body_contact(state, Vector3(own_end * 15, 0.8, 0), team, 1 - team)
				decision = Rules.contact_decision(contact, state, _tuning)
				_check(_case_prefix(mode, mirrored, team) + "_defending_area_penalty_precedes_sixth",
					decision.restart.kind == Types.RestartKind.PENALTY_6M and not decision.counts_as_accumulated_foul
					and is_equal_approx(decision.restart.spot.x, own_end * 14))
	state = _state()
	state.accumulated_fouls.y = 5
	_check("straight_penalty_area_line_belongs_to_area",
		Rules.contact_decision(_body_contact(state, Vector3(14, 0.8, 0)), state, _tuning).restart.kind == Types.RestartKind.PENALTY_6M)
	_check("just_outside_straight_area_line_uses_sixth",
		Rules.contact_decision(_body_contact(state, Vector3(13.99, 0.8, 0)), state, _tuning).restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK)
	_check("quarter_circle_uses_outer_post_center_at_one_point_five_eight",
		Rules.contact_decision(_body_contact(state, Vector3(15.2, 0.8, 5.18)), state, _tuning).restart.kind == Types.RestartKind.PENALTY_6M)
	_check("just_outside_quarter_circle_uses_sixth_not_rectangular_penalty",
		Rules.contact_decision(_body_contact(state, Vector3(15.2, 0.8, 5.2)), state, _tuning).restart.kind == Types.RestartKind.ACCUMULATED_FREE_KICK)
	contact = _body_contact(state)
	contact.actor_velocity = Vector3.INF
	_check("nonfinite_contact_velocity_cannot_award_a_foul",
		Rules.contact_decision(contact, state, _tuning).reason == &"invalid_contact_vectors", true)


func _test_foul_tuning_addendum() -> void:
	_check("published_arcade_defaults_match_accepted_addendum",
		_tuning.foul_challenge_window_ticks == 18 and is_equal_approx(_tuning.foul_min_closing_speed, 0.8)
		and is_equal_approx(_tuning.foul_reckless_closing_speed, 9.5))
	var state: Snapshot = _state()
	var contact: Types.ContactEvidence = _body_contact(state)
	contact.tackle_started_tick = state.tick - _tuning.foul_challenge_window_ticks
	_check("contact_at_last_challenge_window_tick_can_be_late",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.LATE)
	contact.tackle_started_tick -= 1
	_check("contact_after_challenge_window_is_not_a_foul",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact = _body_contact(state)
	contact.tackle_started_tick = -1
	contact.actor_velocity = Vector3(-10.5, 0, 0)
	state.actor(1).gesture_kind = Types.GestureKind.TACKLE
	state.actor(1).gesture_started_tick = state.tick - 1
	state.actor(1).gesture_duration_ticks = 30
	_check("animation_alone_does_not_replace_captured_active_challenge",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.actor(1).gesture_kind = Types.GestureKind.NONE
	_check("high_speed_contact_without_active_challenge_is_not_automatically_a_foul",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact = _body_contact(state)
	contact.actor_velocity = Vector3.ZERO
	_check("stationary_active_challenge_without_closing_is_not_a_foul",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact.actor_velocity = Vector3.LEFT * _tuning.foul_min_closing_speed
	_check("closing_exactly_at_minimum_does_not_exceed_foul_threshold",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact.actor_velocity = Vector3.LEFT * (_tuning.foul_min_closing_speed + 0.1)
	_check("body_first_contact_above_minimum_is_late",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.LATE)
	contact.ball_touched_first = true
	contact.actor_velocity = Vector3.LEFT * _tuning.foul_reckless_closing_speed
	_check("ball_first_contact_at_reckless_threshold_is_not_above_it",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.CLEAN, true)
	contact.actor_velocity = Vector3.LEFT * (_tuning.foul_reckless_closing_speed + 0.1)
	_check("ball_first_contact_above_reckless_threshold_is_reckless",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.RECKLESS)
	contact.actor_velocity = Vector3.LEFT * 4.0
	contact.tackle_started_tick = state.tick - _tuning.foul_challenge_window_ticks
	contact.ball_touch_tick = contact.tackle_started_tick + 1
	_check("ball_first_from_same_challenge_uses_full_agreed_window",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.CLEAN, true)
	contact = _body_contact(state)
	state.actor(1).position = Vector3(8, 0, 0)
	state.actor(0).position = Vector3(8, 0, 1)
	state.actor(1).velocity = Vector3.ZERO
	state.actor(0).velocity = Vector3.ZERO
	_check("classification_uses_captured_preimpact_normal_velocity_not_post_slide_pose",
		Rules.contact_decision(contact, state, _tuning).foul_verdict == Types.FoulVerdict.LATE)
	contact.normal = Vector3.ZERO
	_check("missing_contact_normal_is_not_replaced_with_post_slide_centres",
		Rules.contact_decision(contact, state, _tuning).reason == &"missing_contact_normal", true)


func _test_spots() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for mirrored: bool in [false, true]:
			for team: int in [Snapshot.Team.HOME, Snapshot.Team.AWAY]:
				var state: Snapshot = _state(mode, mirrored)
				var end: float = -_attack(team, state).x
				var point: Vector3 = Rules.project_to_penalty_area_line(Vector3(end * 18, 0.4, 1.0), team, state, _tuning)
				_check(_case_prefix(mode, mirrored, team) + "_straight_projection_preserves_z_and_height",
					point.is_equal_approx(Vector3(end * 14, 0.4, 1.0)))
				point = Rules.project_to_penalty_area_line(Vector3(end * 18, 0.4, 5.18), team, state, _tuning)
				_check(_case_prefix(mode, mirrored, team) + "_curved_projection_is_longitudinal_not_radial",
					point.is_equal_approx(Vector3(end * 15.2, 0.4, 5.18)))
	var state: Snapshot = _state()
	_check("impossible_longitudinal_intersection_returns_explicit_nonfinite_sentinel",
		not Rules.project_to_penalty_area_line(Vector3(18, 0.1, 8), 1, state, _tuning).is_finite(), true)
	state.accumulated_fouls.y = 5
	var choice: Types.RuleDecision = Rules.contact_decision(_body_contact(state, Vector3(12, 0.8, 8)), state, _tuning)
	_check("ten_metre_strip_choice_is_longitudinal_even_beyond_ten_metre_radial_distance",
		choice.restart.has_spot_choice and choice.restart.spot_choice == Types.SpotChoice.TEN_METRE
		and choice.restart.offence_spot.is_equal_approx(Vector3(12, Tuning.BALL_RADIUS, 8)))
	choice = Rules.contact_decision(_body_contact(state, Vector3(10, 0.8, 8)), state, _tuning)
	_check("exact_ten_metre_line_uses_mark_without_closer_choice", not choice.restart.has_spot_choice, true)
	choice = Rules.contact_decision(_body_contact(state, Vector3(8, 0.8, 8)), state, _tuning)
	_check("offence_outside_ten_metre_strip_has_no_location_choice", not choice.restart.has_spot_choice, true)
	choice = Rules.contact_decision(_body_contact(state, Vector3(16, 0.8, 0)), state, _tuning)
	_check("inside_area_never_offers_a_ten_metre_choice",
		choice.restart.kind == Types.RestartKind.PENALTY_6M and not choice.restart.has_spot_choice)
	state = _restart_state(Types.RestartKind.ACCUMULATED_FREE_KICK, false)
	state.restart.spot_choice = Types.SpotChoice.OFFENCE_SPOT
	state.restart.has_spot_choice = false
	_check("unavailable_offence_spot_choice_is_not_silently_accepted",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3(10, 0, 0), -1, _tuning) == ERR_INVALID_DATA, true)


func _test_expiry() -> void:
	var kinds: Array[Types.RestartKind] = [Types.RestartKind.KICK_IN, Types.RestartKind.CORNER,
		Types.RestartKind.GOAL_CLEARANCE, Types.RestartKind.DIRECT_FREE_KICK,
		Types.RestartKind.INDIRECT_FREE_KICK, Types.RestartKind.ACCUMULATED_FREE_KICK]
	for kind: Types.RestartKind in kinds:
		var state: Snapshot = _restart_state(kind)
		state.restart.ready_tick = 0
		state.restart.deadline_tick = 240
		state.tick = 0
		_check(_kind_name(kind) + "_ready_tick_zero_is_not_expired",
			Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
		state.tick = 239
		_check(_kind_name(kind) + "_tick_two_three_nine_is_not_expired",
			Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
		state.tick = 240
		var decision: Types.RuleDecision = Rules.expiry_decision(state, _tuning)
		var expected: Types.RestartKind = Types.RestartKind.INDIRECT_FREE_KICK
		if kind == Types.RestartKind.KICK_IN:
			expected = Types.RestartKind.KICK_IN
		elif kind == Types.RestartKind.CORNER:
			expected = Types.RestartKind.GOAL_CLEARANCE
		_check(_kind_name(kind) + "_tick_two_four_zero_has_type_specific_consequence",
			decision.kind == Types.DecisionKind.RESTART and decision.restart.kind == expected
			and decision.restart.awarded_team_id == Snapshot.Team.AWAY and not decision.counts_as_accumulated_foul)
	var state: Snapshot = _restart_state(Types.RestartKind.PENALTY_6M)
	state.tick += 900
	_check("ordinary_penalty_has_no_four_second_expiry", Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
	state = _restart_state(Types.RestartKind.KICK_IN)
	state.restart.deadline_tick = -1
	state.tick += 900
	_check("minus_one_deadline_is_never_treated_as_already_expired", Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.restart.deadline_tick = 0
	state.tick = 0
	_check("deadline_zero_is_a_real_deadline_not_a_falsey_disabled_timer",
		Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.RESTART)
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	state.restart.spot = Vector3(-18, Tuning.BALL_RADIUS, 3)
	state.tick = state.restart.deadline_tick
	var decision: Types.RuleDecision = Rules.expiry_decision(state, _tuning)
	var expected_spot: Vector3 = Rules.project_to_penalty_area_line(state.restart.spot, 0, state, _tuning)
	_check("own_area_free_kick_expiry_projects_indirect_along_touchline",
		decision.restart.spot.is_equal_approx(expected_spot) and decision.restart.spot.z == 3.0)
	state.phase = Snapshot.Phase.PAUSED
	_check("paused_restart_does_not_expire_from_tick_value_alone",
		Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.phase = Snapshot.Phase.RESTART_PAUSE
	state.restart.stage = Types.RestartStage.STOPPED
	_check("stopped_stage_never_consumes_ready_deadline", Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.restart.stage = Types.RestartStage.PLACEMENT
	_check("placement_stage_never_consumes_ready_deadline", Rules.expiry_decision(state, _tuning).kind == Types.DecisionKind.NONE, true)
	state = _restart_state(Types.RestartKind.ACCUMULATED_FREE_KICK)
	state.period_state = Types.PeriodState.EXTENDED_KICK
	state.extended_restart_id = state.restart.id
	state.tick = state.restart.deadline_tick
	decision = Rules.expiry_decision(state, _tuning)
	_check("expired_extended_sixth_finishes_without_fresh_indirect_attack",
		decision.kind == Types.DecisionKind.NONE and decision.reason == &"extended_kick_expired", true)


func _test_second_touch_and_extension() -> void:
	var state: Snapshot = _restart_state(Types.RestartKind.KICK_IN)
	_put_in_play(state)
	var taker: int = state.restart.taker_actor_id
	var contact: Types.ContactEvidence = _ball_contact(state, taker, state.tick, state.restart.launch_contact_id)
	_check("original_kick_notification_is_not_second_touch",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact.tick += 20
	_check("delayed_original_notification_retains_original_episode_identity",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	contact = _ball_contact(state, taker, state.tick + 10)
	var decision: Types.RuleDecision = Rules.contact_decision(contact, state, _tuning)
	_check("new_separated_taker_contact_awards_indirect_without_accumulation",
		decision.kind == Types.DecisionKind.RESTART and decision.restart.kind == Types.RestartKind.INDIRECT_FREE_KICK
		and decision.contact_id == contact.contact_id and not decision.counts_as_accumulated_foul)
	var repeated: Types.RuleDecision = Rules.contact_decision(contact, state, _tuning)
	_check("repeated_evidence_retains_same_commit_identity_and_does_not_mutate_state",
		repeated.contact_id == decision.contact_id and state.accumulated_fouls == Vector2i.ZERO)
	contact = _ball_contact(state, 2, state.tick + 10)
	_check("other_player_contact_does_not_penalize_the_taker_or_mutate_touch_guard",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE
		and not state.restart.other_actor_touched, true)
	state.restart.other_actor_touched = true
	contact = _ball_contact(state, taker, state.tick + 20)
	_check("core_confirmed_other_player_touch_releases_second_touch_guard",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.restart.other_actor_touched = false
	_check("post_without_other_player_does_not_release_second_touch_guard",
		Rules.contact_decision(contact, state, _tuning).restart.kind == Types.RestartKind.INDIRECT_FREE_KICK)
	state = _restart_state(Types.RestartKind.ACCUMULATED_FREE_KICK)
	_put_in_play(state)
	state.period_state = Types.PeriodState.EXTENDED_KICK
	state.extended_restart_id = state.restart.id
	state.extended_kick_event_id = 51
	contact = _ball_contact(state, state.restart.taker_actor_id, state.tick + 10)
	_check("extended_second_touch_does_not_start_an_indirect_restart",
		Rules.contact_decision(contact, state, _tuning).kind == Types.DecisionKind.NONE, true)
	_check("current_extended_kick_can_complete_with_one_goal",
		Rules.boundary_decision(_goal_crossing(1.0), state, _tuning).kind == Types.DecisionKind.GOAL)
	state.extended_restart_id += 1
	_check("stale_extension_identity_cannot_award_a_goal",
		Rules.boundary_decision(_goal_crossing(1.0), state, _tuning).kind == Types.DecisionKind.NONE, true)
	state.extended_restart_id = state.restart.id
	_check("extended_ball_out_never_starts_a_fresh_corner_or_clearance",
		Rules.boundary_decision(_goal_crossing(1.0, 4.0), state, _tuning).kind == Types.DecisionKind.NONE, true)
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	_put_in_play(state)
	contact = _body_contact(state)
	contact.tick = state.restart.stage_started_tick - 1
	_check("contact_from_before_current_restart_is_ignored",
		Rules.contact_decision(contact, state, _tuning).reason == &"contact_precedes_current_restart", true)
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for mirrored: bool in [false, true]:
			for pending: Types.RestartKind in [Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]:
				for in_area: bool in [false, true]:
					state = _restart_state(pending, false, mode, mirrored)
					_put_in_play(state)
					state.period_state = Types.PeriodState.EXTENDED_KICK
					state.seconds_remaining = 0.0
					state.extended_restart_id = state.restart.id
					state.extended_kick_event_id = 51
					state.accumulated_fouls = Vector2i(5, 5)
					var end: float = _attack(Snapshot.Team.HOME, state).x
					contact = _body_contact(state, Vector3(end * (15.0 if in_area else 8.0), 0.8, 0))
					var before: Array = _fingerprint(state)
					decision = Rules.contact_decision(contact, state, _tuning)
					_check(_case_prefix(mode, mirrored, Snapshot.Team.HOME) + "_extended_" + _kind_name(pending)
						+ ("_body_foul_cannot_create_fresh_penalty" if in_area else "_body_foul_cannot_create_fresh_sixth"),
						decision.kind == Types.DecisionKind.NONE and decision.restart.kind == Types.RestartKind.NONE
						and decision.reason == &"extended_kick_contact_ends_play" and decision.contact_id == contact.contact_id
						and not decision.counts_as_accumulated_foul and before == _fingerprint(state)
						and state.extended_restart_id == state.restart.id and state.extended_kick_event_id == 51, true)


func _test_g10_episode_identity() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for mirrored: bool in [false, true]:
			var prefix: String = _case_prefix(mode, mirrored, Snapshot.Team.HOME)
			var state: Snapshot = _restart_state(Types.RestartKind.KICK_IN, true, mode, mirrored)
			_put_in_play(state)
			var launch_id: int = state.restart.launch_contact_id
			var launch_tick: int = state.tick
			var before: Array = _fingerprint(state)
			var copied: Snapshot = state.copy()
			var copied_id: int = copied.restart.launch_contact_id
			copied.restart.launch_contact_id = -1
			_check(prefix + "_launch_contact_identity_survives_detached_snapshot_copy",
				copied_id == launch_id and copied.restart != state.restart and before == _fingerprint(state))
			for offset: int in [0, 1]:
				var label: String = prefix + "_tick_plus_%d" % offset
				state.tick = launch_tick + offset
				var observed: Array = _fingerprint(state)
				var original: Types.ContactEvidence = _ball_contact(state, state.restart.taker_actor_id, state.tick, launch_id)
				var decision: Types.RuleDecision = Rules.contact_decision(original, state, _tuning)
				_check(label + "_continuous_original_episode_is_not_second_touch",
					decision.kind == Types.DecisionKind.NONE and decision.reason == &"original_launch_contact", true)
				var separated: Types.ContactEvidence = _ball_contact(state, state.restart.taker_actor_id, state.tick, launch_id + 1 + offset)
				decision = Rules.contact_decision(separated, state, _tuning)
				_check(label + "_new_episode_is_indirect_without_any_clock_grace",
					decision.kind == Types.DecisionKind.RESTART and decision.reason == &"restart_double_touch"
					and decision.restart.kind == Types.RestartKind.INDIRECT_FREE_KICK
					and decision.restart.awarded_team_id == Snapshot.Team.AWAY and decision.contact_id == separated.contact_id
					and not decision.counts_as_accumulated_foul)
				var repeated: Types.RuleDecision = Rules.contact_decision(separated, state, _tuning)
				_check(label + "_repeated_new_episode_keeps_commit_identity_and_input_immutable",
					repeated.kind == decision.kind and repeated.contact_id == decision.contact_id and observed == _fingerprint(state))
			state.tick = launch_tick + 40
			var delayed: Types.ContactEvidence = _ball_contact(state, state.restart.taker_actor_id, state.tick, launch_id)
			_check(prefix + "_original_identity_is_not_derived_from_a_recent_timestamp",
				Rules.contact_decision(delayed, state, _tuning).reason == &"original_launch_contact", true)
			state.restart.launch_contact_id = -1
			state.tick = launch_tick + 1
			var unknown: Types.ContactEvidence = _ball_contact(state, state.restart.taker_actor_id, state.tick, launch_id)
			_check(prefix + "_missing_launch_identity_cannot_be_guessed_from_time",
				Rules.contact_decision(unknown, state, _tuning).restart.kind == Types.RestartKind.INDIRECT_FREE_KICK)
			state = _restart_state(Types.RestartKind.ACCUMULATED_FREE_KICK, true, mode, mirrored)
			_put_in_play(state)
			state.period_state = Types.PeriodState.EXTENDED_KICK
			state.extended_restart_id = state.restart.id
			state.extended_kick_event_id = 51
			state.tick += 1
			var original: Types.ContactEvidence = _ball_contact(state, state.restart.taker_actor_id, state.tick, state.restart.launch_contact_id)
			_check(prefix + "_extended_original_episode_callback_does_not_end_the_kick",
				Rules.contact_decision(original, state, _tuning).reason == &"original_launch_contact", true)
			var separated: Types.ContactEvidence = _ball_contact(state, state.restart.taker_actor_id, state.tick, state.restart.launch_contact_id + 1)
			var terminal: Types.RuleDecision = Rules.contact_decision(separated, state, _tuning)
			_check(prefix + "_extended_new_episode_ends_without_starting_an_indirect",
				terminal.kind == Types.DecisionKind.NONE and terminal.reason == &"extended_kick_second_touch"
				and terminal.restart.kind == Types.RestartKind.NONE, true)


func _test_placement_and_guards() -> void:
	var kinds: Array[Types.RestartKind] = [Types.RestartKind.KICK_IN, Types.RestartKind.CORNER,
		Types.RestartKind.GOAL_CLEARANCE, Types.RestartKind.DIRECT_FREE_KICK,
		Types.RestartKind.INDIRECT_FREE_KICK, Types.RestartKind.PENALTY_6M, Types.RestartKind.ACCUMULATED_FREE_KICK]
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for mirrored: bool in [false, true]:
			for kind: Types.RestartKind in kinds:
				var state: Snapshot = _restart_state(kind, false, mode, mirrored)
				var before: Array = _fingerprint(state)
				var plan: Array[Types.ActorPlacement] = Rules.placement_plan(state, _tuning)
				var untouched: bool = before == _fingerprint(state)
				_apply_placements(state, plan)
				_make_ready(state)
				var action: Command.Action = Command.Action.KEEPER_THROW if kind == Types.RestartKind.GOAL_CLEARANCE else Command.Action.SHOOT
				var command: Command = _launch(state, action)
				var velocity: Vector3 = _attack(0, state) * 10.0
				_check(_case_prefix(mode, mirrored, 0) + "_" + _kind_name(kind) + "_localized_legal_placement",
					not plan.is_empty() and untouched and _placements_separated(state)
					and Rules.launch_error(command, state, velocity, -1, _tuning) == OK)
	var state: Snapshot = _restart_state(Types.RestartKind.GOAL_CLEARANCE, false)
	state.actor(1).position = Vector3(-13.9, 0, 0)
	var plan: Array[Types.ActorPlacement] = Rules.placement_plan(state, _tuning)
	_check("clearance_opponent_outside_area_within_five_metres_is_not_relocated",
		not plan.is_empty() and not _plan_has(plan, 1) and state.actor(1).position.distance_to(state.restart.spot) < 5.0)
	state = _restart_state(Types.RestartKind.CORNER, false)
	state.actor(1).position = Vector3(20, 0, -10) + Vector3(-1, 0, 1).normalized() * 5.20
	plan = Rules.placement_plan(state, _tuning)
	_apply_placements(state, plan)
	_check("corner_opponent_distance_is_from_arc_not_only_ball",
		_plan_has(plan, 1) and _flat_distance(state.actor(1).position, Vector3(20, 0, -10)) >= 5.25 - 0.0001)
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK, false, Setup.Mode.PREVIEW_5V5)
	state.actor(4).position = Vector3(state.restart.spot.x, 0, state.restart.spot.z)
	plan = Rules.placement_plan(state, _tuning)
	_apply_placements(state, plan)
	_check("friendly_actor_contesting_stationary_ball_is_moved_out_of_kick_contact",
		_plan_has(plan, 4) and _flat_distance(state.actor(4).position, state.restart.spot) > 0.55 and _placements_separated(state))
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK, false, Setup.Mode.PREVIEW_5V5)
	state.actor(1).position = Vector3(13.2, 0, -0.4)
	state.actor(5).position = Vector3(13.2, 0, 0.4)
	state.actor(4).position = Vector3(12.5, 0, 0)
	plan = Rules.placement_plan(state, _tuning)
	_apply_placements(state, plan)
	_check("attacking_support_stays_one_metre_from_two_player_wall",
		_flat_distance(state.actor(4).position, state.actor(1).position) >= 1.0
		and _flat_distance(state.actor(4).position, state.actor(5).position) >= 1.0)
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	_check("ready_taker_cannot_move", not Rules.can_move(state.restart.taker_actor_id, state)
		and Rules.constrain_displacement(state.restart.taker_actor_id, Vector3.RIGHT, state, _tuning).is_zero_approx(), true)
	_check("non_taker_cannot_tackle_stationary_restart_ball",
		Command.Action.TACKLE not in Rules.allowed_actions(1, state), true)
	state.restart.awarded_team_id = Snapshot.Team.AWAY
	state.restart.taker_actor_id = 1
	state.restart.spot = Vector3(-8, Tuning.BALL_RADIUS, 0)
	state.restart.stage = Types.RestartStage.PLACEMENT
	_apply_placements(state, Rules.placement_plan(state, _tuning))
	_make_ready(state)
	_check("human_defender_can_switch_during_opponent_restart",
		Command.Action.SWITCH_TEAMMATE in Rules.allowed_actions(0, state))
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	var wrong: Command = _launch(state, Command.Action.SHOOT)
	wrong.actor_id = 1
	_check("wrong_actor_cannot_launch_restart",
		Rules.launch_error(wrong, state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state = _restart_state(Types.RestartKind.GOAL_CLEARANCE)
	_check("goal_clearance_does_not_allow_foot_pass",
		Rules.launch_error(_launch(state, Command.Action.PASS), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	_check("goal_clearance_uses_keeper_hands_without_leaving_area",
		Rules.launch_error(_launch(state, Command.Action.KEEPER_THROW), state, Vector3.RIGHT * 10, -1, _tuning) == OK)
	state = _restart_state(Types.RestartKind.PENALTY_6M)
	_check("ordinary_penalty_cannot_be_kicked_backwards",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.LEFT * 10, -1, _tuning) != OK, true)
	state = _restart_state(Types.RestartKind.ACCUMULATED_FREE_KICK)
	_check("sixth_requires_shot_not_pass",
		Rules.launch_error(_launch(state, Command.Action.PASS), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state = _restart_state(Types.RestartKind.PENALTY_6M)
	_check("ordinary_penalty_uses_shot_only_in_arcade_control_contract",
		Command.Action.PASS not in Rules.allowed_actions(state.restart.taker_actor_id, state)
		and Rules.launch_error(_launch(state, Command.Action.PASS), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK, false)
	_check("preparatory_vector_can_be_previewed_but_not_executed",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.RIGHT * 10, -1, _tuning) == OK
		and Command.Action.SHOOT not in Rules.allowed_actions(0, state))
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	state.actor(0).ball_contact_reachable = false
	_check("ready_launch_revalidates_authoritative_physical_contact",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state.actor(0).ball_contact_reachable = true
	wrong = _launch(state, Command.Action.PASS)
	wrong.target_actor_id = 1
	_check("opponent_cannot_be_effective_pass_target",
		Rules.launch_error(wrong, state, Vector3.RIGHT * 10, 1, _tuning) != OK, true)
	_check("nonfinite_launch_velocity_is_rejected",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.INF, -1, _tuning) == ERR_INVALID_PARAMETER, true)
	state.tick = state.restart.deadline_tick
	_check("launch_revalidates_deadline_instead_of_trusting_old_preview",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	state.actor(2).position = state.actor(0).position
	_check("overlapping_teammate_cannot_be_ignored_for_restart_execution",
		Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state = _restart_state(Types.RestartKind.INDIRECT_FREE_KICK)
	state.restart.spot = Vector3(0, 0.105, 0)
	state.ball_position = state.restart.spot
	state.actor(1).position = Vector3(-6, 0, 0)
	var displacement: Vector3 = Rules.constrain_displacement(1, Vector3(12, 0, 0), state, _tuning)
	_check("large_motion_cannot_tunnel_through_five_metre_exclusion",
		displacement.x < 1.01 and state.actor(1).position.x + displacement.x <= -5.0 + 0.001, true)
	state = _restart_state(Types.RestartKind.GOAL_CLEARANCE)
	state.actor(1).position = Vector3(-19, 0, -8)
	displacement = Rules.constrain_displacement(1, Vector3(0, 0, 16), state, _tuning)
	_check("outside_area_endpoints_do_not_allow_motion_through_goal_clearance_area",
		displacement.z < 2.0, true)
	state = _restart_state(Types.RestartKind.PENALTY_6M)
	var keeper_start: Vector3 = state.actor(3).position
	_check("penalty_keeper_can_move_along_goal_line",
		Rules.constrain_displacement(3, Vector3(0, 0, 0.2), state, _tuning).is_equal_approx(Vector3(0, 0, 0.2)))
	_check("penalty_keeper_cannot_move_forward_before_kick",
		absf(Rules.constrain_displacement(3, Vector3.LEFT, state, _tuning).x) < 0.001
		and is_equal_approx(keeper_start.x, 20.0), true)
	state.restart.kind = Types.RestartKind.NONE
	_check("unsupported_restart_is_not_silently_launchable",
		Rules.allowed_actions(0, state) == [Command.Action.NONE]
		and Rules.launch_error(_launch(state, Command.Action.SHOOT), state, Vector3.RIGHT * 10, -1, _tuning) != OK, true)
	state = _state(Setup.Mode.PREVIEW_5V5)
	state.ball_owner_id = 4
	state.actor(4).ball_contact_reachable = true
	wrong = Command.new(4, 1)
	wrong.action = Command.Action.SHOOT
	_check("live_home_ai_cannot_request_a_shot",
		Rules.launch_error(wrong, state, Vector3.RIGHT * 10, -1, _tuning) == ERR_UNAUTHORIZED, true)
	state.selected_actor_id = 4
	_check("selected_human_retains_live_shot",
		Rules.launch_error(wrong, state, Vector3.RIGHT * 10, -1, _tuning) == OK)
	state.selected_actor_id = 0
	wrong.action = Command.Action.PASS
	_check("home_ai_free_goalward_pass_cannot_disguise_a_shot",
		Rules.launch_error(wrong, state, Vector3.RIGHT * 10, -1, _tuning) == ERR_UNAUTHORIZED, true)


func _test_copies() -> void:
	var state: Snapshot = _restart_state(Types.RestartKind.DIRECT_FREE_KICK)
	var before: Array = _fingerprint(state)
	var command: Command = _launch(state, Command.Action.SHOOT)
	var command_before: Array = [command.actor_id, command.sequence, command.action, command.aim, command.target_actor_id]
	var crossing: Types.BoundaryCrossing = _goal_crossing(1.0)
	Rules.boundary_decision(crossing, state, _tuning)
	Rules.contact_decision(_ball_contact(state, 0, state.tick), state, _tuning)
	Rules.expiry_decision(state, _tuning)
	Rules.placement_plan(state, _tuning)
	Rules.allowed_actions(0, state)
	Rules.can_move(1, state)
	Rules.constrain_displacement(1, Vector3.RIGHT, state, _tuning)
	Rules.launch_error(command, state, Vector3.RIGHT * 10, -1, _tuning)
	Rules.project_to_penalty_area_line(Vector3(18, 0.105, 0), 1, state, _tuning)
	_check("all_public_queries_preserve_snapshot_and_command_arguments", before == _fingerprint(state)
		and command_before == [command.actor_id, command.sequence, command.action, command.aim, command.target_actor_id])
	var copy: Types.RestartState = state.restart.copy()
	copy.spot.x += 3.0
	copy.other_actor_touched = true
	copy.launch_contact_id = 901
	_check("restart_copy_is_detached", copy != state.restart and copy.spot != state.restart.spot and
		not state.restart.other_actor_touched and state.restart.launch_contact_id == -1)
	state = _state()
	var contact: Types.ContactEvidence = _body_contact(state)
	var first: Types.RuleDecision = Rules.contact_decision(contact, state, _tuning)
	var second: Types.RuleDecision = Rules.contact_decision(contact, state, _tuning)
	first.restart.spot.z = 9.0
	_check("identical_rule_queries_return_fresh_nested_decisions",
		first != second and first.restart != second.restart and second.restart.spot.z == 0.0)
	var copied_decision: Types.RuleDecision = second.copy()
	copied_decision.restart.spot.x += 1.0
	_check("decision_copy_detaches_nested_restart",
		copied_decision.restart != second.restart and copied_decision.restart.spot != second.restart.spot)


func _test_corner_orientations() -> void:
	for mode: Setup.Mode in [Setup.Mode.MICRO_1V1, Setup.Mode.PREVIEW_5V5]:
		for end: float in [-1.0, 1.0]:
			for side: float in [-1.0, 1.0]:
				var state: Snapshot = _restart_state(Types.RestartKind.CORNER, false, mode, end < 0.0)
				if end < 0.0:
					state.training_exercise = Setup.TrainingExercise.CORNER_NEG_X_NEG_Z if side < 0.0 else Setup.TrainingExercise.CORNER_NEG_X_POS_Z
				else:
					state.training_exercise = Setup.TrainingExercise.CORNER_POS_X_NEG_Z if side < 0.0 else Setup.TrainingExercise.CORNER_POS_X_POS_Z
				state.restart.spot = Vector3(end * 19.88, Tuning.BALL_RADIUS, side * 9.88)
				var plan: Array[Types.ActorPlacement] = Rules.placement_plan(state, _tuning)
				_apply_placements(state, plan)
				_make_ready(state)
				var command: Command = _launch(state, Command.Action.SHOOT)
				command.aim = Vector2(-end, -side).normalized()
				var velocity: Vector3 = Vector3(command.aim.x, 0.0, command.aim.y) * 10.0
				var taker: Snapshot.ActorSnapshot = state.actor(state.restart.taker_actor_id)
				_check(("micro" if mode == Setup.Mode.MICRO_1V1 else "preview")
					+ ("_negative_x" if end < 0.0 else "_positive_x") + ("_negative_z" if side < 0.0 else "_positive_z")
					+ "_corner_places_and_aims_inward",
					not plan.is_empty() and taker.forward.x * end < 0.0 and taker.forward.z * side < 0.0
					and _placements_separated(state) and Rules.launch_error(command, state, velocity, -1, _tuning) == OK)


func _state(mode: Setup.Mode = Setup.Mode.MICRO_1V1, mirrored: bool = false) -> Snapshot:
	var exercise: Setup.TrainingExercise = Setup.TrainingExercise.CORNER_NEG_X_NEG_Z if mirrored else Setup.TrainingExercise.FREE_PLAY
	var setup: Setup = Setup.for_exercise(mode, exercise)
	var state: Snapshot = Snapshot.new()
	state.mode = mode
	state.training_exercise = exercise
	state.phase = Snapshot.Phase.PLAYING
	state.tick = 600
	state.seconds_remaining = 60.0
	state.selected_actor_id = 0
	state.ball_position = Vector3(0, Tuning.BALL_RADIUS, 0)
	state.ball_velocity = Vector3.ZERO
	state.ball_owner_id = -1
	state.last_touch_actor_id = -1
	state.last_touch_tick = -1
	state.period_state = Types.PeriodState.REGULATION
	state.extended_restart_id = -1
	state.extended_kick_event_id = -1
	state.restart = Types.RestartState.new()
	state.restart.kind = Types.RestartKind.NONE
	state.restart.stage = Types.RestartStage.NONE
	for id: int in setup.actor_positions:
		var actor: Snapshot.ActorSnapshot = Snapshot.ActorSnapshot.new()
		actor.actor_id = id
		actor.team_id = id % 2
		actor.role = Snapshot.Role.KEEPER if id in [2, 3] else Snapshot.Role.FIELD
		actor.position = setup.actor_positions[id]
		actor.spawn_position = actor.position
		actor.attack_direction = setup.attack_direction(actor.team_id)
		actor.forward = actor.attack_direction
		actor.human_controlled = id == 0
		actor.ball_contact_reachable = false
		state.actors.append(actor)
	return state


func _restart_state(kind: Types.RestartKind, ready: bool = true, mode: Setup.Mode = Setup.Mode.MICRO_1V1, mirrored: bool = false) -> Snapshot:
	var state: Snapshot = _state(mode, mirrored)
	var end: float = _attack(0, state).x
	state.phase = Snapshot.Phase.RESTART_PAUSE
	state.restart.id = 8
	state.restart.kind = kind
	state.restart.stage = Types.RestartStage.PLACEMENT
	state.restart.awarded_team_id = 0
	state.restart.taker_actor_id = 2 if kind == Types.RestartKind.GOAL_CLEARANCE else 0
	state.selected_actor_id = state.restart.taker_actor_id
	state.restart.spot = Vector3(end * 8.0, Tuning.BALL_RADIUS, 0)
	match kind:
		Types.RestartKind.KICK_IN:
			state.restart.spot = Vector3(0, Tuning.BALL_RADIUS, 10)
			state.restart.border = Types.Border.POS_Z
		Types.RestartKind.CORNER:
			state.restart.spot = Vector3(end * 19.88, Tuning.BALL_RADIUS, -9.88)
			state.restart.border = Types.Border.NEG_X if end < 0.0 else Types.Border.POS_X
		Types.RestartKind.GOAL_CLEARANCE:
			state.restart.spot = Vector3(-end * 18, _tuning.keeper_hand_height, 0)
		Types.RestartKind.PENALTY_6M:
			state.restart.spot = Vector3(end * 14, Tuning.BALL_RADIUS, 0)
		Types.RestartKind.ACCUMULATED_FREE_KICK:
			state.restart.spot = Vector3(end * 10, Tuning.BALL_RADIUS, 0)
			state.restart.spot_choice = Types.SpotChoice.TEN_METRE
	state.restart.offence_spot = state.restart.spot
	state.restart.stage_started_tick = 540
	state.restart.placement_end_tick = 600
	state.restart.ready_tick = -1
	state.restart.deadline_tick = -1
	state.restart.has_spot_choice = false
	state.restart.other_actor_touched = false
	if ready:
		_apply_placements(state, Rules.placement_plan(state, _tuning))
		_make_ready(state)
	return state


func _make_ready(state: Snapshot) -> void:
	state.restart.stage = Types.RestartStage.READY
	state.restart.stage_started_tick = state.tick
	state.restart.ready_tick = state.tick
	state.restart.deadline_tick = -1 if state.restart.kind == Types.RestartKind.PENALTY_6M else state.tick + 240
	state.ball_position = state.restart.spot
	state.ball_velocity = Vector3.ZERO
	var taker: Snapshot.ActorSnapshot = state.actor(state.restart.taker_actor_id)
	taker.ball_contact_reachable = true
	taker.ball_in_hands = state.restart.kind == Types.RestartKind.GOAL_CLEARANCE


func _put_in_play(state: Snapshot) -> void:
	state.phase = Snapshot.Phase.PLAYING
	state.restart.stage = Types.RestartStage.IN_PLAY
	state.restart.stage_started_tick = state.tick
	state.restart.other_actor_touched = false
	state.restart.launch_contact_id = 70
	state.last_touch_actor_id = state.restart.taker_actor_id
	state.last_touch_tick = state.tick


func _body_contact(state: Snapshot, point: Vector3 = Vector3(8, 0.8, 0), offender: int = 1, victim: int = 0) -> Types.ContactEvidence:
	state.actor(offender).position = Vector3(point.x + 0.3, 0, point.z)
	state.actor(victim).position = Vector3(point.x - 0.3, 0, point.z)
	var contact: Types.ContactEvidence = Types.ContactEvidence.new()
	contact.kind = Types.ContactKind.ACTOR_ACTOR
	contact.contact_id = 42
	contact.tick = state.tick
	contact.actor_id = offender
	contact.other_actor_id = victim
	contact.point = point
	contact.normal = Vector3.RIGHT
	contact.actor_velocity = Vector3.LEFT * 4
	contact.other_velocity = Vector3.ZERO
	contact.tackle_started_tick = state.tick - 10
	contact.ball_touch_tick = state.tick - 1
	contact.ball_touched_first = false
	return contact


func _ball_contact(state: Snapshot, actor_id: int, tick: int, contact_id: int = 71) -> Types.ContactEvidence:
	var contact: Types.ContactEvidence = Types.ContactEvidence.new()
	contact.kind = Types.ContactKind.BALL_ACTOR
	contact.contact_id = contact_id
	contact.actor_id = actor_id
	contact.other_actor_id = -1
	contact.tick = tick
	contact.ball_touch_tick = tick
	contact.point = state.ball_position
	contact.normal = Vector3.UP
	contact.tackle_started_tick = -1
	return contact


func _launch(state: Snapshot, action: Command.Action) -> Command:
	var command: Command = Command.new(state.restart.taker_actor_id, 1)
	command.action = action
	var attack: Vector3 = _attack(state.restart.awarded_team_id, state)
	command.aim = Vector2(attack.x, 0)
	return command


func _goal_crossing(end: float, lateral: float = 0.0) -> Types.BoundaryCrossing:
	return Rules.first_crossing(Vector3(end * 19.8, Tuning.BALL_RADIUS, lateral), Vector3(end * 20.4, Tuning.BALL_RADIUS, lateral), _tuning)


func _attack(team: int, state: Snapshot) -> Vector3:
	var setup: Setup = Setup.new()
	setup.training_exercise = state.training_exercise
	return setup.attack_direction(team)


func _apply_placements(state: Snapshot, placements: Array[Types.ActorPlacement]) -> void:
	for placement: Types.ActorPlacement in placements:
		state.actor(placement.actor_id).position = placement.position
		state.actor(placement.actor_id).forward = Vector3(placement.forward.x, 0, placement.forward.y)


func _plan_has(plan: Array[Types.ActorPlacement], actor_id: int) -> bool:
	for placement: Types.ActorPlacement in plan:
		if placement.actor_id == actor_id:
			return true
	return false


func _placements_separated(state: Snapshot) -> bool:
	for first: Snapshot.ActorSnapshot in state.actors:
		for second: Snapshot.ActorSnapshot in state.actors:
			if first.actor_id < second.actor_id and _flat_distance(first.position, second.position) < 2.0 * Tuning.ACTOR_RADIUS + 0.029:
				return false
	return true


func _fingerprint(state: Snapshot) -> Array:
	var result: Array = [state.phase, state.mode, state.tick, state.training_exercise,
		state.selected_actor_id, state.score, state.accumulated_fouls, state.ball_position,
		state.ball_velocity, state.ball_owner_id, state.last_touch_actor_id, state.last_touch_tick,
		state.restart.id, state.restart.kind, state.restart.stage, state.restart.spot, state.restart.offence_spot,
		state.restart.other_actor_touched, state.restart.deadline_tick, state.restart.launch_contact_id]
	for actor: Snapshot.ActorSnapshot in state.actors:
		result.append([actor.actor_id, actor.team_id, actor.position, actor.forward,
			actor.velocity, actor.ball_contact_reachable, actor.ball_in_hands])
	return result


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _case_prefix(mode: Setup.Mode, mirrored: bool, team: int) -> String:
	return ("micro" if mode == Setup.Mode.MICRO_1V1 else "preview") + ("_mirrored_" if mirrored else "_normal_") + ("home" if team == 0 else "away")


func _kind_name(kind: Types.RestartKind) -> String:
	var names: Array[String] = ["none", "kick_in", "corner", "goal_clearance", "direct_free_kick", "indirect_free_kick", "penalty", "sixth"]
	return names[int(kind)]


func _border_name(border: Types.Border) -> String:
	var names: Array[String] = ["none", "negative_end", "positive_end", "negative_touchline", "positive_touchline"]
	return names[int(border)]


func _check(label: String, passed: bool, negative: bool = false) -> void:
	var name: String = label if _group.is_empty() else _group + "_" + label
	if negative:
		_negative_cases += 1
	_checks.append({"name": name, "passed": passed, "negative": negative})
	print(("PASS " if passed else "FAIL ") + name)


func _finish() -> void:
	var failures: Array[Dictionary] = _checks.filter(func(check: Dictionary) -> bool: return not bool(check["passed"]))
	var result: Dictionary = {
		"ok": _completed and failures.is_empty() and _checks.size() == _expected_checks and _negative_cases == _expected_negatives,
		"complete": _completed, "total": _checks.size(), "passed": _checks.size() - failures.size(),
		"expected_checks": _expected_checks, "negative_cases": _negative_cases,
		"expected_negative_cases": _expected_negatives, "expected_errors": 0, "expected_warnings": 0,
		"expected_refusals": 0, "scope": "pure-match-rules-contract", "physical_episode_collection_tested": false,
		"headless": DisplayServer.get_name() == "headless", "process_id": OS.get_process_id(),
		"engine": Engine.get_version_info()["string"], "groups": _groups, "checks": _checks, "failures": failures,
	}
	print("FUTSAL_MATCH_RULES_TESTS ", JSON.stringify(result))
	quit(0 if bool(result["ok"]) else 1)


func _finalize() -> void:
	if not _completed:
		printerr("FUTSAL_MATCH_RULES_TESTS_INCOMPLETE")
