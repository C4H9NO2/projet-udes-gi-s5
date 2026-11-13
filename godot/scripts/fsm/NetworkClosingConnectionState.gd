class_name NetworkFSMClosingConnectionState
extends StateMachineState

var temps_fermeture = 0.0


# Called when the state machine enters this state.
func on_enter() -> void:
	print("Network Closing connection State entered")
	temps_fermeture = 0.0
	var socket = get_parent().socket
	var etat = socket.get_ready_state()
	if etat == WebSocketPeer.STATE_OPEN or etat == WebSocketPeer.STATE_CONNECTING:
		socket.close(1000, "Connection was closed by the user")


# Called every frame when this state is active.
func on_process(delta: float) -> void:
	temps_fermeture += delta
	var socket = get_parent().socket
	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED or temps_fermeture >= 1.0:
		get_node("../../GridContainer/btn_Connect").text = "Connect"
		get_node("../../GridContainer/btn_Connect").disabled = false
		get_node("../../GridContainer/lb_ConnectionStatusPackets").text = "Disconnected"
		get_parent().current_state = $"../NetworkWaitingState"

# Called every physics frame when this state is active.
func on_physics_process(delta: float) -> void:
	pass

# Called when there is an input event while this state is active.
func on_input(event: InputEvent) -> void:
	pass

# Called when the state machine exits this state.
func on_exit() -> void:
	print("Network Closing connection State left")
