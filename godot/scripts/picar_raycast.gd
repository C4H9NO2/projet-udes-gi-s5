extends Node3D

var manual_control_enabled := false
var bypass_contraintes := false

# --- State machine ---
enum WallState {
	FOLLOW_LINE,
	SLOW_DOWN,
	WAIT_BALL,
	BACK_UP,
	OBSTACLE_TURN_OUT,
	OBSTACLE_TURN_IN,
	OBSTACLE_PASS,
	OBSTACLE_RETURN,
	OBSTACLE_APPROACH,
	OBSTACLE_ALIGN
}
var temps_ecoule := 0.0
var temps_arret_ecoule := 0.0
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
const EMPATTEMENT = 0.142				# distance entre les essieux (m)
const RAYON_ROUE = 0.0325				# rayon des roues (m) 
const VOIE = 0.11						# distance entre les centres des roues gauche/droite (m)
const LARGEUR_VOITURE = 0.136			# largeur roues incluses (m) 
const X_ROUE_G = -VOIE * 0.5			# position en x du centre de la roue gauche (m)
const X_ROUE_D = VOIE * 0.5				# position en x du centre de la roue droite (m)
const DISTANCE_CAPTEUR_ESSIEU = 0.182	# capteur ultrasons devant l'essieu arrière (m)
const DISTANCE_ARRIERE_ESSIEU = 0.04	# point le plus arrière de la voiture derrière l'essieu arrière (m)

# --- Vitesse et direction actuels ---
var vitesse := 0.0 		# en m/s
var direction := 0.0 	# entre -1 et 1
var v_min := 0.0  		# vitesse dans le virage le plus serré (m/s)
var v_max := 0.0  		# vitesse maximale en ligne droite (m/s)
var theta_max := 0.0  	# angle de braquage maximal (rad)

# --- Paramètres du suivi de ligne ---
const LINE_FILTER = 18.0	# fréquence de coupure du filtre de position (rad/s)
const RATE_FILTER = 10.0	# fréquence de coupure du filtre de dérivée de la position (rad/s)
const STEER_P_GAIN = 0.5	# braquage par unité de position (0.5 = ancien mapping capteur 1)
const STEER_D_GAIN = 0.010	# amortissement (unités de braquage par unité de dérivée de la position/s)
const NB_CAPTEURS_ARRET = 4	# nombre de capteurs actifs qui déclenche l'arrêt (ligne perpendiculaire)

# --- Variables issues des capteurs ---
var position_filtree := 0.0						# position de la ligne (+2 à -2) lissée par un filtre passe-bas
var derniere_position_filtree := 0.0			# utile pour calculer la dérivée
var derivee_filtree := 0.0						# dérivée filtrée de la position
var derniere_position_mesuree := 0.0			# utile pour savoir de quel côté la ligne était avant d'être perdue
var temps_derniere_position_mesuree := 0.0		# utile pour savoir depuis combien de temps la ligne est perdue
var reinitialiser_suivi := false				# réinitialise les filtres au retour sur la ligne

# --- Contournement d'obstacle ---
var cote := -1.0				# signe de direction_cible pour tourner vers le côté du contournement
var distance_recul_parcourue := 0.0
var x_contournement := 0.0		# odométrie : avance depuis le début du S (m)
var y_contournement := 0.0		# odométrie : décalage vers le côté du contournement (m)
var angle_contournement := 0.0	# odométrie : angle vers le côté du contournement (rad)
var y_cible := 0.0				# décalage latéral visé (m)
var x_s := 0.0					# longueur du S (m)
var x_obstacle := 0.0			# distance de l'essieu arrière au début du S jusqu'à la face avant de l'obstacle (m)
var angle_s := 0.0				# angle maximal du S (rad)
var braquage_s := 0.0			# angle de braquage du S (rad)
var angle_retour := 0.0			# angle de retour vers la ligne (rad)

# Appelé par Godot au lancement
func _ready():
	# -- Récupération des différents nodes de la scène --
	ray = get_node("capteur_ultrasons")
	lfs = $capteur_ligne
	nfsm = $"../NetworkFSM"
	roue_av_g = find_child("roue_av_g", true, false) as Node3D
	roue_av_d = find_child("roue_av_d", true, false) as Node3D
	roue_ar_g = find_child("roue_ar_g", true, false) as Node3D
	roue_ar_d = find_child("roue_ar_d", true, false) as Node3D

	# -- Calculs préliminaires pour le respect des contraintes --

	theta_max = deg_to_rad(Config.angle_braquage_max_deg)
	v_min = sqrt((Config.accel_max * EMPATTEMENT * cos(theta_max)) / maxf(tan(theta_max), 0.0001))
	v_max = v_min * maxf(Config.overspeed_ratio, 1.0)

	# -- Calculs préliminaires pour le contournement d'obstacle --

	# +1 si on contourne à gauche, -1 si on contourne à droite
	cote = -signf(Config.direction_contournerment)
	if cote == 0.0:
		cote = -1.0

	# Géométrie fixe du contournement : elle ne dépend que de la config.
	# Décalage latéral : demi-largeur de l'obstacle + marge latérale + demi-largeur réelle de la voiture.
	y_cible = maxf(Config.largeur_obstacle * 0.5 + Config.marge_contournement_x + LARGEUR_VOITURE * 0.5, 0.01)

	# Distance totale entre l'essieu arrière au début du S et la face avant de l'obstacle.
	x_obstacle = maxf(Config.distance_arret + DISTANCE_CAPTEUR_ESSIEU + Config.distance_recul, 0.05)

	# Marge longitudinale : le S se termine avant l'obstacle ; le reste est parcouru tout droit.
	var marge_y := maxf(Config.marge_contournement_y, 0.0)
	x_s = maxf(x_obstacle - marge_y, 0.05)

	# S'assure que le S reste réalisable avec le braquage maximal.
	var rayon_min := EMPATTEMENT / maxf(tan(theta_max), 0.0001)
	var x_s_min := sqrt(maxf(4.0 * y_cible * rayon_min - y_cible * y_cible, 0.0))
	if y_cible > 4.0 * rayon_min:
		push_warning("Décalage latéral de contournement impossible avec le braquage maximal.")
	if x_s < x_s_min:
		push_warning("Marge de contournement y trop grande : S raccourci à %.1f cm pour respecter le braquage maximal." % (x_s_min * 100.0))
		x_s = x_s_min

	# S formé de deux arcs de cercle tangents de même rayon.
	# x_s = 2 R sin(angle_s) et y_cible = 2 R (1 - cos(angle_s)).
	angle_s = 2.0 * atan2(y_cible, x_s)
	var rayon := (x_s * x_s + y_cible * y_cible) / (4.0 * y_cible)
	braquage_s = atan(EMPATTEMENT / rayon)

	# On ne veut pas traverser la ligne pendant le virage de retour.
	var angle_retour_max := acos(clampf(1.0 - y_cible / rayon, -1.0, 1.0))
	angle_retour = minf(deg_to_rad(Config.angle_retour_ligne_deg), angle_retour_max)

# Appelé par Godot à chaque tick physique
func _physics_process(delta):
	temps_ecoule += delta
	if temps_ecoule < Config.delai_depart_s and not manual_control_enabled:
		return

	var distance_obstacle = _lire_capteur_distance()
	var capteurs_ligne = _lire_capteurs_ligne()

	var consigne := [0.0, 0.0]

	if manual_control_enabled:
		wall_state = WallState.FOLLOW_LINE

		var direction_input = (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0)
		var velocity_input = (1.0 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)

		consigne = [velocity_input * Config.vitesse_m_s_par_unite_pwm, direction_input]
	else:
		match wall_state:
			WallState.FOLLOW_LINE:
				if distance_obstacle < Config.distance_arret * 2.0:
					wall_state = WallState.SLOW_DOWN
					consigne = _slow_down(distance_obstacle, capteurs_ligne, delta)
				else:
					consigne = _follow_line(capteurs_ligne, delta)

			WallState.SLOW_DOWN:
				consigne = _slow_down(distance_obstacle, capteurs_ligne, delta)

			WallState.WAIT_BALL:
				consigne = _wait_ball(delta)

			WallState.BACK_UP:
				consigne = _back_up(delta)

			WallState.OBSTACLE_TURN_OUT:
				consigne = _obstacle_turn_out(delta)

			WallState.OBSTACLE_TURN_IN:
				consigne = _obstacle_turn_in(delta)

			WallState.OBSTACLE_PASS:
				consigne = _obstacle_pass(delta)

			WallState.OBSTACLE_RETURN:
				consigne = _obstacle_return(capteurs_ligne, delta)

			WallState.OBSTACLE_APPROACH:
				consigne = _obstacle_approach(capteurs_ligne, delta)

			WallState.OBSTACLE_ALIGN:
				consigne = _obstacle_align(capteurs_ligne, delta)

	if bypass_contraintes:
		vitesse = consigne[0]
		direction = consigne[1]
	else:
		var mouvement_contraint = _appliquer_contraintes(consigne[0], consigne[1], delta)
		vitesse = mouvement_contraint[0]
		direction = mouvement_contraint[1]

	_mettre_a_jour_odometrie(delta)

	if _is_car_connected():
		nfsm.data_to_send["velocity"] = vitesse / Config.vitesse_m_s_par_unite_pwm
		nfsm.data_to_send["direction"] = clampf(direction + Config.trim_direction_normalise, -1.0, 1.0)
	else:
		_deplacer_simulation(delta)

# Lit le capteur de distance (réel si la voiture est connectée, simulé sinon) et retourne sa valeur en mètres
func _lire_capteur_distance() -> float:
	if _is_car_connected():
		var distance_brute := float(nfsm.data_received.get("distance", -1.0)) / 100.0
		if distance_brute < 0.0:
			return INF
		# Régression mesurée sur le capteur réel : mesure = 0.988077 * distance_réelle + 3.455385 cm.
		# On l'inverse pour retrouver la distance réelle à partir de la mesure.
		return maxf(1.012067 * distance_brute - 3.497081, 0.0)
	else:
		if not ray.is_colliding():
			return INF

		var ray_collision_point = ray.get_collision_point()
		return ray.global_position.distance_to(ray_collision_point) / 10.0

# Lit les capteurs de ligne (réels si la voiture est connectée, simulés sinon) et retourne leurs valeurs
func _lire_capteurs_ligne() -> Array:
	if _is_car_connected():
		return nfsm.data_received.get("line_follower", [0, 0, 0, 0, 0])
	else:
		return lfs.line_follower_array

# Suivi de ligne. Retourne [vitesse_cible, direction_cible].
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

	if reinitialiser_suivi:
		position_filtree = position_mesuree
		derniere_position_filtree = position_mesuree
		derivee_filtree = 0.0
		reinitialiser_suivi = false
	else:
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

	# Presque tous les capteurs actifs -> arrêt (fin de piste)
	if nb_capteurs_actifs >= NB_CAPTEURS_ARRET:
		vitesse_cible = 0.0

	return [vitesse_cible, direction_cible]

# Ralentit pour s'arrêter à `distance_arret` de l'obstacle. Retourne [vitesse_cible, direction_cible].
func _slow_down(distance_obstacle: float, capteurs_ligne: Array, delta: float) -> Array:
	# On continue de suivre la ligne pendant le freinage.
	var consigne_ligne = _follow_line(capteurs_ligne, delta)

	# Vitesse qui permet de s'arrêter exactement à `distance_arret` en freinant à a_max.
	var d_restant := distance_obstacle - Config.distance_arret
	var vitesse_cible := 0.0
	if is_finite(d_restant) and d_restant > 0.0:
		vitesse_cible = minf(v_max, sqrt(2.0 * Config.accel_max * d_restant))

	if d_restant <= 0.0 and absf(vitesse) < 0.002:
		temps_arret_ecoule = 0.0
		wall_state = WallState.WAIT_BALL

	return [vitesse_cible, consigne_ligne[1]]

# Attend que la bille se stabilise avant de reculer. Retourne [vitesse_cible, direction_cible].
func _wait_ball(delta: float) -> Array:
	temps_arret_ecoule += delta
	if temps_arret_ecoule >= Config.temps_pause_avant_recul:
		distance_recul_parcourue = 0.0
		wall_state = WallState.BACK_UP
	return [0.0, 0.0]

# Recule de `distance_recul` en respectant a_max. Retourne [vitesse_cible, direction_cible].
func _back_up(delta: float) -> Array:
	distance_recul_parcourue += maxf(-vitesse, 0.0) * delta

	var d_restant := Config.distance_recul - distance_recul_parcourue
	var vitesse_cible := 0.0
	if d_restant > 0.0:
		# Même loi de freinage que pour l'arrêt, mais en marche arrière.
		vitesse_cible = -minf(v_max, sqrt(2.0 * Config.accel_max * d_restant))
	elif absf(vitesse) < 0.002:
		# Le S repart de la position actuelle : on remet l'odométrie locale à zéro.
		x_contournement = 0.0
		y_contournement = 0.0
		angle_contournement = 0.0
		wall_state = WallState.OBSTACLE_TURN_OUT

	return [vitesse_cible, 0.0]

# Premier arc du S : on s'éloigne de la ligne. Retourne [vitesse_cible, direction_cible].
func _obstacle_turn_out(delta: float) -> Array:
	# On anticipe l'inversion du braquage : les roues mettent du temps à passer
	# de +theta_S à -theta_S, donc on commence le second arc un peu avant psi_max.
	var seuil := maxf(angle_s - deg_to_rad(10.0), 0.0)
	if angle_contournement >= seuil:
		wall_state = WallState.OBSTACLE_TURN_IN
		return _obstacle_turn_in(delta)

	return [v_max, cote * braquage_s / theta_max]

# Second arc du S : on se remet parallèle à la piste, décalé de y_cible.
# La courbure est recalculée à chaque tick pour raccorder la position et l'angle courants à (y_cible, 0).
func _obstacle_turn_in(delta: float) -> Array:
	if angle_contournement <= deg_to_rad(2.0):
		wall_state = WallState.OBSTACLE_PASS
		return _obstacle_pass(delta)

	var denom := maxf(y_cible - y_contournement, 0.002)
	var courbure := (cos(angle_contournement) - 1.0) / denom
	var courbure_max := tan(theta_max) / EMPATTEMENT
	courbure = clampf(courbure, -courbure_max, courbure_max)
	var braquage := atan(EMPATTEMENT * courbure)

	return [v_max, cote * braquage / theta_max]

# Une fois parallèle à la piste, on avance tout droit le long de l'obstacle
# jusqu'à ce que l'arrière de la voiture ait dépassé sa face arrière.
func _obstacle_pass(delta: float) -> Array:
	# On parcourt tout droit la marge longitudinale restante, puis la profondeur
	# de l'obstacle et le porte-à-faux arrière.
	var x_passage: float = x_obstacle + Config.profondeur_obstacle + DISTANCE_ARRIERE_ESSIEU
	if x_contournement >= x_passage:
		wall_state = WallState.OBSTACLE_RETURN
		return [v_min, 0.0]

	return [v_min, 0.0]

# Virage de retour vers la ligne. On redresse les roues dès que la ligne est vue,
# puis on laisse le suivi de ligne prendre le relai une fois le braquage stabilisé.
func _obstacle_return(capteurs_ligne: Array, delta: float) -> Array:
	if _ligne_detectee(capteurs_ligne):
		wall_state = WallState.OBSTACLE_ALIGN
		return _obstacle_align(capteurs_ligne, delta)

	if angle_contournement <= -angle_retour:
		wall_state = WallState.OBSTACLE_APPROACH
		return _obstacle_approach(capteurs_ligne, delta)

	return [v_min, -cote * braquage_s / theta_max]

# Approche rectiligne vers la ligne, avec l'angle de retour.
func _obstacle_approach(capteurs_ligne: Array, delta: float) -> Array:
	if _ligne_detectee(capteurs_ligne):
		wall_state = WallState.OBSTACLE_ALIGN
		return _obstacle_align(capteurs_ligne, delta)

	return [v_min, 0.0]

# Redresse les roues avant de rendre la main au suivi de ligne, pour éviter que
# le suiveur doive annuler un braquage important en même temps qu'il rattrape la ligne.
func _obstacle_align(capteurs_ligne: Array, delta: float) -> Array:
	_mettre_a_jour_derniere_position(capteurs_ligne)

	if absf(direction) < 0.05:
		reinitialiser_suivi = true
		wall_state = WallState.FOLLOW_LINE
		return _follow_line(capteurs_ligne, delta)

	return [v_min, 0.0]

# Vrai si un des trois capteurs centraux voit la ligne : la voiture est sur la ligne.
func _ligne_detectee(capteurs_ligne: Array) -> bool:
	return capteurs_ligne[1] == 1 or capteurs_ligne[2] == 1 or capteurs_ligne[3] == 1

# Met à jour la dernière position connue de la ligne (utile si elle est perdue juste après).
func _mettre_a_jour_derniere_position(capteurs_ligne: Array) -> void:
	var somme := 0.0
	var nb := 0
	for i in 5:
		if capteurs_ligne[i]:
			somme += 2 - i
			nb += 1
	if nb > 0:
		derniere_position_mesuree = somme / nb
		temps_derniere_position_mesuree = 0.0

# Intègre la pose de la voiture dans le repère du contournement (x vers l'avant, y vers le côté du contournement)
# pour qu'on puisse "savoir où on en est" pendant le contournement
func _mettre_a_jour_odometrie(delta: float) -> void:
	# On intègre la consigne de braquage du contrôleur, pas la valeur envoyée à la voiture :
	# le trim compense un défaut mécanique, donc une fois ajouté à la commande la trajectoire
	# réelle correspond à `direction` (comme dans la simulation). Le remettre ici fausse
	# l'odométrie et empêche OBSTACLE_TURN_IN de se terminer.
	var braquage_local: float = cote * direction * theta_max
	angle_contournement += vitesse / EMPATTEMENT * tan(braquage_local) * delta
	x_contournement += vitesse * cos(angle_contournement) * delta
	y_contournement += vitesse * sin(angle_contournement) * delta

# Applique les contraintes d'accélération maximale et retourne [vitesse_contrainte, direction_contrainte].
func _appliquer_contraintes(vitesse_cible: float, direction_cible: float, delta: float) -> Array:
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
	var angle_cible: float = direction * theta_max

	# modèle bicycle
	var omega: float = vitesse / EMPATTEMENT * tan(angle_cible)

	var t := global_transform
	t.basis = t.basis.rotated(Vector3.UP, omega * delta)
	t.origin += -t.basis.z * vitesse * delta
	global_transform = t

	_animer_roues(delta, vitesse, angle_cible)

# Anime les roues (direction et rotation)
func _animer_roues(delta: float, vitesse_lineaire: float, angle_roue: float) -> void:
	if roue_av_g == null or roue_av_d == null or roue_ar_g == null or roue_ar_d == null:
		return

	var courbure := tan(angle_roue) / EMPATTEMENT

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

# Retourne le nom lisible de l'état courant.
func nom_etat() -> String:
	return WallState.keys()[wall_state]
