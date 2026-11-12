extends Node3D

# Variables
var HostRegex = RegEx.new()

# Engine functions
# Called when the node enters the scene tree for the first time.
func _ready():
	HostRegex.compile(r'^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])\.)*([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])$')
	#get_node("NetworkFSM").current_state = $NetworkFSM/NetworkInitState
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

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


func _on_camera_toggle_toggled(toggled_on):
	$PiCar/Camera3D.current = not toggled_on
	$"Caméra libre".current = toggled_on
	if not toggled_on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_check_box_toggled(toggled_on):
	if toggled_on:
		$GridContainer/le_IpAdress.text = "127.0.0.1"
		get_node("NetworkFSM").current_state = $NetworkFSM/NetworkInitState
