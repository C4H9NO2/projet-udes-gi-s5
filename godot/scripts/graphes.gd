extends Control

# Graphiques temps réel de la soucoupe et de la voiture.
# Le même script sert aux trois panneaux ; le type se règle dans l'inspecteur.
# L'accélération est estimée empiriquement en dérivant deux fois la position
# de la soucoupe (node "position_bille" de la voiture), à une fréquence réglable.

enum TypeGraphe {
	ACCELERATION,
	VITESSE_SOUCOUPE,
	VITESSE_VOITURE,
}

@export var type_graphe := TypeGraphe.ACCELERATION
@export var chemin_soucoupe: NodePath = ^"../../PiCar/position_bille"
@export var chemin_voiture: NodePath = ^"../../PiCar"
@export var fenetre_s := 8.0
@export var echelle_scene := 10.0	# le node Main de main.tscn est mis à l'échelle 10
@export var accel_max := 0.0		# 0 = lire Config.accel_max au démarrage
@export var frequence_echantillonnage := 60.0	# Hz (0 = chaque tick physique)
@export var vitesse_haut := 0.0		# m/s, 0 = échelle automatique

const TITRE_ACCELERATION := "Accélération de la soucoupe (m/s²)"
const TITRE_VITESSE_SOUCOUPE := "Vitesse de la soucoupe (m/s)"
const TITRE_VITESSE_VOITURE := "Vitesse de la voiture (m/s)"

const COULEUR_FOND := Color(0.04, 0.04, 0.06, 0.78)
const COULEUR_GRILLE := Color(1.0, 1.0, 1.0, 0.10)
const COULEUR_TEXTE := Color(1.0, 1.0, 1.0, 0.60)
const COULEUR_TITRE := Color(1.0, 1.0, 1.0, 0.95)
const COULEUR_MAX := Color(1.0, 0.33, 0.33, 0.90)
const COULEUR_TOTAL := Color(1.0, 1.0, 1.0, 0.95)
const COULEUR_LON := Color(0.35, 0.80, 1.0, 0.90)
const COULEUR_LAT := Color(1.0, 0.72, 0.25, 0.90)
const COULEUR_VITESSE_SOUCOUPE := Color(0.40, 0.90, 0.60, 0.95)
const COULEUR_VITESSE_VOITURE := Color(0.55, 0.65, 1.0, 0.95)
const COULEUR_V_MIN := Color(0.35, 0.80, 1.0, 0.85)
const COULEUR_V_MAX := Color(1.0, 0.33, 0.33, 0.90)

const MARGE_GAUCHE := 40.0
const MARGE_HAUT := 40.0
const MARGE_DROITE := 8.0
const MARGE_BAS := 12.0
const TAILLE_POLICE := 11
const TAILLE_POLICE_TITRE := 13

var _soucoupe: Node3D = null
var _voiture: Node = null
var _temps := 0.0
var _accumulateur := 0.0
var _derniere_pos := Vector3.ZERO
var _derniere_vitesse := Vector3.ZERO
var _nb_mesures := 0

var _t := PackedFloat32Array()
var _a_tot := PackedFloat32Array()
var _a_lon := PackedFloat32Array()
var _a_lat := PackedFloat32Array()
var _v := PackedFloat32Array()
var _v_voiture := PackedFloat32Array()

var _v_min := 0.0
var _v_max := 0.0


func _ready() -> void:
	_soucoupe = get_node_or_null(chemin_soucoupe) as Node3D
	if _soucoupe == null:
		push_warning("Graphes : soucoupe introuvable (%s)" % chemin_soucoupe)

	_voiture = get_node_or_null(chemin_voiture)
	if _voiture != null:
		# v_min/v_max peuvent être absents si le script de la voiture ne les expose pas encore
		var v_min_prop = _voiture.get("v_min")
		var v_max_prop = _voiture.get("v_max")
		if v_min_prop != null:
			_v_min = float(v_min_prop)
		if v_max_prop != null:
			_v_max = float(v_max_prop)

	if accel_max <= 0.0:
		var config := get_node_or_null("/root/Config")
		if config != null:
			accel_max = float(config.accel_max)


func _physics_process(delta: float) -> void:
	if _soucoupe == null or delta <= 0.0001:
		return

	# Échantillonnage à la fréquence choisie (la physique tourne à 240 Hz)
	var periode := delta
	if frequence_echantillonnage > 0.0:
		periode = 1.0 / frequence_echantillonnage
	_accumulateur += delta
	if _accumulateur < periode:
		return

	var dt := _accumulateur
	_accumulateur = 0.0
	_temps += dt

	var pos := _soucoupe.global_position / echelle_scene

	# Les deux premières mesures servent à amorcer la dérivée première
	if _nb_mesures < 2:
		if _nb_mesures == 1:
			_derniere_vitesse = (pos - _derniere_pos) / dt
		_derniere_pos = pos
		_nb_mesures += 1
		return

	var vitesse := (pos - _derniere_pos) / dt
	var accel := (vitesse - _derniere_vitesse) / dt
	_derniere_pos = pos
	_derniere_vitesse = vitesse

	# Projection sur les axes de la voiture (normalisés, car le parent est mis à l'échelle 10)
	var avant := -_soucoupe.global_transform.basis.z.normalized()
	var lateral := _soucoupe.global_transform.basis.x.normalized()
	var vitesse_voiture := 0.0
	if _voiture != null:
		vitesse_voiture = float(_voiture.get("vitesse"))
	_ajouter_echantillon(accel.length(), accel.dot(avant), accel.dot(lateral), vitesse.length(), vitesse_voiture)


func _ajouter_echantillon(a_tot: float, a_lon: float, a_lat: float, v: float, v_voiture: float) -> void:
	_t.append(_temps)
	_a_tot.append(a_tot)
	_a_lon.append(a_lon)
	_a_lat.append(a_lat)
	_v.append(v)
	_v_voiture.append(v_voiture)

	# Purge des échantillons sortis de la fenêtre glissante
	var debut := 0
	var limite := _temps - fenetre_s
	while debut < _t.size() and _t[debut] < limite:
		debut += 1
	if debut > 0:
		_t = _t.slice(debut)
		_a_tot = _a_tot.slice(debut)
		_a_lon = _a_lon.slice(debut)
		_a_lat = _a_lat.slice(debut)
		_v = _v.slice(debut)
		_v_voiture = _v_voiture.slice(debut)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COULEUR_FOND)

	var police := ThemeDB.fallback_font
	match type_graphe:
		TypeGraphe.ACCELERATION:
			_dessiner_acceleration(police)
		TypeGraphe.VITESSE_SOUCOUPE:
			_dessiner_vitesse_soucoupe(police)
		TypeGraphe.VITESSE_VOITURE:
			_dessiner_vitesse_voiture(police)


func _dessiner_acceleration(police: Font) -> void:
	_dessiner_titre(TITRE_ACCELERATION, police)

	var a_max := maxf(accel_max, 0.001)
	var a_haut := maxf(a_max * 1.6, 0.001)
	var zone := _zone()

	for valeur in [0.0, a_max * 0.5, a_max, a_max * 1.5]:
		_dessiner_ligne_grille(valeur, a_haut, zone, police)

	# Ligne de consigne a_max
	var y_max := _y_pour(a_max, a_haut, zone)
	draw_line(Vector2(zone.position.x, y_max), Vector2(zone.end.x, y_max), COULEUR_MAX, 1.5)

	_dessiner_courbe(_a_lat, COULEUR_LAT, 1.2, a_haut, zone)
	_dessiner_courbe(_a_lon, COULEUR_LON, 1.2, a_haut, zone)
	_dessiner_courbe(_a_tot, COULEUR_TOTAL, 1.8, a_haut, zone)

	if not _a_tot.is_empty():
		var i := _a_tot.size() - 1
		_dessiner_entete("a=%.4f   lon=%.4f   lat=%.4f   max=%.4f" % [
			_a_tot[i], _a_lon[i], _a_lat[i], a_max
		], zone, police)


func _dessiner_vitesse_soucoupe(police: Font) -> void:
	_dessiner_titre(TITRE_VITESSE_SOUCOUPE, police)

	var v_haut := vitesse_haut
	if v_haut <= 0.0:
		v_haut = 0.10
	var zone := _zone()

	for i in 5:
		_dessiner_ligne_grille(v_haut * float(i) / 4.0, v_haut, zone, police)

	_dessiner_courbe(_v, COULEUR_VITESSE_SOUCOUPE, 1.8, v_haut, zone)

	if not _v.is_empty():
		var i := _v.size() - 1
		_dessiner_entete("v=%.4f m/s" % _v[i], zone, police)


func _dessiner_vitesse_voiture(police: Font) -> void:
	_dessiner_titre(TITRE_VITESSE_VOITURE, police)

	var v_haut := vitesse_haut
	if v_haut <= 0.0:
		v_haut = maxf(_v_max * 1.3, 0.01)
	var zone := _zone()

	for i in 5:
		_dessiner_ligne_grille(v_haut * float(i) / 4.0, v_haut, zone, police)

	if _v_max > 0.0:
		_dessiner_reference(_v_min, "v_min", COULEUR_V_MIN, v_haut, zone, police)
		_dessiner_reference(_v_max, "v_max", COULEUR_V_MAX, v_haut, zone, police)
	_dessiner_courbe(_v_voiture, COULEUR_VITESSE_VOITURE, 1.8, v_haut, zone)

	if not _v_voiture.is_empty():
		var i := _v_voiture.size() - 1
		var texte := "v=%.4f" % _v_voiture[i]
		if _v_max > 0.0:
			texte += "   v_min=%.4f   v_max=%.4f" % [_v_min, _v_max]
		_dessiner_entete(texte, zone, police)


func _zone() -> Rect2:
	return Rect2(
		MARGE_GAUCHE,
		MARGE_HAUT,
		maxf(size.x - MARGE_GAUCHE - MARGE_DROITE, 1.0),
		maxf(size.y - MARGE_HAUT - MARGE_BAS, 1.0)
	)


func _dessiner_titre(texte: String, police: Font) -> void:
	draw_string(police, Vector2(0.0, 16.0), texte,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, TAILLE_POLICE_TITRE, COULEUR_TITRE)


func _dessiner_entete(texte: String, zone: Rect2, police: Font) -> void:
	draw_string(police, Vector2(zone.position.x + 4.0, 33.0), texte,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAILLE_POLICE, COULEUR_TEXTE)


func _dessiner_ligne_grille(valeur: float, echelle: float, zone: Rect2, police: Font) -> void:
	var y := _y_pour(valeur, echelle, zone)
	draw_line(Vector2(zone.position.x, y), Vector2(zone.end.x, y), COULEUR_GRILLE, 1.0)
	draw_string(police, Vector2(4.0, y + 4.0), "%.3f" % valeur,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, TAILLE_POLICE, COULEUR_TEXTE)


func _dessiner_reference(valeur: float, nom: String, couleur: Color, echelle: float,
		zone: Rect2, police: Font) -> void:
	var y := _y_pour(valeur, echelle, zone)
	draw_line(Vector2(zone.position.x, y), Vector2(zone.end.x, y), couleur, 1.2)
	draw_string(police, Vector2(zone.position.x, y - 3.0), "%s=%.3f" % [nom, valeur],
		HORIZONTAL_ALIGNMENT_RIGHT, zone.size.x, TAILLE_POLICE, couleur)


func _dessiner_courbe(valeurs: PackedFloat32Array, couleur: Color, epaisseur: float,
		echelle: float, zone: Rect2) -> void:
	if valeurs.size() < 2:
		return

	var points := PackedVector2Array()
	points.resize(valeurs.size())
	var t_debut := _temps - fenetre_s
	for i in valeurs.size():
		var x := zone.position.x + ((_t[i] - t_debut) / fenetre_s) * zone.size.x
		points[i] = Vector2(x, _y_pour(valeurs[i], echelle, zone))
	draw_polyline(points, couleur, epaisseur, true)


func _y_pour(valeur: float, echelle: float, zone: Rect2) -> float:
	return zone.end.y - clampf(valeur / echelle, 0.0, 1.0) * zone.size.y
