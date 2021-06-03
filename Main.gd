extends Spatial

var perform_runtime_config = false

onready var ovr_init_config = preload("res://addons/godot_ovrmobile/OvrInitConfig.gdns").new()
onready var ovr_performance = preload("res://addons/godot_ovrmobile/OvrPerformance.gdns").new()
onready var bullet_template: RigidBody = preload("res://Bullet.tscn").instance()
onready var target_template: RigidBody = preload("res://Target.tscn").instance()

onready var bullets = get_node("ARVROrigin/Bullets")
onready var targets = get_node("ARVROrigin/Targets")
onready var camera = get_node("ARVROrigin/ARVRCamera")

var leftHand: OculusHandTracker = null
var rightHand: OculusHandTracker = null

var targetTimer = 0.0
var targetSpawnDelay = 1.5

var leftHandLoaded = 0
var leftHandReady = false
var rightHandLoaded = 0
var rightHandReady = false

func _ready():
	var interface = ARVRServer.find_interface("OVRMobile")
	if interface:
		ovr_init_config.set_render_target_size_multiplier(1)

		if interface.initialize():
			get_viewport().arvr = true
	leftHand = get_node("ARVROrigin/LeftHand")
	rightHand = get_node("ARVROrigin/RightHand")	

func _process(delta):
	if not perform_runtime_config:
		ovr_performance.set_clock_levels(1, 1)
		ovr_performance.set_extra_latency_mode(1)
		perform_runtime_config = true
	updateHands(delta)
	updateBullets(delta)
	updateTargets(delta)

func updateHands(delta):
	leftHandLoaded += 1 * delta
	leftHandLoaded = min(leftHandLoaded, 5)
	
	if detectGesture(leftHand, 00011) && leftHandLoaded > 0 && !leftHandReady:
		leftHandLoaded -= 1
		leftHandReady = true
	if detectGesture(leftHand, 00010) && leftHandReady:
		leftHandReady = false
		spawnBullet(leftHand, leftHand.transform.basis.x)
	
	rightHandLoaded += 1 * delta
	rightHandLoaded = min(rightHandLoaded, 5)
	
	if detectGesture(rightHand, 00011) && rightHandLoaded > 0 && !rightHandReady:
		rightHandLoaded -= 1
		rightHandReady = true
	if detectGesture(rightHand, 00010) && rightHandReady:
		rightHandReady = false
		spawnBullet(rightHand, rightHand.transform.basis.x * -1)

func updateTargets(delta):
	targetTimer += delta
	if targetTimer >= targetSpawnDelay && targets.get_child_count() < 10:
		targetTimer -= targetSpawnDelay
		spawnTarget()
	for target in targets.get_children():
		var y = target.translation.y
		if y < -10.0:
			target.queue_free()

func updateBullets(delta):
	for bullet in bullets.get_children():
		var dist = camera.translation.distance_to(bullet.translation)
		if dist > 50.0:
			bullet.queue_free()

func detectGesture(hand: OculusHandTracker, gesture: int):
	var result = 0;
	for i in range(0,5):
		var finger_state = hand.get_finger_state_estimate(i);
		result += pow(10,i) * finger_state;
	return result == gesture

func spawnTarget():
	var angle = rand_range(-45, 45)
	var translation = -camera.transform.basis.z * 10
	var target: RigidBody = target_template.duplicate()
	translation.y = -5
	targets.add_child(target)
	target.translation = translation
	target.apply_central_impulse(Vector3(0,1,0) * 5.0)

func spawnBullet(hand: OculusHandTracker, forward: Vector3):
	var bullet: RigidBody = bullet_template.duplicate()
	bullets.add_child(bullet)
	
	var model = hand.get_child(0)
	bullet.transform = model.global_transform
	bullet.apply_central_impulse(forward * 20.0)
