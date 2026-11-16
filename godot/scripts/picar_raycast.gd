extends Node3D

var manual_control_enabled := false

# --- State machine ---
enum WallState {
	FOLLOW_LINE,
	SLOW_DOWN,
	WAIT_BALL,
	AVOID
}
var temps_ecoule := 0.0
var temps_avant_recul_ecoule = 0.0
var wall_state = WallState.FOLLOW_LINE

# --- Nodes godot ---
var lfs = 0			# Line Follower Sensor simulé
var ray = null		# Raycast du capteur de distance simulé
var nfsm = 0		# Network Finite State Machine
var roue_av_g: Node3D = null
var roue_av_d: Node3D = null
var roue_ar_g: Node3D = null
var roue_ar_d: Node3D = null

# --- Géométrie de la voiture ---
const EMPATTEMENT = 0.142		# distance entre les essieux (m)
const RAYON_ROUE = 0.0325		# rayon des roues (m) 
const VOIE = 0.11				# distance entre les centres des roues gauche/droite (m)
const X_ROUE_G = -VOIE * 0.5	# position en x du centre de la roue gauche (m)
const X_ROUE_D = VOIE * 0.5		# position en x du centre de la roue droite (m)

# --- Vitesse et direction actuels ---
var vitesse = 0.0 # en m/s
var direction = 0 # entre -1 et 1

# --- Paramètres du capteur de distance --- (TODO : filtrer ?)
var ray_collision_point = Vector3.ZERO

# --- Paramètres du suivi de ligne ---
const LINE_FILTER = 18.0	# fréquence de coupure du filtre de position (rad/s)
const RATE_FILTER = 10.0	# fréquence de coupure du filtre de dérivée de la position (rad/s)
const STEER_P_GAIN = 0.5	# braquage par unité de position (0.5 = ancien mapping capteur 1)
const STEER_D_GAIN = 0.010	# amortissement (unités de braquage par unité de dérivée de la position/s)
const CURVE_ACCEL = 0.024	# accélération latérale conservée pour la bille (m/s²)

# --- Variables issues des capteurs ---
var distance_obstacle = 0.0
var position_filtree := 0.0						# position de la ligne (+2 à -2) lissée par un filtre passe-bas
var derniere_position_filtree := 0.0			# utile pour calculer la dérivée
var derivee_filtree := 0.0						# dérivée filtrée de la position
var derniere_position_mesuree := 0.0			# utile pour savoir de quel côté la ligne était avant d'être perdue
var temps_derniere_position_mesuree := 0.0		# utile pour savoir depuis combien de temps la ligne est perdue

const TURN_ANGLE_BIG = 1
const TURN_ACCEL = 1

# Appelé par Godot au lancement
func _ready():
	# Récupération des différents nodes de la scène	
	ray = get_node("capteur_ultrasons")
	lfs = $capteur_ligne
	nfsm = $"../NetworkFSM"
	roue_av_g = find_child("roue_av_g", true, false) as Node3D
	roue_av_d = find_child("roue_av_d", true, false) as Node3D
	roue_ar_g = find_child("roue_ar_g", true, false) as Node3D
	roue_ar_d = find_child("roue_ar_d", true, false) as Node3D

# Appelé par Godot à chaque tick physique
func _physics_process(delta):
	if not _is_car_connected():
		_mettre_a_jour_distance_obstacle()

	if manual_control_enabled:
		wall_state = WallState.FOLLOW_LINE

		var direction_input = (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0)
		var velocity_input = (1.0 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)

		direction = direction_input
		vitesse = velocity_input * Config.vitesse_m_s_par_unite_pwm
	else:
		match wall_state:
			WallState.FOLLOW_LINE:
				line_follower_car_angle(delta)

			WallState.SLOW_DOWN:
				if distance_obstacle > Config.distance_arret * 1.5:
					vitesse = move_toward(
						vitesse,
						Config.vitesse_moyenne,
						Config.accel_max * delta
					)
					direction = move_toward(
						direction,
						0.0,
						TURN_ACCEL * delta
					)
				elif distance_obstacle > Config.distance_arret:
					vitesse = move_toward(
						vitesse,
						Config.vitesse_faible,
						Config.accel_max * delta
					)
					direction = move_toward(
						direction,
						0.0,
						TURN_ACCEL * delta
					)
				else:
					vitesse = move_toward(
						vitesse,
						0.0,
						Config.accel_max * delta
					)
					direction = move_toward(
						direction,
						0.0,
						TURN_ACCEL * delta
					)
					if abs(vitesse) < 0.001:
						temps_avant_recul_ecoule = 0.0
						wall_state = WallState.WAIT_BALL
						
			WallState.WAIT_BALL:
				vitesse = 0.0
				direction = 0.0
				temps_avant_recul_ecoule += delta
				if temps_avant_recul_ecoule >= Config.temps_pause_avant_recul:
					temp_time = 0.0
					wall_state = WallState.AVOID

			WallState.AVOID:
				wall_avoidance_loop(delta)

	if _is_car_connected():
		nfsm.data_to_send["velocity"] = vitesse / Config.vitesse_m_s_par_unite_pwm
		nfsm.data_to_send["direction"] = clampf(direction + Config.trim_direction_normalise, -1.0, 1.0)
	else:
		_deplacer(delta)

# Met à jour la distance à l'obstacle et déclenche le contournement
func _mettre_a_jour_distance_obstacle():
	if ray.is_colliding():
		ray_collision_point = ray.get_collision_point()
		distance_obstacle = ray_collision_point.distance_to(ray.global_position)
		if distance_obstacle < Config.distance_arret * 2.0 and wall_state == WallState.FOLLOW_LINE:
			wall_state = WallState.SLOW_DOWN # Premier état du contournement

func line_follower_car_angle(delta):
	var sensors

	if _is_car_connected():
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
			signe = signf(direction)
		position_mesuree = signe * min(2.0 + temps_derniere_position_mesuree * 20.0, 4.0)

	# Filtrage passe bas pour lisser les mesures
	var alpha := 1.0 - exp(-LINE_FILTER * delta)
	position_filtree = lerp(position_filtree, position_mesuree, alpha)

	# On calcule la dérivée filtrée, pour amortir les oscillations
	var taux := (position_mesuree - derniere_position_filtree) / maxf(delta, 0.0001)
	derniere_position_filtree = position_mesuree
	derivee_filtree = lerp(derivee_filtree, taux, 1.0 - exp(-RATE_FILTER * delta))

	# Braquage proportionnel à l'écart latéral, amorti par sa dérivée (PD)
	var angle_max: float = deg_to_rad(Config.angle_braquage_max_deg)
	var steer_target: float = STEER_P_GAIN * position_filtree + STEER_D_GAIN * derivee_filtree
	steer_target = clampf(steer_target, -1.0, 1.0)

	# On borne l'accélération latérale de la trajectoire demandée.
	var courbure: float = absf(tan(steer_target * angle_max)) / EMPATTEMENT
	var vitesse_courbe: float = sqrt(CURVE_ACCEL / maxf(courbure, 0.001))
	var vitesse_cible = clampf(vitesse_courbe, Config.vitesse_faible, Config.vitesse_max)

	# Tous les capteurs actifs -> arrêt
	if (lfs.line_follower_array[0] || nfsm.data_received['line_follower'][0]) \
	and (lfs.line_follower_array[1] || nfsm.data_received['line_follower'][1]) \
	and (lfs.line_follower_array[2] || nfsm.data_received['line_follower'][2]) \
	and (lfs.line_follower_array[3] || nfsm.data_received['line_follower'][3]) \
	and (lfs.line_follower_array[4] || nfsm.data_received['line_follower'][4]):

		vitesse_cible = 0.0

	# Braquage progressif (le servo ne tourne pas instantanément)
	direction = move_toward(direction, steer_target, Config.steer_speed_normalise * delta)

	# Accélération longitudinale limitée par le budget total d'accélération
	var accel_lateral: float = vitesse * vitesse * courbure
	var accel_longitudinale: float = sqrt(maxf(Config.accel_max * Config.accel_max - accel_lateral * accel_lateral, 0.0))
	# On garde toujours une marge pour ralentir si la courbe est plus vive que prévu.
	if vitesse_cible < vitesse:
		accel_longitudinale = maxf(accel_longitudinale, Config.accel_max * 0.5)
	vitesse = move_toward(vitesse, vitesse_cible, accel_longitudinale * delta)

var temp_time = 0.0
func wall_avoidance_loop(delta):

	print("IN WALL AVOIDANCE LOOP")
	var steer_target = 0.0
	
	if temp_time < 5.5:
		steer_target = -TURN_ANGLE_BIG * Config.direction_contournerment

	elif temp_time < 16:
		steer_target = TURN_ANGLE_BIG * Config.direction_contournerment

	elif temp_time < 17.5:
		steer_target = -TURN_ANGLE_BIG * Config.direction_contournerment
	
	else:
		temp_time = 0.0
		wall_state = WallState.FOLLOW_LINE
		return

	direction = move_toward(
		direction,
		steer_target,
		TURN_ACCEL * delta
	)
	vitesse = move_toward(
		vitesse,
		Config.vitesse_faible,
		(Config.accel_max/2) * delta
	)

	temp_time += delta

# Déplace la voiture simulée dans la scène 
func _deplacer(delta: float) -> void:
	temps_ecoule += delta
	
	if temps_ecoule < Config.delai_depart_s and not manual_control_enabled:
		return

	# angle de braquage demandé
	var angle_cible = direction * Config.angle_braquage_max_deg

	# modèle bicycle
	var omega = vitesse / EMPATTEMENT * tan(deg_to_rad(angle_cible))

	var t := global_transform
	t.basis = t.basis.rotated(Vector3.UP, omega * delta)
	t.origin += -t.basis.z * vitesse * delta
	global_transform = t

	_animer_roues(delta, vitesse, angle_cible)

# Anime les roues (direction et rotation)
func _animer_roues(delta: float, vitesse_lineaire: float, angle_roue: float) -> void:
	if roue_av_g == null or roue_av_d == null or roue_ar_g == null or roue_ar_d == null:
		return

	var courbure := tan(deg_to_rad(angle_roue)) / EMPATTEMENT

	# chaque roue avant pointe dans la direction de sa propre vitesse (tan(angle) = EMPATTEMENT / (R + x)).
	var angle_av_g := atan2(EMPATTEMENT * courbure, 1.0 + X_ROUE_G * courbure)
	var angle_av_d := atan2(EMPATTEMENT * courbure, 1.0 + X_ROUE_D * courbure)

	# chaque roue roule a sa propre vitesse (rayons de courbure differents)
	var sens := signf(vitesse_lineaire)
	var pas_ar_g := sens * _vitesse_roue(courbure, X_ROUE_G, false, vitesse_lineaire) / RAYON_ROUE * delta
	var pas_ar_d := sens * _vitesse_roue(courbure, X_ROUE_D, false, vitesse_lineaire) / RAYON_ROUE * delta
	var pas_av_g := sens * _vitesse_roue(courbure, X_ROUE_G, true, vitesse_lineaire) / RAYON_ROUE * delta
	var pas_av_d := sens * _vitesse_roue(courbure, X_ROUE_D, true, vitesse_lineaire) / RAYON_ROUE * delta

	# braquage autour de Y puis roulage autour de l'axe X
	roue_av_g.rotation = Vector3(wrapf(roue_av_g.rotation.x + pas_av_g, -PI, PI), angle_av_g, 0.0)
	roue_av_d.rotation = Vector3(wrapf(roue_av_d.rotation.x + pas_av_d, -PI, PI), angle_av_d, 0.0)
	roue_ar_g.rotation.x = wrapf(roue_ar_g.rotation.x + pas_ar_g, -PI, PI)
	roue_ar_d.rotation.x = wrapf(roue_ar_d.rotation.x + pas_ar_d, -PI, PI)

# Retourne la vitesse de roulement (m/s) d'une roue situee située à la position `x` en x par rapport au centre de la voiture
func _vitesse_roue(courbure: float, x: float, avant: bool, vitesse_lineaire: float) -> float:
	var v := absf(vitesse_lineaire)
	var dx := 1.0 + x * courbure
	if avant:
		var dl := EMPATTEMENT * courbure
		return v * sqrt(dx * dx + dl * dl)
	return v * absf(dx)


func _is_car_connected() -> bool:
	return (nfsm.current_state == $"../NetworkFSM/NetworkProcessState")