extends CharacterBody3D

const SPEED = 5.0
const CROUCH_SPEED = 2.5
const RUN_SPEED = 7.5

const SPRINT_FOV = 90.0
const CAM_FOV = 75.0
const CROUCH_FOV = 60.0

const FREELOOK_TILT = 5.0

# slide variables
var slide_timer = 0.0
@export var slide_max = 1.0 # seconds
var slide_vector = Vector2.ZERO
@export var slide_coyote_max = 0.5
var slide_coyote = 0.0 # allows a little bit of time to press crouch after releasing sprint to slide
@export var slide_speed = 5.0

const JUMP_VELOCITY = 6
const CROUCH_DEPTH = -0.5

# state machine variables
var sprinting = false
var crouching = false
var freelooking = false
var sliding = false

# access various nodes
@onready var head_pivot = $freelook_pivot/pivot
@onready var freelook_pivot = $freelook_pivot
@onready var camera = $freelook_pivot/pivot/camera
@onready var collision = $collision
@onready var crouch_collision = $crouch_collision
@onready var bonk_check = $bonk_check
@onready var debug_label = $"../RichTextLabel"

var mouse_sensitivity = 0.2
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# linear interpolation speeds
var lerp_speed = 10.0
var air_lerp = 2.5

var current_speed = SPEED
var direction = Vector3.ZERO

func _enter_tree():
	set_multiplayer_authority(str(name).to_int())

func _ready():
	# don't execute code if you are not a given player
	if not is_multiplayer_authority(): return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	camera.current = true

func _input(event):
	if not is_multiplayer_authority(): return
	if event is InputEventMouseMotion:
		# freelook around a different pivot to ensure the player does not rotate
		if freelooking:
			freelook_pivot.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		# rotate body when looking normally
		else:
			rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))

		# head turning
		head_pivot.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head_pivot.rotation.x = clampf(head_pivot.rotation.x, deg_to_rad(-89), deg_to_rad(89))
		
func _physics_process(delta):
	if not is_multiplayer_authority(): return
	
	# Get the input direction and handle the movement/deceleration.
	var input_dir = Input.get_vector("left", "right", "up", "down")
	
	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		# cancel sliding with a jump
		if sliding:
			# don't jump fully; do a cute little hop instead
			velocity.y = JUMP_VELOCITY/2.5
			sliding = false
			# we don't want to be able to keep sliding; reset the coyote timer, too
			slide_coyote = 0.0
		else:
			velocity.y = JUMP_VELOCITY
	
	# handle sprinting
	# you cannot crouch and sprint/slide at the same time
	if Input.is_action_pressed("sprint") and not sliding and not crouching:
		# start the sliding coyote timer after sprinting
		slide_coyote = slide_coyote_max
		current_speed = lerp(current_speed, RUN_SPEED, delta*lerp_speed)
		camera.fov = lerp(camera.fov, SPRINT_FOV, delta*lerp_speed)
		sprinting = true
		crouching = false
	else:
		# decrement the slide coyote timer by the frame timing
		if slide_coyote >= 0.0:
			slide_coyote -= delta
		current_speed = lerp(current_speed, SPEED, delta*lerp_speed)
		camera.fov = lerp(camera.fov, CAM_FOV, delta*lerp_speed)
		sprinting = false

	# handle crouching
	if Input.is_action_pressed("crouch") or sliding:
		# squat the camera down
		head_pivot.position.y = lerp(head_pivot.position.y, CROUCH_DEPTH, delta*lerp_speed)
		# switch collision shapes to make crouch collision small
		collision.disabled = true
		crouch_collision.disabled = false
		current_speed = lerp(current_speed, CROUCH_SPEED, delta*lerp_speed)
		# begin sliding logic
		# checking if player has recently sprinted & is moving
		if slide_coyote > 0.0 and input_dir != Vector2.ZERO:  
			sliding = true
			slide_timer = slide_max
			slide_vector = input_dir
			freelooking = true
		crouching = true
		sprinting = false
	# ensure there is room to stand up; if so, stand up
	elif !bonk_check.is_colliding():
		head_pivot.position.y = lerp(head_pivot.position.y, 0.0, delta*lerp_speed)
		collision.disabled = false
		crouch_collision.disabled = true
		current_speed = lerp(current_speed, SPEED, delta*lerp_speed)
		crouching = false
		
	# handle sliding and ending sliding
	if sliding:
		slide_timer -= delta
		if slide_timer <= 0.0:
			sliding = false
		freelooking = false

	# handle freelooking
	if Input.is_action_pressed("freelook") or sliding:
		freelooking = true
		# rotate the camera to simulate looking over a shoulder
		freelook_pivot.rotation.y = clampf(freelook_pivot.rotation.y, deg_to_rad(-119), deg_to_rad(119))
		camera.rotation.z = -deg_to_rad(freelook_pivot.rotation.y*FREELOOK_TILT)
	else:
		# lerp back towards normal rotation
		freelook_pivot.rotation.y = lerp(freelook_pivot.rotation.y, 0.0, delta*lerp_speed)
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta*lerp_speed)
		freelooking = false
	
	# handle ground and midair movement
	if is_on_floor():
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*lerp_speed)
	else:
		velocity.y -= gravity * delta
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*air_lerp)
	
	# handle sliding movement
	if sliding:
		direction = (transform.basis * Vector3(slide_vector.x, 0.0, slide_vector.y)).normalized()
	
	# if moving
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
		# if moving by sliding
		if sliding:
			# make the speed gradually slow by multiplying by the slide timer
			velocity.x = direction.x * (slide_timer + 0.1) * slide_speed
			velocity.z = direction.z * (slide_timer + 0.1) * slide_speed
	# otherwise, gradually slow down
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	# debug GUI text
	debug_label.text = "Slide Coyote Time: %s" % slide_coyote
