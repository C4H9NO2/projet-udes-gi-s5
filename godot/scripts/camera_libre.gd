extends Camera3D

@export var speed: float = 10.0
@export var sprint_multiplier: float = 3.0
@export var mouse_sensitivity: float = 0.002
@export var pitch_limit: float = 1.5 # ~85°

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
		rotation.x = clampf(rotation.x, -pitch_limit, pitch_limit)

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S): dir.z += 1.0
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_E): dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q): dir.y -= 1.0

	if dir == Vector3.ZERO:
		return

	var spd := speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		spd *= sprint_multiplier

	# déplacement relatif à l'orientation de la caméra
	global_position += (global_transform.basis * dir.normalized()) * spd * delta
