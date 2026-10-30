extends Node3D

#meme nom et meme format que le capteur des profs : 5 valeurs 0/1, index 0 = gauche
var line_follower_array := [0, 0, 0, 0, 0]

@onready var rayons := [$ir_0, $ir_1, $ir_2, $ir_3, $ir_4]

func _physics_process(_delta: float) -> void:
	for i in 5:
		line_follower_array[i] = 1 if rayons[i].is_colliding() else 0
