extends Node3D

const RAY_LENGTH = 1000
const MAX_PROXIMITY_LENGHT = 0.1

var ray = null
var ray_collision_point = Vector3.ZERO
var distance = 0.0
var wall_avoidance = false


# Engine power
var acceleration = 0.01
var speed = 0.05
# How quickly the car turns
var rot_acceleration = 0.0075

var lfs = 0
var steer_dir = 0

var nfsm = 0
var lfs_simulated_ignored = false

const max_speed = 0.2	# Speed is float from 0.0 to 1.0
const mid_speed = 0.1	# Speed is float from 0.0 to 1.0
const low_speed = 0.05	# Speed is float from 0.0 to 1.0

# Called when the node enters the scene tree for the first time.
func _ready():
	ray = get_node("capteur_ultrasons")
	lfs = $capteur_ligne
	nfsm = $"../NetworkFSM"


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	car_speed(delta)
	
	if nfsm.data_received['distance'] < 30 && nfsm.data_received['distance'] > 20:
		wall_avoidance = true
		
	if wall_avoidance:
		wall_avoidance_loop(delta)	
	else:
		line_follower_car_angle(delta)
		
	
	# If websocket connection
	if nfsm.current_state == $"../NetworkFSM/NetworkProcessState" :
		#print(nfsm.data_received['line_follower'])
		nfsm.data_to_send["velocity"] = speed
		nfsm.data_to_send["direction"] = steer_dir
		
		lfs_simulated_ignored = true
	else:
		
		lfs_simulated_ignored = false

func _physics_process(delta):
	#pass
# Ray casting for distance
	if !nfsm.current_state == $"../NetworkFSM/NetworkProcessState" :
		if ray.is_colliding():
			ray_collision_point = ray.get_collision_point()
			distance = ray_collision_point.distance_to(ray.global_position)
			#print(ray_collision_point)
			print(distance)
			if distance < 0.3:
				wall_avoidance = true	# Start the collision avoidance sequence
		else:
			pass
		deplacer(delta)

const turn_angle_mid = 0.5
const turn_angle_big = 1
const turn_accel = 2
var dir_buf = []
func line_follower_car_angle(delta):
	var temp_dir = steer_dir
	# Should apply smoothing with delta for direction. 
	# The same way/feeling that Trackmania does it
	if lfs_simulated_ignored:
		if nfsm.data_received['line_follower'][2]:
			#print("Middle")
			temp_dir = 0
		elif nfsm.data_received['line_follower'][4]:
			#print("Right")
			if temp_dir > -turn_angle_big:
				temp_dir += -delta * turn_accel
			else:
				temp_dir = -turn_angle_big
		elif nfsm.data_received['line_follower'][0]:
			#print("Left")
			if temp_dir < turn_angle_big:
				temp_dir += delta * turn_accel
			else:
				temp_dir = turn_angle_big
		elif nfsm.data_received['line_follower'][1]:
			#print("Middle Left")
			if temp_dir < turn_angle_mid:
				temp_dir += delta * turn_accel
			else:
				temp_dir = turn_angle_mid
			speed = low_speed
		elif nfsm.data_received['line_follower'][3]:
			#print("Middle Right")
			if temp_dir > -turn_angle_mid:
				temp_dir += -delta * turn_accel
			else:
				temp_dir = -turn_angle_mid
			speed = low_speed
		else:
			# NEVER COMES HERE. THATS THE PROBLEM
			speed = low_speed
			temp_dir = 0
	else:
		if lfs.line_follower_array[2]:
			#print("Middle")
			temp_dir = 0
		elif lfs.line_follower_array[4]:
			#print("Right")
			if temp_dir > -turn_angle_big:
				temp_dir += -delta * turn_accel
			else:
				temp_dir = -turn_angle_big
		elif lfs.line_follower_array[0]:
			#print("Left")
			if temp_dir < turn_angle_big:
				temp_dir += delta * turn_accel
			else:
				temp_dir = turn_angle_big
		elif lfs.line_follower_array[1]:
			#print("Middle Left")
			if temp_dir < turn_angle_mid:
				temp_dir += delta * turn_accel
			else:
				temp_dir = turn_angle_mid
			speed = low_speed
		elif lfs.line_follower_array[3]:
			#print("Middle Right")
			if temp_dir > -turn_angle_mid:
				temp_dir += -delta * turn_accel
			else:
				temp_dir = -turn_angle_mid
			speed = low_speed
		else:
			# NEVER COMES HERE. THATS THE PROBLEM
			print("Oh it does come here")
			var mean = average(dir_buf)
			if mean > turn_angle_mid:
				temp_dir = turn_angle_big
			elif mean >= 0 && mean < turn_angle_mid:
				temp_dir = turn_angle_mid
				
			speed = low_speed
			#temp_dir = 0
		
	# All light sensor activated -> Need to stop
	if (lfs.line_follower_array[0] || nfsm.data_received['line_follower'][0]) && (lfs.line_follower_array[4] || nfsm.data_received['line_follower'][4]) && (lfs.line_follower_array[3] || nfsm.data_received['line_follower'][3]) && (lfs.line_follower_array[1] || nfsm.data_received['line_follower'][1]) && (lfs.line_follower_array[2] || nfsm.data_received['line_follower'][2]):
		speed = 0
	
	# Apply Steer dir
	steer_dir = temp_dir
	
	
	if len(dir_buf) > 15:
		#print("Here")
		#print(dir_buf)
		dir_buf.pop_front()
		dir_buf.append(temp_dir)
	else:
		dir_buf.append(temp_dir)	
	#print(steer_dir)


func car_speed(delta):
	var temp_speed = speed
	if speed == 0:
		temp_speed = 0
	elif temp_speed < max_speed:
		temp_speed += delta
	else:
		temp_speed = speed
	speed = temp_speed

var temp_time = 0.0
const TEST = 0.0
func wall_avoidance_loop(delta):
# Ive should have put the sequence in a list and loop through the list
# But im lazy and the code wont ever be used....

	print("IN WALL AVOIDANCE LOOP")
	if temp_time < 1.3 && temp_time >= 0.0:
		steer_dir = turn_angle_big
		speed = 0
	elif temp_time < 2.0 && temp_time >= 1.3:
		steer_dir = 0
		speed = low_speed
	elif temp_time < 4.5 && temp_time >= 2.0:
		steer_dir = -turn_angle_big
		speed = 0
	elif temp_time < 5.0 && temp_time >= 4.5:
		steer_dir = 0
		speed = low_speed
	elif temp_time < 7.5 && temp_time >= 5.0:
		steer_dir = -turn_angle_big
		speed = 0
	elif temp_time < 8.2 && temp_time >= 7.5:
		steer_dir = 0
		speed = low_speed
	elif temp_time < 9.5 && temp_time >= 8.2:
		steer_dir = turn_angle_big
		speed = 0
	else:
		wall_avoidance = false
		temp_time = 0.0 
	
	temp_time += delta

func average(numbers: Array) -> float:
	var sum := 0.0
	for n in numbers:
		sum += n
	return sum / numbers.size()


#simulation deplacement de la voiture
#Transforme speed (0 a 1) et steer_dir (-1 a 1) du code des profs
#en vitesse (m/s) et angle de roues, avec les limites du config.json.
const EMPATTEMENT = 0.142	#distance entre les essieux (m) (picar.blend)

@export var delai_depart_s := 1.0	#attendre que la bille se pose avant de partir
@export var mode_test_acceleration := false	#ligne droite, ignore la ligne
@export var vitesse_test_m_s := 0.5
@export var duree_test_s := 1.5

var vitesse_actuelle := 0.0
var angle_actuel := 0.0
var temps_ecoule := 0.0

func deplacer(delta: float) -> void:
	temps_ecoule += delta
	if temps_ecoule < delai_depart_s:
		return
	var cfg = Config.donnees

	var v_cible = speed * 100.0 * cfg.get("vitesse_m_s_par_unite_pwm", 0.005)
	var angle_cible = steer_dir * cfg.get("angle_braquage_max_deg", 45.0)
	if mode_test_acceleration:
		angle_cible = 0.0
		v_cible = vitesse_test_m_s if temps_ecoule < delai_depart_s + duree_test_s else 0.0

	#limites physiques
	var a_max = cfg.get("acceleration_max_m_s2", 0.72)
	if abs(v_cible) < abs(vitesse_actuelle):
		a_max = cfg.get("deceleration_max_m_s2", 0.72)
	vitesse_actuelle = move_toward(vitesse_actuelle, v_cible, a_max * delta)
	angle_actuel = move_toward(angle_actuel, angle_cible, cfg.get("vitesse_braquage_deg_s", 300.0) * delta)

	#tourner puis avancer (avant = -Z)
	var omega = vitesse_actuelle / EMPATTEMENT * tan(deg_to_rad(angle_actuel))
	#tourner et avancer en même temps : avec Sync to Physics,
	#rotate_y() suivi d'un changement de position perd la rotation.
	var t := global_transform
	t.basis = t.basis.rotated(Vector3.UP, omega * delta)
	t.origin += -t.basis.z * vitesse_actuelle * delta
	global_transform = t
