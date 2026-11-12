extends Node3D

enum WallState {
	IDLE,
	SLOW_DOWN,
	WAIT_BALL,
	AVOID
}
var vitesse = 0.0

var manual_control_enabled := false
var manual_velocity := 0.0
var manual_direction := 0.0

#Capteur de distance
var ray = null
var ray_collision_point = Vector3.ZERO
var wall_state = WallState.IDLE
var distance = 0.0
var temps_pause_bille_cal = 0.0


#Constante du fichier config
var vitesse_max = 0.0
var vitesse_moyenne = 0.0
var vitesse_faible = 0.0
var distance_arret = 0.0
var accel_max = 0.0
var temps_pause_bille = 0.0
var direction_contournerment = 0.0


# How quickly the car turns

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
	temps_pause_bille = Config.donnees.get("temps_pause_bille")
	direction_contournerment = Config.donnees.get("direction_contournerment")
	
	_recuperer_roues()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if manual_control_enabled:
		wall_state = WallState.IDLE
		_update_manual_control()
	elif wall_state == WallState.IDLE:
		line_follower_car_angle(delta)
	else:
		wall_avoidance_manager(delta)
	# If websocket connection
	if nfsm.current_state == $"../NetworkFSM/NetworkProcessState" :
		#print(nfsm.data_received['line_follower'])
		if manual_control_enabled:
			nfsm.data_to_send["velocity"] = manual_velocity
			nfsm.data_to_send["direction"] = manual_direction
		else:
			nfsm.data_to_send["velocity"] = vitesse * 4
			nfsm.data_to_send["direction"] = steer_dir
		
		lfs_simulated_ignored = true
	else:
		
		lfs_simulated_ignored = false

func _update_manual_control():
	manual_direction = 0.0
	if Input.is_key_pressed(KEY_LEFT):
		manual_direction += 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		manual_direction -= 1.0

	manual_velocity = 0.0
	if Input.is_key_pressed(KEY_UP):
		manual_velocity += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		manual_velocity -= 1.0

	steer_dir = manual_direction
	vitesse = manual_velocity * vitesse_max

func _physics_process(delta):
	#pass
# Ray casting for distance
	if !nfsm.current_state == $"../NetworkFSM/NetworkProcessState" :
		if not manual_control_enabled:
			if ray.is_colliding():
				ray_collision_point = ray.get_collision_point()
				distance = ray_collision_point.distance_to(ray.global_position)
				#print(ray_collision_point)
				print(distance)
				if distance < distance_arret * 2.0 and wall_state == WallState.IDLE:
					wall_state = WallState.SLOW_DOWN #Premier état du contournement
			else:
				pass
		deplacer(delta)

# Suivi de ligne continu
const LINE_FILTER = 18.0	# fréquence de coupure du filtre de position (rad/s)
const RATE_FILTER = 10.0	# fréquence de coupure du filtre de dérivée de la position (rad/s)
const STEER_P_GAIN = 0.5	# braquage par unité de position (0.5 = ancien mapping capteur 1)
const STEER_D_GAIN = 0.010	# amortissement (unités de braquage par unité de dérivée de la position/s)
const STEER_RATE = 4.0		# vitesse de variation du braquage (normalisé/s)
const CURVE_ACCEL = 0.024	# accélération latérale conservée pour la bille (m/s²)

# Constantes du contournement d'obstacle
const turn_angle_big = 1
const turn_accel = 1

var position_filtree := 0.0						# position de la ligne (+2 à -2) lissée par un filtre passe-bas
var derniere_position_filtree := 0.0			# utile pour calculer la dérivée
var derivee_filtree := 0.0						# dérivée filtrée de la position
var derniere_position_mesuree := 0.0			# utile pour savoir de quel côté la ligne était avant d'être perdue
var temps_derniere_position_mesuree := 0.0		# utile pour savoir depuis combien de temps la ligne est perdue

var vitesse_cible = 0.0

func line_follower_car_angle(delta):
	var sensors

	if lfs_simulated_ignored:
		sensors = nfsm.data_received['line_follower']
	else:
		sensors = lfs.line_follower_array

	# La position mesurée est va de -2 à 2 suivant le capteur actif.
	# On prend le barycentre si plusieurs capteurs sont actifs en même temps :
	var somme := 0.0
	var nb_capteurs_actifs := 0
	for i in 5:
		if sensors[i]:
			somme += 2 - i 
			nb_capteurs_actifs += 1

	var position_mesuree := 0.0

	# Si on est sur la ligne, on calcule le barycentre
	if nb_capteurs_actifs > 0:
		position_mesuree = somme / nb_capteurs_actifs
		derniere_position_mesuree = position_mesuree
		temps_derniere_position_mesuree = 0.0

	# Si on a perdu la ligne, on considère qu'elle est du côté où elle était la dernière fois qu'on la vue, et on augmente progressivement l'écart pour simuler un écart de trajectoire.
	else:
		temps_derniere_position_mesuree += delta
		var signe := signf(derniere_position_mesuree)
		if signe == 0.0:
			signe = signf(steer_dir)
		position_mesuree = signe * min(2.0 + temps_derniere_position_mesuree * 20.0, 4.0)

	# Filtrage passe bas pour lisser les mesures
	var alpha := 1.0 - exp(-LINE_FILTER * delta)
	position_filtree = lerp(position_filtree, position_mesuree, alpha)

	# On calcule la dérivée filtrée, pour amortir les oscillations
	var taux := (position_mesuree - derniere_position_filtree) / maxf(delta, 0.0001)
	derniere_position_filtree = position_mesuree
	derivee_filtree = lerp(derivee_filtree, taux, 1.0 - exp(-RATE_FILTER * delta))

	# Braquage proportionnel à l'écart latéral, amorti par sa dérivée (PD)
	var angle_max: float = deg_to_rad(float(Config.donnees.get("angle_braquage_max_deg", 45.0)))
	var steer_target: float = STEER_P_GAIN * position_filtree + STEER_D_GAIN * derivee_filtree
	steer_target = clampf(steer_target, -1.0, 1.0)

	# On borne l'accélération latérale de la trajectoire demandée.
	var courbure: float = absf(tan(steer_target * angle_max)) / EMPATTEMENT
	var vitesse_courbe: float = sqrt(CURVE_ACCEL / maxf(courbure, 0.001))
	vitesse_cible = clampf(vitesse_courbe, vitesse_faible, vitesse_max)

	# Tous les capteurs actifs -> arrêt
	if (lfs.line_follower_array[0] || nfsm.data_received['line_follower'][0]) \
	and (lfs.line_follower_array[1] || nfsm.data_received['line_follower'][1]) \
	and (lfs.line_follower_array[2] || nfsm.data_received['line_follower'][2]) \
	and (lfs.line_follower_array[3] || nfsm.data_received['line_follower'][3]) \
	and (lfs.line_follower_array[4] || nfsm.data_received['line_follower'][4]):

		vitesse_cible = 0.0

	# Braquage progressif (le servo ne tourne pas instantanément)
	steer_dir = move_toward(steer_dir, steer_target, STEER_RATE * delta)

	# Accélération longitudinale limitée par le budget total d'accélération
	var accel_lateral: float = vitesse * vitesse * courbure
	var accel_longitudinale: float = sqrt(maxf(accel_max * accel_max - accel_lateral * accel_lateral, 0.0))
	# On garde toujours une marge pour ralentir si la courbe est plus vive que prévu.
	if vitesse_cible < vitesse:
		accel_longitudinale = maxf(accel_longitudinale, accel_max * 0.5)
	vitesse = move_toward(vitesse, vitesse_cible, accel_longitudinale * delta)

func wall_avoidance_manager(delta):

	match wall_state:

		WallState.SLOW_DOWN:
			if distance > distance_arret * 1.5:
				vitesse = move_toward(
					vitesse,
					vitesse_moyenne,
					accel_max * delta
				)
				steer_dir = move_toward(
					steer_dir,
					0.0,
					turn_accel * delta
				)
			elif distance > distance_arret:
				vitesse = move_toward(
					vitesse,
					vitesse_faible,
					accel_max * delta
				)
				steer_dir = move_toward(
					steer_dir,
					0.0,
					turn_accel * delta
				)
			else:
				vitesse = move_toward(
					vitesse,
					0.0,
					accel_max * delta
				)
				steer_dir = move_toward(
					steer_dir,
					0.0,
					turn_accel * delta
				)
				if abs(vitesse) < 0.001:
					temps_pause_bille_cal = 0.0
					wall_state = WallState.WAIT_BALL
					
		WallState.WAIT_BALL:
			vitesse = 0.0
			steer_dir = 0.0
			temps_pause_bille_cal += delta
			if temps_pause_bille_cal >= temps_pause_bille:
				temp_time = 0.0
				wall_state = WallState.AVOID

		WallState.AVOID:
			wall_avoidance_loop(delta)

var temp_time = 0.0
func wall_avoidance_loop(delta):

	print("IN WALL AVOIDANCE LOOP")
	var steer_target = 0.0
	
	if temp_time < 5.5:
		steer_target = -turn_angle_big * direction_contournerment

	elif temp_time < 16:
		steer_target = turn_angle_big * direction_contournerment

	elif temp_time < 17.5:
		steer_target = -turn_angle_big * direction_contournerment
	
	else:
		temp_time = 0.0
		wall_state = WallState.IDLE
		return

	steer_dir = move_toward(
		steer_dir,
		steer_target,
		turn_accel * delta
	)
	vitesse = move_toward(
		vitesse,
		vitesse_faible,
		(accel_max/2) * delta
	)

	temp_time += delta

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
	
	if temps_ecoule < delai_depart_s and not manual_control_enabled:
		return

	var cfg = Config.donnees

	# vitesse demandée directement en m/s
	var v_cible = vitesse

	# angle de braquage demandé
	var angle_cible = steer_dir * cfg.get("angle_braquage_max_deg", 45.0)

	# mode test
	if mode_test_acceleration and not manual_control_enabled:
		angle_cible = 0.0
		v_cible = vitesse_test_m_s if temps_ecoule < delai_depart_s + duree_test_s else 0.0

	# accélération / décélération
	var a_max = cfg.get("acceleration_max_m_s2", 0.72)

	if manual_control_enabled:
		vitesse_actuelle = v_cible
		angle_actuel = angle_cible
	else:
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
