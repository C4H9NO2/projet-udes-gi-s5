extends Node3D

# Variables
var HostRegex = RegEx.new()
var _derniere_valeur_etat := -1
var _label_etat: Label = null

# Engine functions
# Called when the node enters the scene tree for the first time.
func _ready():
	HostRegex.compile(r'^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])\.)*([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])$')
	#get_node("NetworkFSM").current_state = $NetworkFSM/NetworkInitState
	_creer_label_etat()

func _creer_label_etat() -> void:
	var couche := CanvasLayer.new()
	couche.name = "CoucheEtat"
	couche.layer = 10
	add_child(couche)

	_label_etat = Label.new()
	_label_etat.name = "LabelWallState"
	_label_etat.anchor_left = 1.0
	_label_etat.anchor_top = 1.0
	_label_etat.anchor_right = 1.0
	_label_etat.anchor_bottom = 1.0
	_label_etat.offset_left = -300.0
	_label_etat.offset_top = -38.0
	_label_etat.offset_right = -8.0
	_label_etat.offset_bottom = -8.0
	_label_etat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label_etat.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label_etat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_etat.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label_etat.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label_etat.add_theme_constant_override("outline_size", 5)
	_label_etat.text = $PiCar.nom_etat()
	couche.add_child(_label_etat)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var etat: int = $PiCar.wall_state
	if etat != _derniere_valeur_etat:
		_derniere_valeur_etat = etat
		if _label_etat != null:
			_label_etat.text = $PiCar.nom_etat()

# Signals functions
func _on_quit_pressed():
	$NetworkFSM.current_state = $NetworkFSM/NetworkClosingConnectionState
	get_tree().quit()

func _on_connect_pressed():
	# IP address REGEX before starting connection
	if get_node("GridContainer/btn_Connect").text == "Disconnect":
		$NetworkFSM.current_state = $NetworkFSM/NetworkClosingConnectionState
	else:
		var adresse = get_node("GridContainer/le_IpAdress").text.strip_edges()
		if HostRegex.search(adresse) != null:
			get_node("GridContainer/le_IpAdress").text = adresse
			# Disable button before having a connection
			get_node("GridContainer/btn_Connect").disabled = true
			get_node("GridContainer/lb_ConnectionStatusPackets").text = "Connecting"
			get_node("NetworkFSM").current_state = $NetworkFSM/NetworkInitState
		else:
			get_node("GridContainer/lb_ConnectionStatusPackets").text = "Wrong IP address or hostname!"


func _on_manual_control_toggled(toggled_on):
	$PiCar.manual_control_enabled = toggled_on

func _on_bypass_contraintes_toggled(toggled_on):
	$PiCar.bypass_contraintes = toggled_on

func _on_cacher_graphiques_toggled(toggled_on):
	for graphe in $Graphes.get_children():
		graphe.visible = not toggled_on

func _on_camera_toggle_toggled(toggled_on):
	$PiCar/Camera3D.current = not toggled_on
	$"Caméra libre".current = toggled_on
	if not toggled_on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_check_box_toggled(toggled_on):
	if toggled_on:
		$GridContainer/le_IpAdress.text = "127.0.0.1"
		get_node("NetworkFSM").current_state = $NetworkFSM/NetworkInitState
