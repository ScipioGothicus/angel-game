extends Node3D

const PLAYER_SCENE_PATH = "res://scenes/player.tscn"

@export var player_spawn_position = Vector3(0.0, 25.0, 0.0)

func add_player(peer_id):
	var player = load(PLAYER_SCENE_PATH).instantiate()
	player.name = str(peer_id)
	add_child(player)

# used for disconnects
func remove_player(peer_id):
	var player = get_node_or_null(str(peer_id))
	# remove player if it exists
	if player:
		player.queue_free()
		
func upnp_setup(port):
	var upnp = UPNP.new()
	
	# todo: add more detailed error messages
	var discover_result = upnp.discover()
	assert(discover_result == UPNP.UPNP_RESULT_SUCCESS, \
		"UPNP Discover failed with error: %s" % discover_result)
		
	assert(upnp.get_gateway() and upnp.get_gateway().is_valid_gateway(), \
		"UPNP Invalid gateway")
		
	var map_result = upnp.add_port_mapping(port)
	assert(map_result == UPNP.UPNP_RESULT_SUCCESS, \
		"UPNP Port Mapping failed with error: %s" % discover_result)
	
	print("UPNP connection successful with join address %s" % upnp.query_external_address())


func _on_world_border_body_entered(body):
	if body is CharacterBody3D:
		body.position = player_spawn_position
