extends Node3D

var enet_peer = ENetMultiplayerPeer.new()
const PORT = 50993
const WORLD_SCENE_PATH = "res://world.tscn"
@onready var root = $"."
@onready var main_menu = $Menu/CanvasLayer

# Called when the node enters the scene tree for the first time.

func _ready():
	ResourceLoader.load_threaded_request(WORLD_SCENE_PATH)

func _process(delta):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

func _on_host_button_pressed():
	main_menu.hide()
	
	var world = load(WORLD_SCENE_PATH).instantiate()
	root.add_child(world)
	
	print("ready")
	
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	multiplayer.peer_connected.connect(world.add_player)
	multiplayer.peer_disconnected.connect(world.remove_player)

	world.add_player(multiplayer.get_unique_id())
	
	
func _on_join_button_pressed():
	main_menu.hide()
	
	var world = load(WORLD_SCENE_PATH).instantiate()
	root.add_child(world)
	
	enet_peer.create_client("localhost", PORT)
	multiplayer.multiplayer_peer = enet_peer
