extends Node3D

const PLAYER_SCENE_PATH = "player.tscn"

func add_player(peer_id):
	var player = load(PLAYER_SCENE_PATH).instantiate()
	player.name = str(peer_id)
	add_child(player)
	print("player added")

func remove_player(peer_id):
	var player = get_node_or_null(str(peer_id))
	if player:
		player.queue_free()
