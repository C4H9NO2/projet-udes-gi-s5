extends RayCast3D

@export var periode_s := 0.05
@export var ecart_type_cm := 0.5

var distance_cm := -1.0
var _temps := 0.0

func _physics_process(delta: float) -> void:
	_temps += delta
	if _temps < periode_s:
		return
	_temps = 0.0
	if is_colliding():
		var d := global_position.distance_to(get_collision_point())
		distance_cm = d * 100.0 + randfn(0.0, ecart_type_cm)
	else:
		distance_cm = -1.0
