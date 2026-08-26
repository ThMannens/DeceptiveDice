extends RefCounted

signal local_signal_created(payload: Dictionary)
signal connected()
signal message_received(message: Dictionary)
signal disconnected(message: String)
signal transport_failed(message: String)

var peer: WebRTCPeerConnection
var channel: WebRTCDataChannel
var is_host := false
var is_connected := false
var _remote_description_set := false
var _pending_ice: Array[Dictionary] = []
var _failure_emitted := false


func initialize(host: bool, ice_servers: Array = []) -> Error:
	is_host = host
	peer = WebRTCPeerConnection.new()
	peer.session_description_created.connect(_on_session_description_created)
	peer.ice_candidate_created.connect(_on_ice_candidate_created)
	var configuration := {
		"iceServers": ice_servers if not ice_servers.is_empty() else [
			{"urls": ["stun:stun.l.google.com:19302"]},
		],
	}
	var error := peer.initialize(configuration)
	if error != OK:
		transport_failed.emit("WebRTC initialization failed. Error %d" % error)
		return error
	channel = peer.create_data_channel("deceptive-dice", {
		"negotiated": true,
		"id": 1,
		"ordered": true,
	})
	if channel == null:
		transport_failed.emit("Could not create the WebRTC data channel")
		return ERR_CANT_CREATE
	channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
	return OK


func start_offer() -> Error:
	if not is_host:
		return ERR_UNAUTHORIZED
	var error := peer.create_offer()
	if error != OK:
		transport_failed.emit("Could not create WebRTC offer. Error %d" % error)
	return error


func accept_signal(payload: Dictionary) -> void:
	match str(payload.get("kind", "")):
		"sdp":
			var description_type := str(payload.get("description_type", ""))
			var sdp := str(payload.get("sdp", ""))
			var error := peer.set_remote_description(description_type, sdp)
			if error != OK:
				transport_failed.emit("Could not apply remote WebRTC description. Error %d" % error)
				return
			_remote_description_set = true
			for candidate in _pending_ice:
				peer.add_ice_candidate(candidate["media"], int(candidate["index"]), candidate["name"])
			_pending_ice.clear()
		"ice":
			var candidate := {
				"media": str(payload.get("media", "")),
				"index": int(payload.get("index", 0)),
				"name": str(payload.get("name", "")),
			}
			if _remote_description_set:
				peer.add_ice_candidate(candidate["media"], candidate["index"], candidate["name"])
			else:
				_pending_ice.append(candidate)
		_:
			transport_failed.emit("Unknown WebRTC signalling payload")


func poll() -> void:
	if peer == null:
		return
	peer.poll()
	if channel != null:
		channel.poll()
		if not is_connected and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			is_connected = true
			connected.emit()
		while channel.get_available_packet_count() > 0:
			var packet := channel.get_packet()
			var message = JSON.parse_string(packet.get_string_from_utf8())
			if typeof(message) == TYPE_DICTIONARY:
				message_received.emit(message)
			else:
				transport_failed.emit("Received malformed gameplay JSON")
	var state := peer.get_connection_state()
	if state in [WebRTCPeerConnection.STATE_FAILED, WebRTCPeerConnection.STATE_CLOSED] and not _failure_emitted:
		_failure_emitted = true
		disconnected.emit("WebRTC connection failed" if state == WebRTCPeerConnection.STATE_FAILED else "WebRTC connection closed")


func send_message(message: Dictionary) -> Error:
	if channel == null or channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		return ERR_UNCONFIGURED
	return channel.put_packet(JSON.stringify(message).to_utf8_buffer())


func is_gathering_complete() -> bool:
	return peer != null and peer.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE


func close() -> void:
	if channel != null:
		channel.close()
	if peer != null:
		peer.close()
	is_connected = false


func _on_session_description_created(description_type: String, sdp: String) -> void:
	var error := peer.set_local_description(description_type, sdp)
	if error != OK:
		transport_failed.emit("Could not set local WebRTC description. Error %d" % error)
		return
	local_signal_created.emit({
		"kind": "sdp",
		"description_type": description_type,
		"sdp": sdp,
	})


func _on_ice_candidate_created(media: String, index: int, name: String) -> void:
	local_signal_created.emit({
		"kind": "ice",
		"media": media,
		"index": index,
		"name": name,
	})
