extends RigidBody3D

signal tombe

@export var chemin_point_depart: NodePath = ^"../PiCar/point_bille"
@export var hauteur_chute := 0.05

var est_tombee := false

func _ready() -> void:
	if not has_node(chemin_point_depart):
		push_warning("position du plateau introuvable : la bille reste ou elle est")
		return
	var point := get_node(chemin_point_depart) as Node3D
	global_position = point.global_position
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

func _physics_process(_delta: float) -> void:
	if not est_tombee and global_position.y < hauteur_chute:
		est_tombee = true
		print("la bille est tombée")
		tombe.emit()
