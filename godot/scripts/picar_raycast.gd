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
var v_min := 0.0  # vitesse dans le virage le plus serré (m/s)
var v_max := 0.0  # vitesse maximale en ligne droite (m/s)

# --- Paramètres du suivi de ligne ---
const LINE_FILTER = 18.0	# fréquence de coupure du filtre de position (rad/s)
const RATE_FILTER = 10.0	# fréquence de coupure du filtre de dérivée de la position (rad/s)
const STEER_P_GAIN = 0.5	# braquage par unité de position (0.5 = ancien mapping capteur 1)
const STEER_D_GAIN = 0.010	# amortissement (unités de braquage par unité de dérivée de la position/s)

# --- Variables issues des capteurs ---
var position_filtree := 0.0						# position de la ligne (+2 à -2) lissée par un filtre passe-bas
var derniere_position_filtree := 0.0			# utile pour calculer la dérivée
var derivee_filtree := 0.0						# dérivée filtrée de la position
var derniere_position_mesuree := 0.0			# utile pour savoir de quel côté la ligne était avant d'être perdue
var temps_derniere_position_mesuree := 0.0		# utile pour savoir depuis combien de temps la ligne est perdue

const TURN_ANGLE_BIG = 1

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

	var theta_max := deg_to_rad(Config.angle_braquage_max_deg)
	v_min = sqrt((Config.accel_max * EMPATTEMENT * cos(theta_max)) / maxf(tan(theta_max), 0.0001))
	v_max = v_min * maxf(Config.overspeed_ratio, 1.0)

# Appelé par Godot à chaque tick physique
func _physics_process(delta):
	temps_ecoule += delta
	if temps_ecoule < Config.delai_depart_s and not manual_control_enabled:
		return

	var distance_obstacle = _lire_capteur_distance()
	var capteurs_ligne = _lire_capteurs_ligne()

	var vitesse_cible := 0.0
	var direction_cible := 0.0

	if manual_control_enabled:
		wall_state = WallState.FOLLOW_LINE

		var direction_input = (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0)
		var velocity_input = (1.0 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)

		direction_cible = direction_input
		vitesse_cible = velocity_input * Config.vitesse_m_s_par_unite_pwm
	else:
		match wall_state:
			WallState.FOLLOW_LINE:
				if distance_obstacle < Config.distance_arret * 2.0:
					wall_state = WallState.SLOW_DOWN

				var consigne = _follow_line(capteurs_ligne, delta)
				vitesse_cible = consigne[0]
				direction_cible = consigne[1]

			WallState.SLOW_DOWN:
				direction_cible = 0.0
				if distance_obstacle > Config.distance_arret * 1.5:
					vitesse_cible = Config.vitesse_moyenne
				elif distance_obstacle > Config.distance_arret:
					vitesse_cible = Config.vitesse_faible
				else:
					vitesse_cible = 0.0
					if abs(vitesse) < 0.001:
						temps_avant_recul_ecoule = 0.0
						wall_state = WallState.WAIT_BALL
						
			WallState.WAIT_BALL:
				vitesse_cible = 0.0
				direction_cible = 0.0
				temps_avant_recul_ecoule += delta
				if temps_avant_recul_ecoule >= Config.temps_pause_avant_recul:
					temp_time = 0.0
					wall_state = WallState.AVOID

			WallState.AVOID:
				var consigne = wall_avoidance_loop(delta)
				vitesse_cible = consigne[0]
				direction_cible = consigne[1]

	var mouvement_contraint = _appliquer_contraintes(vitesse_cible, direction_cible, delta)
	vitesse = mouvement_contraint[0]
	direction = mouvement_contraint[1]

	if _is_car_connected():
		nfsm.data_to_send["velocity"] = vitesse / Config.vitesse_m_s_par_unite_pwm
		nfsm.data_to_send["direction"] = clampf(direction + Config.trim_direction_normalise, -1.0, 1.0)
	else:
		_deplacer_simulation(delta)

# Lit le capteur de distance (réel si la voiture est connectée, simulé sinon) et retourne sa valeur
func _lire_capteur_distance() -> float:
	if _is_car_connected():
		var distance_recue := float(nfsm.data_received.get("distance_recue", -1.0)) / 100.0
		distance_recue = 0.988077 * distance_recue + 3.455385
		return distance_recue if distance_recue > 0.0 else INF
	else:
		if not ray.is_colliding():
			return INF

		var ray_collision_point = ray.get_collision_point()
		return ray.global_position.distance_to(ray_collision_point) + 3.5


# Lit les capteurs de ligne (réels si la voiture est connectée, simulés sinon) et retourne leurs valeurs
func _lire_capteurs_ligne() -> Array:
	if _is_car_connected():
		return nfsm.data_received.get("line_follower", [0, 0, 0, 0, 0])
	else:
		return lfs.line_follower_array
	
func _follow_line(capteurs_ligne, delta) -> Array:
	# La position mesurée va de -2 à 2 suivant le capteur actif.
	# On prend le barycentre si plusieurs capteurs sont actifs en même temps :
	var somme := 0.0
	var nb_capteurs_actifs := 0
	for i in 5:
		if capteurs_ligne[i]:
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
	var taux := (position_filtree - derniere_position_filtree) / maxf(delta, 0.0001)
	derniere_position_filtree = position_filtree
	derivee_filtree = lerp(derivee_filtree, taux, 1.0 - exp(-RATE_FILTER * delta))

	# Braquage proportionnel à l'écart latéral, amorti par sa dérivée (PD)
	var direction_cible: float = STEER_P_GAIN * position_filtree + STEER_D_GAIN * derivee_filtree
	direction_cible = clampf(direction_cible, -1.0, 1.0)

	var vitesse_cible: float = v_max

	# Tous les capteurs actifs -> arrêt
	if nb_capteurs_actifs == 5:
		vitesse_cible = 0.0

	return [vitesse_cible, direction_cible]

var temp_time = 0.0
func wall_avoidance_loop(delta) -> Array:
	print("IN WALL AVOIDANCE LOOP")
	var direction_cible = 0.0
	
	if temp_time < 4.5:
		direction_cible = -TURN_ANGLE_BIG * Config.direction_contournerment

	elif temp_time < 13:
		direction_cible = TURN_ANGLE_BIG * Config.direction_contournerment

	elif temp_time < 15.5:
		direction_cible = -TURN_ANGLE_BIG * Config.direction_contournerment
	
	else:
		temp_time = 0.0
		wall_state = WallState.FOLLOW_LINE
		return [0.0, 0.0]

	temp_time += delta
	return [Config.vitesse_faible, direction_cible]

# Applique les contraintes d'accélération maximale et retourne [vitesse_contrainte, direction_contrainte].
func _appliquer_contraintes(vitesse_cible: float, direction_cible: float, delta: float) -> Array:
	var theta_max := deg_to_rad(Config.angle_braquage_max_deg)
	var a_max := Config.accel_max

	direction_cible = clampf(direction_cible, -1.0, 1.0)
	vitesse_cible = clampf(vitesse_cible, -v_max, v_max)

	# vitesse maximale permise par l'angle de braquage demandé (theta_virage) à l'essieu avant
	var theta_virage := absf(direction_cible) * theta_max
	if theta_virage > 0.0001:
		var vitesse_virage := sqrt((a_max * EMPATTEMENT * cos(theta_virage)) / tan(theta_virage))
		vitesse_cible = clampf(vitesse_cible, -vitesse_virage, vitesse_virage)

	# répartition du budget d'accélération si on est en survitesse par rapport à vitesse_cible
	var t := 0.0
	if v_max > v_min and absf(vitesse) > absf(vitesse_cible):
		t = clampf((absf(vitesse) - absf(vitesse_cible)) / (v_max - v_min), 0.0, 1.0)
	var a_lat_max := sqrt(maxf(1.0 - t * t, 0.0)) * a_max

	# limitation de l'angle de braquage par la vitesse actuelle : (tan(theta) / (L * cos(theta))) * v² <= a_lat_max
	var direction_max_autorisee := 1.0
	if absf(vitesse) > 0.001:
		var theta_actuel_abs := absf(direction) * theta_max
		var theta_max_autorise: float = atan((a_lat_max * EMPATTEMENT * cos(theta_actuel_abs)) / (vitesse * vitesse))
		direction_max_autorisee = clampf(theta_max_autorise / maxf(theta_max, 0.0001), 0.0, 1.0)

	var direction_cible_bridee := clampf(direction_cible, -direction_max_autorisee, direction_max_autorisee)

	# limitation de la vitesse de braquage pour que a_centripète + a_braquage <= a_lat_max
	#    a_centripète = tan(theta) / (L cos(theta)) * v²   et   a_braquage = vitesse de braquage / cos²(theta) * v
	var theta_actuel := absf(direction) * theta_max
	var a_centripete: float = (tan(theta_actuel) / (EMPATTEMENT * maxf(cos(theta_actuel), 0.0001))) * vitesse * vitesse
	# en braquant vers l'intérieur, le coup de volant s'ajoute à la force centripète. en redressant, il la réduit.
	var a_braquage_max := a_lat_max + a_centripete
	if absf(direction_cible) > absf(direction):
		a_braquage_max = a_lat_max - a_centripete
	a_braquage_max = maxf(a_braquage_max, 0.0)

	var vitesse_braquage_max := INF	# rad/s
	if absf(vitesse) > 0.001:
		var cos_theta := cos(theta_actuel)
		vitesse_braquage_max = (a_braquage_max * cos_theta * cos_theta) / absf(vitesse)

	var direction_contrainte := move_toward(direction, direction_cible_bridee, (vitesse_braquage_max / theta_max) * delta)

	# mise à jour de la vitesse avec la contrainte exacte a_u² + a_n² <= a_max²
	# a_u = dot(v) - v² tan²(theta) / L
	# a_n = v² tan(theta) / L + dot(v) tan(theta) + v theta_point / cos²(theta)
	var theta_nouveau := direction_contrainte * theta_max
	var theta_point: float = (direction_contrainte - direction) * theta_max / delta
	var cos_theta_nouveau := maxf(cos(theta_nouveau), 0.0001)
	var tan_theta := tan(theta_nouveau)
	var c_centripete: float = vitesse * vitesse * tan_theta / EMPATTEMENT
	var b_braquage: float = vitesse * theta_point / (cos_theta_nouveau * cos_theta_nouveau)

	# (1/cos²) v̇² + (2 B tan) v̇ + C² tan² + (C+B)² - a_max² <= 0
	var a_quad := 1.0 / (cos_theta_nouveau * cos_theta_nouveau)
	var b_quad: float = 2.0 * b_braquage * tan_theta
	var somme_cb: float = c_centripete + b_braquage
	var c_quad: float = c_centripete * c_centripete * tan_theta * tan_theta + somme_cb * somme_cb - a_max * a_max

	var accel_min := 0.0
	var accel_max := 0.0
	var discriminant: float = b_quad * b_quad - 4.0 * a_quad * c_quad
	if discriminant >= 0.0:
		var racine := sqrt(discriminant)
		accel_min = (-b_quad - racine) / (2.0 * a_quad)
		accel_max = (-b_quad + racine) / (2.0 * a_quad)
	else:
		# aucun v̇ ne satisfait exactement la contrainte : on prend le minimum de la parabole
		accel_min = -b_quad / (2.0 * a_quad)
		accel_max = accel_min

	var pas: float = clampf(vitesse_cible - vitesse, accel_min * delta, accel_max * delta)
	var vitesse_contrainte: float = vitesse + pas

	return [vitesse_contrainte, direction_contrainte]

# Déplace la voiture simulée dans la scène 
func _deplacer_simulation(delta: float) -> void:
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
