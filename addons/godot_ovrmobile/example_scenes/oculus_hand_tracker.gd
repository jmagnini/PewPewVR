class_name OculusHandTracker
extends OculusTracker
# Extension of the OculusTracker class to support Oculus hands tracking.


# Current hand pinch mapping for the tracked hands
# Godot itself also exposes some of these constants via JOY_VR_* and JOY_OCULUS_*
# this enum here is to document everything in place and includes the pinch event mappings
enum FINGER_PINCH {
	MIDDLE_PINCH = 1,
	PINKY_PINCH = 2,
	INDEX_PINCH = 7,
	RING_PINCH = 15,
}

var hand_skel : Skeleton = null

# Oculus mobile APIs available at runtime.
var ovr_hand_tracking = null;
var ovr_utilities = null;

# This array is used to get the orientations from the sdk each frame (an array of Quat)
var _vrapi_bone_orientations = [];

# we need the inverse neutral pose to compute the estimates for gesture detection
var _vrapi_inverse_neutral_pose = []; # this is filled when clearing the rest pose

# Remap the bone ids from the hand model to the bone orientations we get from the vrapi
var _hand_bone_mappings = [0, 23,  1, 2, 3, 4,  6, 7, 8,  10, 11, 12,  14, 15, 16, 18, 19, 20, 21];

enum ovrHandFingers {
	Thumb		= 0,
	Index		= 1,
	Middle		= 2,
	Ring		= 3,
	Pinky		= 4,
	Max,
	EnumSize = 0x7fffffff
};

enum ovrHandBone {
	Invalid						= -1,
	WristRoot 					= 0,	# root frame of the hand, where the wrist is located
	ForearmStub					= 1,	# frame for user's forearm
	Thumb0						= 2,	# thumb trapezium bone
	Thumb1						= 3,	# thumb metacarpal bone
	Thumb2						= 4,	# thumb proximal phalange bone
	Thumb3						= 5,	# thumb distal phalange bone
	Index1						= 6,	# index proximal phalange bone
	Index2						= 7,	# index intermediate phalange bone
	Index3						= 8,	# index distal phalange bone
	Middle1						= 9,	# middle proximal phalange bone
	Middle2						= 10,	# middle intermediate phalange bone
	Middle3						= 11,	# middle distal phalange bone
	Ring1						= 12,	# ring proximal phalange bone
	Ring2						= 13,	# ring intermediate phalange bone
	Ring3						= 14,	# ring distal phalange bone
	Pinky0						= 15,	# pinky metacarpal bone
	Pinky1						= 16,	# pinky proximal phalange bone
	Pinky2						= 17,	# pinky intermediate phalange bone
	Pinky3						= 18,	# pinky distal phalange bone
	MaxSkinnable				= 19,

	# Bone tips are position only. They are not used for skinning but useful for hit-testing.
	# NOTE: ThumbTip == MaxSkinnable since the extended tips need to be contiguous
	ThumbTip					= 19 + 0,	# tip of the thumb
	IndexTip					= 19 + 1,	# tip of the index finger
	MiddleTip					= 19 + 2,	# tip of the middle finger
	RingTip						= 19 + 3,	# tip of the ring finger
	PinkyTip					= 19 + 4,	# tip of the pinky
	Max 						= 19 + 5,
	EnumSize 					= 0x7fff
};

const _ovrHandFingers_Bone1Start = [ovrHandBone.Thumb1, ovrHandBone.Index1, ovrHandBone.Middle1, ovrHandBone.Ring1,ovrHandBone.Pinky1];

# we need to remap the bone ids from the hand model to the bone orientations we get from the vrapi and the inverse
# This is only for the actual bones and skips the tips (vrapi 19-23) as they do not need to be updated I think
const _vrapi2hand_bone_map = [0, 23,  1, 2, 3, 4,  6, 7, 8,  10, 11, 12,  14, 15, 16, 18, 19, 20, 21];
# inverse mapping to get from the godot hand bone ids to the vrapi bone ids
const _hand2vrapi_bone_map = [0, 2, 3, 4, 5,19, 6, 7, 8, 20,  9, 10, 11, 21, 12, 13, 14, 22, 15, 16, 17, 18, 23, 1];

# This is a test pose for the left hand used only on desktop so the hand has a proper position
var _test_pose_left_ThumbsUp = [Quat(0, 0, 0, 1), Quat(0, 0, 0, 1), Quat(0.321311, 0.450518, -0.055395, 0.831098),
Quat(0.263483, -0.092072, 0.093766, 0.955671), Quat(-0.082704, -0.076956, -0.083991, 0.990042),
Quat(0.085132, 0.074532, -0.185419, 0.976124), Quat(0.010016, -0.068604, 0.563012, 0.823536),
Quat(-0.019362, 0.016689, 0.8093, 0.586839), Quat(-0.01652, -0.01319, 0.535006, 0.844584),
Quat(-0.072779, -0.078873, 0.665195, 0.738917), Quat(-0.0125, 0.004871, 0.707232, 0.706854),
Quat(-0.092244, 0.02486, 0.57957, 0.809304), Quat(-0.10324, -0.040148, 0.705716, 0.699782),
Quat(-0.041179, 0.022867, 0.741938, 0.668812), Quat(-0.030043, 0.026896, 0.558157, 0.828755),
Quat(-0.207036, -0.140343, 0.018312, 0.968042), Quat(0.054699, -0.041463, 0.706765, 0.704111),
Quat(-0.081241, -0.013242, 0.560496, 0.824056), Quat(0.00276, 0.037404, 0.637818, 0.769273),
]

var _t = 0.0

onready var hand_model : Spatial = $HandModel
onready var hand_pointer : Spatial = $HandModel/HandPointer

func _ready():
	_initialize_hands()

	ovr_hand_tracking = load("res://addons/godot_ovrmobile/OvrHandTracking.gdns");
	if (ovr_hand_tracking): ovr_hand_tracking = ovr_hand_tracking.new()

	ovr_utilities = load("res://addons/godot_ovrmobile/OvrUtilities.gdns")
	if (ovr_utilities): ovr_utilities = ovr_utilities.new()


func _process(delta_t):
	_update_hand_model(hand_model, hand_skel);
	_update_hand_pointer(hand_pointer)

	# If we are on desktop or don't have hand tracking we set a debug pose on the left hand
	if (controller_id == LEFT_TRACKER_ID && !ovr_hand_tracking):
		for i in range(0, _hand_bone_mappings.size()):
			hand_skel.set_bone_pose(_hand_bone_mappings[i], Transform(_test_pose_left_ThumbsUp[i]));

	_t += delta_t;
	if (_t > 1.0):
		_t = 0.0;

		# here we print every second the state of the pinches; they are mapped at the moment
		# to the first 4 joystick axis 0==index; 1==middle; 2==ring; 3==pinky
		print("%s Pinches: %.3f %.3f %.3f %.3f" %
			 ["Left" if controller_id == LEFT_TRACKER_ID else "Right", get_joystick_axis(0), get_joystick_axis(1), get_joystick_axis(2), get_joystick_axis(3)]);


func _initialize_hands():
	hand_skel = $HandModel/ArmatureLeft/Skeleton if controller_id == LEFT_TRACKER_ID else $HandModel/ArmatureRight/Skeleton

	_clear_bone_rest(hand_skel);
	_vrapi_bone_orientations.resize(24);


func _get_tracker_label():
	return "Oculus Tracked Left Hand" if controller_id == LEFT_TRACKER_ID else "Oculus Tracked Right Hand"


# The rotations we get from the OVR sdk are absolute and not relative
# to the rest pose we have in the model; so we clear them here to be
# able to use set pose
# This is more like a workaround then a clean solution but allows to use
# the hand model from the sample without major modifications
func _clear_bone_rest(skel):
	_vrapi_inverse_neutral_pose.resize(skel.get_bone_count());
	for i in range(0, skel.get_bone_count()):
		var bone_rest = skel.get_bone_rest(i);
		_vrapi_inverse_neutral_pose[_hand2vrapi_bone_map[i]] = bone_rest.basis.get_rotation_quat().inverse();
		skel.set_bone_pose(i, Transform(bone_rest.basis)); # use the original rest as pose
		bone_rest.basis = Basis();
		skel.set_bone_rest(i, bone_rest);


func _update_hand_model(model : Spatial, skel: Skeleton):
	if (ovr_hand_tracking): # check if the hand tracking API was loaded
		# scale of the hand model as reported by VrApi
		var ls = ovr_hand_tracking.get_hand_scale(controller_id);
		if (ls > 0.0): model.scale = Vector3(ls, ls, ls);

		var confidence = ovr_hand_tracking.get_hand_pose(controller_id, _vrapi_bone_orientations);
		if (confidence > 0.0):
			model.visible = true;
			for i in range(0, _hand_bone_mappings.size()):
				skel.set_bone_pose(_hand_bone_mappings[i], Transform(_vrapi_bone_orientations[i]));
		else:
			model.visible = false;
		return true;
	else:
		return false;


func _update_hand_pointer(model: Spatial):
	if (ovr_hand_tracking): # check if the hand tracking API was loaded
		if (ovr_hand_tracking.is_pointer_pose_valid(controller_id)):
			model.visible = true
			model.global_transform = ovr_hand_tracking.get_pointer_pose(controller_id)
		else:
			model.visible = false


func _on_LeftHand_pinch_pressed(button):
	if (button == FINGER_PINCH.INDEX_PINCH): print("Left Index Pinching");
	if (button == FINGER_PINCH.MIDDLE_PINCH):
		print("Left Middle Pinching");
		if (ovr_utilities):
			# use this for fade to black for example: here we just do a color change
			ovr_utilities.set_default_layer_color_scale(Color(0.9, 0.85, 0.3, 1.0));

	if (button == FINGER_PINCH.PINKY_PINCH): print("Left Pinky Pinching");
	if (button == FINGER_PINCH.RING_PINCH): print("Left Ring Pinching");


func _on_RightHand_pinch_pressed(button):
	if (button == FINGER_PINCH.INDEX_PINCH): print("Right Index Pinching");
	if (button == FINGER_PINCH.MIDDLE_PINCH):
		print("Right Middle Pinching");
		if (ovr_utilities):
			# use this for fade to black for example: here we just do a color change
			ovr_utilities.set_default_layer_color_scale(Color(0.5, 0.5, 0.5, 0.7));

	if (button == FINGER_PINCH.PINKY_PINCH): print("Right Pinky Pinching");
	if (button == FINGER_PINCH.RING_PINCH): print("Right Ring Pinching");


func _on_finger_pinch_release(button):
	if (button == FINGER_PINCH.MIDDLE_PINCH):
		if (ovr_utilities):
			# use this for fade to black for example: here we just do a color change
			ovr_utilities.set_default_layer_color_scale(Color(1.0, 1.0, 1.0, 1.0));

func _get_bone_angle_diff(ovrHandBone_id):
	var quat_diff = _vrapi_bone_orientations[ovrHandBone_id] * _vrapi_inverse_neutral_pose[ovrHandBone_id];
	var a = acos(clamp(quat_diff.w, -1.0, 1.0));
	return rad2deg(a);

# For simple gesture detection we can just look at the state of the fingers
# and distinguish between bent and straight
enum SimpleFingerState {
	Bent = 0,
	Straight = 1,
	Inbetween = 2,
}

# this is a very basic heuristic to detect if a finger is straight or not.
# It is a bit unprecise on the thumb and pinky but overall is enough for very simple
# gesture detection; it uses the accumulated angle of the 3 bones in each finger
func get_finger_state_estimate(finger):
	var confidence = ovr_hand_tracking.get_hand_pose(controller_id, _vrapi_bone_orientations);
	if confidence <= 0.0:
		return 0;
	
	var angle = 0.0;
	angle += _get_bone_angle_diff(_ovrHandFingers_Bone1Start[finger]+0);
	angle += _get_bone_angle_diff(_ovrHandFingers_Bone1Start[finger]+1);
	angle += _get_bone_angle_diff(_ovrHandFingers_Bone1Start[finger]+2);
	
	# !!TODO: thresholds need some finetuning here
	if (finger == ovrHandFingers.Thumb):
		if (angle <= 30): return SimpleFingerState.Straight;
		if (angle >= 35): return SimpleFingerState.Bent; # very low threshold here...
	elif (finger == ovrHandFingers.Pinky):
		if (angle <= 40): return SimpleFingerState.Straight;
		if (angle >= 60): return SimpleFingerState.Bent;
	else:
		if (angle <= 35): return SimpleFingerState.Straight;
		if (angle >= 75): return SimpleFingerState.Bent;
	return SimpleFingerState.Inbetween;

