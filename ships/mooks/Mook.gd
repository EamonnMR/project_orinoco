extends KinematicBody2D

export var max_speed = 100;
export var accel = 25;
export var turn_rate = PI / 4
export var accel_margin = PI / 2
export var accel_distance = 10
export var shoot_margin = PI / 2
export var shoot_distance = 200
export var max_target_distance = 1000
export var points_reward = 10

var basic_shot = preload("res://ships/mooks/basic_shot.tscn")

export var team = 0
var health = 25
var max_health = 25
var velocity = Vector2()

var target_is_default = null
var target = null
var rotation_impulse = 0.0
var ideal_face = null
var can_shoot = true
var death_explo = null

puppet var puppet_pos = Vector2()
puppet var puppet_velocity = Vector2()
puppet var puppet_rotation = 0.0
puppet var puppet_health = 0

func _init():
	death_explo = preload("res://explosions/medium.tscn")

func _ready():
	health = max_health
	$sprite/Sprite.frame = team
	
func _physics_process(delta):
	if is_network_master():
		_handle_ai(delta)
		_handle_rotation(delta)
		_handle_acceleration(delta)
		_limit_speed()
		_handle_shooting()
		_push_vars_to_net()
	else:
		_get_vars_from_net()

	move_and_slide(velocity)
	if not is_network_master():
		puppet_pos = position # To avoid jitter

func _push_vars_to_net():
	rset("puppet_velocity", velocity)
	rset("puppet_pos", position)
	rset("puppet_rotation", $sprite/Sprite.rotation)
	rset("puppet_health", health)

func _get_vars_from_net():
	position = puppet_pos
	velocity = puppet_velocity
	$sprite/Sprite.rotation = puppet_rotation
	health = puppet_health

sync func destroyed():
	var explo = death_explo.instance()
	explo.position = position
	get_parent().add_child(explo)
	gamestate.add_score(gamestate.other_team(team), points_reward)
	queue_free()
	
master func take_damage(_by_who, amount):
	health -= amount
	if(health) <= 0:
		rpc("destroyed")
		
func comparitor(lval, rval):
	return ai.distance_comparitor(self, lval, rval)

func _find_target():
	var nodes = []
	var players = get_node("../../Players").get_children()
	nodes += players
	var mooks = get_node("../../Mooks").get_children()
	nodes += mooks
	var bases = get_node("../../Bases").get_children()
	nodes += bases
	nodes.sort_custom(self, "comparitor")
	for node in nodes:
		if position.distance_to(node.position) > max_target_distance:
			break
		if "team" in node and node.team != team and is_instance_valid(node):
			return node
	# By default, go after the enemy starbase
	for node in bases:
		if node.team != team and is_instance_valid(node):
			target_is_default = true
			return node
	return null

func _handle_rotation(delta):
	# TODO: Rotate to face target
	$sprite/Sprite.rotation = fmod($sprite/Sprite.rotation + rotation_impulse, PI * 2) # += rotation_impulse * turn_rate * delta

func _handle_shooting():
	if(
		can_shoot and _should_shoot()
	):
		can_shoot = false
		$reload_timer.start()
		for shot_emerge_point in $sprite/shot_emerge_points.get_children():
			var pos = shot_emerge_point.get_global_position()
			rpc("shoot", "mook shot", pos, $sprite/Sprite.rotation, get_tree().get_network_unique_id())

func _handle_ai(delta):
	if not target or not is_instance_valid(target) or target_is_default:
		target = _find_target()
	rotation_impulse = 0.0
	ideal_face = null
	if(target):
		var impulse = ai._constrained_point(self, target, $sprite/Sprite.rotation, turn_rate * delta, target.position)
		rotation_impulse = impulse[0]
		ideal_face = impulse[1]

func _handle_acceleration(delta):
	if(target):
		if(ideal_face):
			if(_facing_right_way_to_accel() and _far_enough_to_accel()):
				velocity += Vector2(0, -1 * accel * delta).rotated($sprite/Sprite.rotation)

func _facing_right_way_to_accel():
	return _facing_within_margin(accel_margin)

func _far_enough_to_accel():
	return position.distance_to(target.position) > accel_distance

func _facing_within_margin(margin):
	return ideal_face and abs(fmod(ideal_face - $sprite/Sprite.rotation, 2 * PI)) < margin

func _limit_speed():
	if velocity.length() > max_speed:
		velocity = Vector2(cos(velocity.angle()), sin(velocity.angle())) * max_speed

func _should_shoot():
	return target and _facing_within_margin(shoot_margin) and position.distance_to(target.position) < shoot_distance

sync func shoot(name, pos, direction, by_who):
	var shot = basic_shot.instance()
	shot.set_name(name) # Ensure unique name for the shot
	shot.team = team
	shot.position = pos
	shot.set_direction(direction)
	shot.velocity = velocity
	# No need to set network master to bomb, will be owned by server by default
	get_node("../..").add_child(shot)

func _on_reload_timer_timeout():
	can_shoot = true

func _on_ai_rethink_timer_timeout():
	target = _find_target()
