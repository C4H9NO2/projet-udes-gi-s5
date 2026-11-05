extends Node3D

const RAY_LENGTH = 1000
const MAX_PROXIMITY_LENGHT = 0.1

var vitesse = 0.0

#Capteur de distance
var ray = null
var ray_collision_point = Vector3.ZERO
var wall_avoidance = false
var distance = 0.0

#Constante du fichier config
var vitesse_max = 0.0
var vitesse_moyenne = 0.0
var vitesse_faible = 0.0
var distance_arret = 0.0
var accel_max = 0.0


# How quickly the car turns
var rot_acceleration = 0.72

var lfs = 0
var steer_dir = 0

var nfsm = 0
var lfs_simulated_ignored = false

# Called when the node enters the scene tree for the first time.
func _ready():
	ray = get_node("capteur_ultrasons")
	lfs = $capteur_ligne
	nfsm = $"../NetworkFSM"
	
	#Constante lu dans le fichier config
	vitesse_max = Config.donnees.get("vitesse_max_m_s")
	vitesse_moyenne = Config.donnees.get("vitesse_moyenne_m_s")
	vitesse_faible = Config.donnees.get("vitesse_faible_m_s")
	accel_max = Config.donnees.get("acceleration_max_m_s2")
	distance_arret = Config.donnees.get("distance_arret")
	
	_recuperer_roues()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	
	if nfsm.data_received['distance'] < 30 && nfsm.data_received['distance'] > 20:
		wall_avoidance = true
		
	if wall_avoidance:
		wall_avoidance_loop(delta)	
	else:
		line_follower_car_angle(delta)
		
	
	# If websocket connection
	if nfsm.current_state == $"../NetworkFSM/NetworkProcessState" :
		#print(nfsm.data_received['line_follower'])
		nfsm.data_to_send["velocity"] = vitesse
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
			if distance < distance_arret:
				wall_avoidance = true	# Start the collision avoidance sequence
		else:
			pass
		deplacer(delta)

var vitesse_cible = 0.0
const turn_angle_mid = 0.5
const turn_angle_big = 1
const turn_accel = 1
var dir_buf = []
func line_follower_car_angle(delta):
	var steer_target := 0.0

	var sensors

	if lfs_simulated_ignored:
		sensors = nfsm.data_received['line_follower']
	else:
		sensors = lfs.line_follower_array

	# Centre
	if sensors[2]:
		vitesse_cible = vitesse_max
		steer_target = 0.0

	# Léger gauche
	elif sensors[1]:
		vitesse_cible = vitesse_moyenne
		steer_target = turn_angle_mid

	# Léger droite
	elif sensors[3]:
		vitesse_cible = vitesse_moyenne
		steer_target = -turn_angle_mid

	# Fort gauche
	elif sensors[0]:
		vitesse_cible = vitesse_faible
		steer_target = turn_angle_big

	# Fort droite
	elif sensors[4]:
		vitesse_cible = vitesse_faible
		steer_target = -turn_angle_big

	# Ligne perdue
	else:
		var mean = average(dir_buf)

		vitesse_cible = vitesse_faible

		if mean > turn_angle_mid:
			steer_target = turn_angle_big
		elif mean >= 0:
			steer_target = turn_angle_mid
		elif mean < -turn_angle_mid:
			steer_target = -turn_angle_big
		else:
			steer_target = -turn_angle_mid

	# Tous les capteurs actifs -> arrêt
	if (lfs.line_follower_array[0] || nfsm.data_received['line_follower'][0]) \
	and (lfs.line_follower_array[1] || nfsm.data_received['line_follower'][1]) \
	and (lfs.line_follower_array[2] || nfsm.data_received['line_follower'][2]) \
	and (lfs.line_follower_array[3] || nfsm.data_received['line_follower'][3]) \
	and (lfs.line_follower_array[4] || nfsm.data_received['line_follower'][4]):

		vitesse_cible = 0.0

	# Braquage progressif
	steer_dir = move_toward(
		steer_dir,
		steer_target,
		turn_accel * delta
	)

	# Vitesse progressive
	vitesse = move_toward(
		vitesse,
		vitesse_cible,
		accel_max * delta
	)

	# Historique des directions
	if len(dir_buf) > 15:
		dir_buf.pop_front()

	dir_buf.append(steer_dir)


var temp_time = 0.0
const TEST = 0.0
func wall_avoidance_loop(delta):
# Ive should have put the sequence in a list and loop through the list
# But im lazy and the code wont ever be used....

	print("IN WALL AVOIDANCE LOOP")
	if temp_time < 1.3 && temp_time >= 0.0:
		steer_dir = turn_angle_big
		vitesse = 0
	elif temp_time < 2.0 && temp_time >= 1.3:
		steer_dir = 0
		vitesse = vitesse_faible
	elif temp_time < 4.5 && temp_time >= 2.0:
		steer_dir = -turn_angle_big
		vitesse = 0
	elif temp_time < 5.0 && temp_time >= 4.5:
		steer_dir = 0
		vitesse = vitesse_faible
	elif temp_time < 7.5 && temp_time >= 5.0:
		steer_dir = -turn_angle_big
		vitesse = 0
	elif temp_time < 8.2 && temp_time >= 7.5:
		steer_dir = 0
		vitesse = vitesse_faible
	elif temp_time < 9.5 && temp_time >= 8.2:
		steer_dir = turn_angle_big
		vitesse = 0
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
const RAYON_ROUE = 0.0325	#rayon des roues (m) (picar.blend)
const VOIE = 0.11	# distance entre les centres des roues gauche/droite (m)
const X_ROUE_G = -VOIE * 0.5	# position en x du centre de la roue gauche (m)
const X_ROUE_D = VOIE * 0.5	# position en x du centre de la roue droite (m)

@export var delai_depart_s := 3.0	#attendre que la bille se pose avant de partir
@export var mode_test_acceleration := false	#ligne droite, ignore la ligne
@export var vitesse_test_m_s := 0.5
@export var duree_test_s := 1.5

var vitesse_actuelle := 0.0
var angle_actuel := 0.0
var temps_ecoule := 0.0

#roues (pour pouvoir les animer)
var roue_av_g: Node3D = null
var roue_av_d: Node3D = null
var roue_ar_g: Node3D = null
var roue_ar_d: Node3D = null

# rotation actuelles des roues
var spin_av_g := 0.0
var spin_av_d := 0.0
var spin_ar_g := 0.0
var spin_ar_d := 0.0

func _recuperer_roues() -> void:
	roue_av_g = find_child("roue_av_g", true, false) as Node3D
	roue_av_d = find_child("roue_av_d", true, false) as Node3D
	roue_ar_g = find_child("roue_ar_g", true, false) as Node3D
	roue_ar_d = find_child("roue_ar_d", true, false) as Node3D

func deplacer(delta: float) -> void:
	temps_ecoule += delta
	
	if temps_ecoule < delai_depart_s:
		return

	var cfg = Config.donnees

	# vitesse demandée directement en m/s
	var v_cible = vitesse

	# angle de braquage demandé
	var angle_cible = steer_dir * cfg.get("angle_braquage_max_deg", 45.0)

	# mode test
	if mode_test_acceleration:
		angle_cible = 0.0
		v_cible = vitesse_test_m_s if temps_ecoule < delai_depart_s + duree_test_s else 0.0

	# accélération / décélération
	var a_max = cfg.get("acceleration_max_m_s2", 0.72)

	vitesse_actuelle = move_toward(
		vitesse_actuelle,
		v_cible,
		a_max * delta
	)

	# vitesse de braquage
	angle_actuel = move_toward(
		angle_actuel,
		angle_cible,
		cfg.get("vitesse_braquage_deg_s", 200.0) * delta
	)

	# modèle bicycle
	var omega = vitesse_actuelle / EMPATTEMENT * tan(deg_to_rad(angle_actuel))

	var t := global_transform
	t.basis = t.basis.rotated(Vector3.UP, omega * delta)
	t.origin += -t.basis.z * vitesse_actuelle * delta
	global_transform = t

	_animer_roues(delta)

func _animer_roues(delta: float) -> void:
	if roue_av_g == null or roue_av_d == null or roue_ar_g == null or roue_ar_d == null:
		return

	var courbure := tan(deg_to_rad(angle_actuel)) / EMPATTEMENT

	# chaque roue avant pointe dans la direction de sa propre vitesse (tan(angle) = EMPATTEMENT / (R + x)).
	var angle_av_g := atan2(EMPATTEMENT * courbure, 1.0 + X_ROUE_G * courbure)
	var angle_av_d := atan2(EMPATTEMENT * courbure, 1.0 + X_ROUE_D * courbure)

	# chaque roue roule a sa propre vitesse (rayons de courbure differents)
	var sens := signf(vitesse_actuelle)
	spin_ar_g = wrapf(spin_ar_g + (sens * _vitesse_roue(courbure, X_ROUE_G, false) / RAYON_ROUE * delta), -PI, PI)
	spin_ar_d = wrapf(spin_ar_d + (sens * _vitesse_roue(courbure, X_ROUE_D, false) / RAYON_ROUE * delta), -PI, PI)
	spin_av_g = wrapf(spin_av_g + (sens * _vitesse_roue(courbure, X_ROUE_G, true) / RAYON_ROUE * delta), -PI, PI)
	spin_av_d = wrapf(spin_av_d + (sens * _vitesse_roue(courbure, X_ROUE_D, true) / RAYON_ROUE * delta), -PI, PI)

	# braquage autour de Y puis roulage autour de l'axe X
	roue_av_g.rotation = Vector3(spin_av_g, angle_av_g, 0.0)
	roue_av_d.rotation = Vector3(spin_av_d, angle_av_d, 0.0)
	roue_ar_g.rotation = Vector3(spin_ar_g, 0.0, 0.0)
	roue_ar_d.rotation = Vector3(spin_ar_d, 0.0, 0.0)

#vitesse de roulement (m/s) d'une roue situee située à la position "x" en x par rapport au centre de la voiture
#v_roue = |omega| * rayon_de_courbure_de_la_roue.
func _vitesse_roue(courbure: float, x: float, avant: bool) -> float:
	var v := absf(vitesse_actuelle)
	var dx := 1.0 + x * courbure
	if avant:
		var dl := EMPATTEMENT * courbure
		return v * sqrt(dx * dx + dl * dl)
	return v * absf(dx)
