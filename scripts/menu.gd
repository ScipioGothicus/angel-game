extends Node2D

const MAIN_SCENE_PATH = "res://scenes/main.tscn"

func _ready():
	ResourceLoader.load_threaded_request(MAIN_SCENE_PATH)

func _on_host_button_pressed():
	var main_scene = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH)
	get_tree().change_scene_to_packed(main_scene)

func _on_join_button_pressed():
	pass
