extends Node

var donnees: Dictionary = {}

# Valeurs lues dans config.jsonc
var delai_depart_s := 3.0
var vitesse_max := 0.075
var vitesse_moyenne := 0.065
var vitesse_faible := 0.055
var vitesse_m_s_par_unite_pwm := 0.5769230769
var accel_max := 0.065
var distance_arret := 1.3
var temps_pause_avant_recul := 1.0
var direction_contournerment := 1.0
var angle_braquage_max_deg := 45.0
var steer_speed_deg_per_s := 180.0
var steer_speed_normalise := 4.0
var trim_direction_deg := -8.5
var trim_direction_normalise := 0.0
var frequence_envoi_commande_hz := 50.0

func _ready() -> void:
	_charger_valeurs()
	charger()

func charger() -> void:
	var chemin := "res://config.jsonc"
	if not OS.has_feature("editor"):
		chemin = OS.get_executable_path().get_base_dir().path_join("config.jsonc")
	var fichier := FileAccess.open(chemin, FileAccess.READ)
	if fichier == null:
		push_error("config.jsonc introuvable : " + chemin)
		return
	var resultat = JSON.parse_string(_retirer_commentaires(fichier.get_as_text()))
	if resultat == null:
		push_error("config.jsonc invalide (erreur de syntaxe)")
		return
	donnees = resultat
	_charger_valeurs()

func _charger_valeurs() -> void:
	delai_depart_s = float(donnees.get("delai_depart_s", delai_depart_s))
	vitesse_max = float(donnees.get("vitesse_max_m_s", vitesse_max))
	vitesse_moyenne = float(donnees.get("vitesse_moyenne_m_s", vitesse_moyenne))
	vitesse_faible = float(donnees.get("vitesse_faible_m_s", vitesse_faible))
	vitesse_m_s_par_unite_pwm = float(donnees.get("vitesse_m_s_par_unite_pwm", vitesse_m_s_par_unite_pwm))
	accel_max = float(donnees.get("acceleration_max_m_s2", accel_max))
	distance_arret = float(donnees.get("distance_arret", distance_arret))
	temps_pause_avant_recul = float(donnees.get("temps_pause_avant_recul", temps_pause_avant_recul))
	direction_contournerment = float(donnees.get("direction_contournerment", direction_contournerment))

	angle_braquage_max_deg = float(donnees.get("angle_braquage_max_deg", angle_braquage_max_deg))
	steer_speed_deg_per_s = float(donnees.get("steer_speed_deg_per_s", steer_speed_deg_per_s))
	steer_speed_normalise = steer_speed_deg_per_s / maxf(angle_braquage_max_deg, 0.001)

	trim_direction_deg = float(donnees.get("trim_direction_deg", trim_direction_deg))
	trim_direction_normalise = trim_direction_deg / maxf(angle_braquage_max_deg, 0.001)

	frequence_envoi_commande_hz = float(donnees.get("frequence_envoi_commande_hz", frequence_envoi_commande_hz))

# Retire les commentaires // et /* */ du JSONC avant de le parser.
func _retirer_commentaires(texte: String) -> String:
	var resultat := ""
	var i := 0
	var n := texte.length()
	var dans_chaine := false
	while i < n:
		var c := texte[i]
		if dans_chaine:
			resultat += c
			if c == "\\" and i + 1 < n:
				resultat += texte[i + 1]
				i += 2
				continue
			if c == '"':
				dans_chaine = false
			i += 1
		elif c == '"':
			dans_chaine = true
			resultat += c
			i += 1
		elif c == "/" and i + 1 < n and texte[i + 1] == "/":
			i += 2
			while i < n and texte[i] != "\n":
				i += 1
		elif c == "/" and i + 1 < n and texte[i + 1] == "*":
			i += 2
			while i + 1 < n and not (texte[i] == "*" and texte[i + 1] == "/"):
				i += 1
			i += 2
		else:
			resultat += c
			i += 1
	return resultat
