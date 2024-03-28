extends CharacterBody3D

const SPEED = 5.0
const CROUCH_SPEED = 2.5
const RUN_SPEED = 7.5

# change FOV of camera depending on movement state
const SPRINT_FOV = 90.0
const CAM_FOV = 75.0
const CROUCH_FOV = 60.0

# adds a "head tilt" effect when freelooking
const FREELOOK_TILT = 5.0

# slide variables
var slide_timer = 0.0
@export var slide_max = 1.0 # seconds
@export var slide_speed = 5.0
var slide_vector = Vector2.ZERO

# allows a little bit of time to press crouch after releasing sprint to slide
var slide_coyote = 0.0
@export var slide_coyote_max = 0.5

const JUMP_VELOCITY = 6
const CROUCH_DEPTH = -0.5

# state machine variables
var sprinting = false
var crouching = false
var freelooking = false
var sliding = false
var double_jumped = false
var paused = false

# access various nodes
@onready var head_pivot = $freelook_pivot/pivot
@onready var freelook_pivot = $freelook_pivot
@onready var camera = $freelook_pivot/pivot/camera
@onready var collision = $collision
@onready var crouch_collision = $crouch_collision
@onready var bonk_check = $bonk_check
@onready var debug_label = $"../RichTextLabel"
@onready var mesh = $mesh
@onready var slap_sprite = $freelook_pivot/pivot/camera/slap_sprite
@onready var slap_ray = $freelook_pivot/pivot/camera/slap_ray
@onready var slap_sound = $slap_sound
@onready var woosh_sound = $woosh_sound
@onready var pause_menu = $pause_menu/CanvasLayer

# look sensitivity
var mouse_sensitivity = 0.2
# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# linear interpolation speeds
var lerp_speed = 10.0
var air_lerp = 2.5

# player movement speed constant
var current_speed = SPEED
# player's desired movement direction, goes in hand with velocity
var direction = Vector3.ZERO

func _enter_tree():
	# the server assigns a player object to each computer on network
	set_multiplayer_authority(str(name).to_int())

func _ready():
	# don't execute code if you are not the player object connected to your computer
	if not is_multiplayer_authority(): return
	
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	
	# set position of players above the level
	position = Vector3(0.0, 25.0, 0.0)
	
	# set the camera to current after authority has been assigned to resolve bugs
	camera.current = true

func _input(event):
	if not is_multiplayer_authority(): return
	
	# check for mouse movement
	if event is InputEventMouseMotion and not paused:
		# freelook around a different pivot to ensure the player does not rotate
		if freelooking:
			freelook_pivot.rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		# rotate body when looking normally
		else:
			rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))

		# head turning
		head_pivot.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head_pivot.rotation.x = clampf(head_pivot.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _process(_delta):
	if not multiplayer.has_multiplayer_peer(): return
	if not is_multiplayer_authority(): return
	
	if Input.is_action_just_pressed("pause") and not paused:
		pause_menu.visible = true
		paused = true
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif Input.is_action_just_pressed("pause") and paused:
		pause_menu.visible = false
		paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta):
	# fixes errors when _physics_process tries to run another cycle after
	# the multiplayer peer has been disconnected
	if not multiplayer.has_multiplayer_peer(): return
	if not is_multiplayer_authority(): return
	
	# get the input direction and handle the movement/deceleration
	var input_dir 
	if not paused:
		input_dir = Input.get_vector("left", "right", "up", "down")
	else:
		input_dir = Vector2.ZERO
		
	# Handle jump.
	if (Input.is_action_just_pressed("jump") and is_on_floor()) and not paused:
		# cancel sliding with a jump
		if sliding:
			# don't jump fully; do a cute little hop instead
			velocity.y = JUMP_VELOCITY/2.5
			# we don't want to be able to keep sliding; reset the coyote timer, too
			sliding = false
			slide_coyote = 0.0
		else:
			# jump normally
			velocity.y = JUMP_VELOCITY
	elif (Input.is_action_just_pressed("jump") and not is_on_floor() and not double_jumped) and not paused:
		velocity.y = JUMP_VELOCITY
		double_jumped = true
	
	# handle sprinting
	# you cannot crouch and sprint/slide at the same time
	if (Input.is_action_pressed("sprint") and not sliding and not crouching) and not paused:
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
	if (Input.is_action_pressed("crouch") or sliding) and not paused:
		# squat the camera down
		head_pivot.position.y = lerp(head_pivot.position.y, CROUCH_DEPTH, delta*lerp_speed)
		# scale and move the mesh as well to look like crouching
		mesh.scale.y = lerp(mesh.scale.y, 0.5, delta * lerp_speed)
		mesh.position.y = lerp(mesh.position.y, -0.5, delta * lerp_speed)
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
	# todo: make this not check every frame
	elif !bonk_check.is_colliding():
		head_pivot.position.y = lerp(head_pivot.position.y, 0.0, delta*lerp_speed)
		mesh.scale.y = lerp(mesh.scale.y, 1.0, delta * lerp_speed)
		mesh.position.y = lerp(mesh.position.y, 0.0, delta * lerp_speed)
		collision.disabled = false
		crouch_collision.disabled = true
		current_speed = lerp(current_speed, SPEED, delta*lerp_speed)
		crouching = false
		
	# handle sliding and ending sliding
	if sliding:
		# count down how long the player remains sliding
		slide_timer -= delta
		# stop sliding (and freelooking) when the timer is up
		if slide_timer <= 0.0:
			sliding = false
		freelooking = false
		
	# handle freelooking
	if (Input.is_action_pressed("freelook") or sliding) and not paused:
		freelooking = true
		# rotate the camera to simulate looking over a shoulder
		freelook_pivot.rotation.y = clampf(freelook_pivot.rotation.y, deg_to_rad(-119), deg_to_rad(119))
		camera.rotation.z = -deg_to_rad(freelook_pivot.rotation.y*FREELOOK_TILT)
	else:
		# lerp back towards normal rotation
		freelook_pivot.rotation.y = lerp(freelook_pivot.rotation.y, 0.0, delta*lerp_speed)
		camera.rotation.z = lerp(camera.rotation.z, 0.0, delta*lerp_speed)
		freelooking = false
	
	# fixes a bug where holding left click and pausing keeps the sprite visible
	if slap_sprite.visible and paused:
		slap_sprite.visible = false
		slap_sprite.frame = 0
	
	# handle slapping
	if Input.is_action_pressed("primary_action") and not paused:
		slap_sprite.visible = true
		# hold the first sprite when primary action is held
		slap_sprite.frame = 0
	if Input.is_action_just_released("primary_action") and not paused:
		# move to next sprite, then start playing the animation to make the anim responsive
		slap_sprite.frame=1
		slap_sprite.play("default")
		# if another player is within bounds...
		
		if slap_ray.is_colliding():
			# makes code less verbose
			var slapped_entity = slap_ray.get_collider()
			# make sure the entity getting slapped is not self
			if slapped_entity.has_method("get_slapped") and not slapped_entity.name == name:
				# play the slap sound for the slapper
				slap_sound.play()
				# get what player was slapped and at what angle, position, etc. with a normal
				slap_ray.get_collider().get_slapped.rpc_id(slap_ray.get_collider().get_multiplayer_authority(), slap_ray.get_collision_normal())
			else:
				# if not a player object, woosh
				woosh_sound.play()
		else:
			# if you just completely miss anyways
			woosh_sound.play()
	
	# handle ground and midair movement
	if is_on_floor():
		# reset double jump check
		double_jumped = false
		# smooth movement (acceleration/deceleration) via lerp and a lerp movement speed
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*lerp_speed)
	else:
		# calculate gravity
		velocity.y -= gravity * delta
		# make movement in midair much less responsive for realism via a lerp function and constant speed (air_lerp)
		direction = lerp(direction, (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized(), delta*air_lerp)
	
	# handle sliding movement
	if sliding:
		# slide towards movement direction but don't allow control
		direction = (transform.basis * Vector3(slide_vector.x, 0.0, slide_vector.y)).normalized()
	
	# if moving
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
		
		# if moving by sliding
		if sliding:
			# make the speed gradually slow by multiplying by the slide timer
			# the .1 is to add some speed to the sliding on initiation & falloff
			velocity.x = direction.x * (slide_timer + 0.1) * slide_speed
			velocity.z = direction.z * (slide_timer + 0.1) * slide_speed
			
	# otherwise, gradually slow down
	else:
		velocity.x = move_toward(velocity.x, 0, current_speed)
		velocity.z = move_toward(velocity.z, 0, current_speed)

	move_and_slide()
	# debug GUI text
	debug_label.text = "Slide Coyote Time: %s" % slide_coyote

@rpc("any_peer")
func get_slapped(normal):
	# set the player's direction to be the negative normal (move away from the slapper) multiplied by a constant speed
	# the normal is passed earlier by the raycast collision
	direction = -normal * 3.0
	# play the slap sound for the entity being slapped
	slap_sound.play()
	# move upwards too instead of just in a direction (the normal doesn't contain a y value)
	velocity.y = 4.0


func _on_disconnect_pressed():
	if multiplayer.is_server():
		multiplayer.server_disconnected.emit()
	elif not multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
		var root = get_tree().root.get_node_or_null("Root")
		var world = get_tree().root.get_node_or_null("Root/World")
		root.remove_child(world)
	

