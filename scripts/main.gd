extends Node3D

var enet_peer = ENetMultiplayerPeer.new()
const PORT = 50993
const WORLD_SCENE_PATH = "res://scenes/world.tscn"
var world

@onready var root = $"."
@onready var main_menu = $Menu/CanvasLayer
@onready var address = $Menu/CanvasLayer/PanelContainer/MarginContainer/VBoxContainer/Address

func _ready():
	multiplayer.server_disconnected.connect(on_server_disconnect)
	ResourceLoader.load_threaded_request(WORLD_SCENE_PATH)

func _process(_delta):
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()

func _on_host_button_pressed():
	main_menu.hide()
	
	world = load(WORLD_SCENE_PATH).instantiate()
	root.add_child(world)
	
	enet_peer.create_server(PORT)
	
	multiplayer.multiplayer_peer = enet_peer
	
	multiplayer.peer_connected.connect(on_player_connect)
	multiplayer.peer_disconnected.connect(on_player_disconnect)

	world.add_player(multiplayer.get_unique_id())
	
	if not address.text:
		world.upnp_setup(PORT)
	
	
func _on_join_button_pressed():
	main_menu.hide()
	
	world = load(WORLD_SCENE_PATH).instantiate()
	root.add_child(world)

	enet_peer.create_client(address.text, PORT)
	multiplayer.multiplayer_peer = enet_peer

func on_player_connect(peer_id):
	world.add_player(peer_id)
	
func on_player_disconnect(peer_id):
	world.remove_player(peer_id)
	#if multiplayer.get_peers().has(peer_id):
		#multiplayer.multiplayer_peer.disconnect_peer(peer_id)

func on_server_disconnect():
	multiplayer.multiplayer_peer.close()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null
	root.remove_child(world)
