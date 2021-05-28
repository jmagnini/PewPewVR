extends Spatial

var perform_runtime_config = false

onready var ovr_init_config = preload("res://addons/godot_ovrmobile/OvrInitConfig.gdns").new()
onready var ovr_performance = preload("res://addons/godot_ovrmobile/OvrPerformance.gdns").new()
onready var bullet_template: RigidBody = preload("res://Bullet.tscn").instance()

onready var objects = get_node("ARVROrigin/Objects")

var leftHand: OculusHandTracker = null
var rightHand: OculusHandTracker = null

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

func _process(_delta):
	if not perform_runtime_config:
		ovr_performance.set_clock_levels(1, 1)
		ovr_performance.set_extra_latency_mode(1)
		perform_runtime_config = true
	updateHands(_delta)

func updateHands(delta):
	if detectGesture(leftHand, 11111):
		leftHandLoaded += 1
		leftHandLoaded = min(leftHandLoaded, 5)
	if detectGesture(leftHand, 00011) && leftHandLoaded > 0 && !leftHandReady:
		leftHandLoaded -= 1
		leftHandReady = true
	if detectGesture(leftHand, 00010) && leftHandReady:
		leftHandReady = false
		spawnBullet(leftHand, leftHand.transform.basis.x)
	
	if detectGesture(rightHand, 11111):
		rightHandLoaded += 1
		rightHandLoaded = min(rightHandLoaded, 5)
	if detectGesture(rightHand, 00011) && rightHandLoaded > 0 && !rightHandReady:
		rightHandLoaded -= 1
		rightHandReady = true
	if detectGesture(rightHand, 00010) && rightHandReady:
		rightHandReady = false
		spawnBullet(rightHand, rightHand.transform.basis.x * -1)

func detectGesture(hand: OculusHandTracker, gesture: int):
	var result = 0;
	for i in range(0,5):
		var finger_state = hand.get_finger_state_estimate(i);
		result += pow(10,i) * finger_state;
	return result == gesture

func spawnBullet(hand: OculusHandTracker, forward: Vector3):
	var bullet: RigidBody = bullet_template.duplicate()
	objects.add_child(bullet)
	
	var model = hand.get_child(0)
	bullet.transform = model.global_transform
	bullet.apply_central_impulse(forward * 10.0)
