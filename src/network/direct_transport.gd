extends RefCounted

## A plain host/join transport over ENet.
##
## This is the simple alternative to the WebRTC path: one player listens on a
## port, the other connects to their address, and no signalling codes are
## exchanged at all. On one machine or a LAN it needs no configuration; over
## the internet the listening player has to forward the port on their router.
##
## It deliberately exposes the same interface as WebRTCTransport
## (poll / send_message / close plus these signals) so NetworkMatch can drive
## either one without knowing which is in use.

signal connected()
signal message_received(message: Dictionary)
signal disconnected(message: String)
signal transport_failed(message: String)

const DEFAULT_PORT := 8910
const CHANNEL := 0
## How long a joiner waits for the host to answer before giving up. ENet sits in
## CONNECTING indefinitely when nothing is listening, so without this the player
## waits forever with no message.
const CONNECT_TIMEOUT_SECONDS := 8.0

var peer: ENetMultiplayerPeer
var is_host := false
var is_connected := false
var _failure_emitted := false
## Set once the link is over, either side, for any reason. Polling an ENet peer
## after that point asserts, so every path that ends the link raises this.
var _link_finished := false
var _connect_deadline_ms := 0


func host(port: int = DEFAULT_PORT) -> Error:
	is_host = true
	peer = ENetMultiplayerPeer.new()
	# One opponent only; this is a two-player game.
	var error := peer.create_server(port, 1)
	if error != OK:
		peer = null
		transport_failed.emit(_host_error_message(port, error))
		return error
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	is_host = false
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		peer = null
		transport_failed.emit("Could not reach %s on port %d" % [address, port])
		return error
	_connect_deadline_ms = Time.get_ticks_msec() + int(CONNECT_TIMEOUT_SECONDS * 1000.0)
	return OK


func poll() -> void:
	if peer == null:
		return
	# A closed or dropped peer stays assigned but stops being active, and polling
	# one asserts inside ENet. The caller polls every frame, so without this the
	# first drop turns into an error every frame for the rest of the session.
	if _link_finished:
		return
	peer.poll()
	# Handlers run synchronously from the signals emitted below, and a handler
	# that closes this transport nulls `peer` underneath us. Every step after an
	# emit therefore re-checks rather than assuming the peer is still there.
	if peer == null:
		return

	# A listening host reports DISCONNECTED until someone arrives, so only the
	# joining side treats that status as a failure. The host learns about the
	# opponent arriving and leaving through peer_connected/peer_disconnected.
	var status := peer.get_connection_status()

	# ENet reports CONNECTING forever when nothing answers, so the wait is bounded
	# here rather than left to the player to notice.
	if (
		not is_host
		and not is_connected
		and not _failure_emitted
		and status == MultiplayerPeer.CONNECTION_CONNECTING
		and _connect_deadline_ms > 0
		and Time.get_ticks_msec() > _connect_deadline_ms
	):
		_failure_emitted = true
		_link_finished = true
		transport_failed.emit("The host did not answer. Check the address and that they are hosting.")
		return

	if not is_host and status == MultiplayerPeer.CONNECTION_DISCONNECTED and not _failure_emitted:
		_failure_emitted = true
		_link_finished = true
		if is_connected:
			is_connected = false
			disconnected.emit("The other player disconnected")
		else:
			transport_failed.emit("Could not reach the host. Check the address and that they are hosting.")
		return

	while peer != null and peer.get_available_packet_count() > 0:
		var packet := peer.get_packet()
		# A peer connecting or dropping surfaces as an ENet event rather than a
		# packet, so connection state is tracked from the status transitions
		# above and the first packet exchange below.
		var parsed = JSON.parse_string(packet.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			if str(parsed.get("__link", "")) == "hello":
				_mark_connected()
				continue
			message_received.emit(parsed)
		else:
			transport_failed.emit("Received malformed gameplay JSON")

	# The client knows it is connected as soon as ENet reports the link is up.
	# The host is told through peer_connected instead.
	if peer != null and not is_connected and not is_host and status == MultiplayerPeer.CONNECTION_CONNECTED:
		_send_hello()
		_mark_connected()


func send_message(message: Dictionary) -> Error:
	if peer == null or not is_connected:
		return ERR_UNCONFIGURED
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	peer.transfer_channel = CHANNEL
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	return peer.put_packet(JSON.stringify(message).to_utf8_buffer())


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	is_connected = false
	_link_finished = true


## Every address this machine can be reached on, best first, so the hosting
## player can tell their opponent where to connect.
static func local_addresses(port: int = DEFAULT_PORT) -> Dictionary:
	var lan := ""
	for address in IP.get_local_addresses():
		# Skip loopback and IPv6; a LAN address is what an opponent needs.
		if address.begins_with("127.") or address.contains(":"):
			continue
		if address.begins_with("192.168.") or address.begins_with("10.") or address.begins_with("172."):
			lan = address
			break
		if lan.is_empty():
			lan = address
	return {
		"local": "127.0.0.1:%d" % port,
		"lan": "%s:%d" % [lan, port] if not lan.is_empty() else "",
		"port": port,
	}


func _on_peer_connected(_id: int) -> void:
	_send_hello()
	_mark_connected()


func _on_peer_disconnected(_id: int) -> void:
	# A host keeps its socket listening so a dropped player can come back inside
	# the reconnection window. Marking the link finished here would close it and
	# turn every brief drop into a lost match.
	_link_finished = not is_host
	if is_connected:
		is_connected = false
		disconnected.emit("The other player disconnected")


func _send_hello() -> void:
	if peer == null:
		return
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_BROADCAST)
	peer.transfer_channel = CHANNEL
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.put_packet(JSON.stringify({"__link": "hello"}).to_utf8_buffer())


func _mark_connected() -> void:
	if is_connected:
		return
	is_connected = true
	connected.emit()


func _host_error_message(port: int, error: Error) -> String:
	if error == ERR_ALREADY_IN_USE or error == ERR_CANT_CREATE:
		return "Port %d is already in use. Another copy of the game may still be hosting." % port
	return "Could not listen on port %d. Error %d" % [port, error]
