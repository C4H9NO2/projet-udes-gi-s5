extends Node

var donnees: Dictionary = {}

func _ready() -> void:
	charger()

func charger() -> void:
	var chemin := "res://config.json"
	if not OS.has_feature("editor"):
		chemin = OS.get_executable_path().get_base_dir().path_join("config.json")
	var fichier := FileAccess.open(chemin, FileAccess.READ)
	if fichier == null:
		push_error("config.json introuvable : " + chemin)
		return
	var resultat = JSON.parse_string(fichier.get_as_text())
	if resultat == null:
		push_error("config.json invalide (erreur de syntaxe)")
		return
	donnees = resultat
