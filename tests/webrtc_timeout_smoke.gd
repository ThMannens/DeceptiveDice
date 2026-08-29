extends SceneTree

## WebRTC reports no error when two peers simply cannot find a route to each
## other: it sits in CONNECTING forever. That left the player on a screen that
## never changed. This drives a host that accepts a well-formed answer whose
## candidates lead nowhere, and asserts the wait is bounded and explained.

const NetworkMatch = preload("res://src/network/network_match.gd")
const ManualSignalCode = preload("res://src/network/manual_signal_code.gd")

var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host = NetworkMatch.new()
	var failure_message := [""]
	host.match_failed.connect(func(message): failure_message[0] = str(message))
	host.host_direct()

	# Wait for the host's own offer, which tells us its match id.
	var offer := ""
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline and offer.is_empty():
		host.poll()
		if host.current_stage() == "DIRECT_HOST_OFFER":
			offer = str(host.manual_code)
		await process_frame
	_check(not offer.is_empty(), "The host never produced an offer code")
	if offer.is_empty():
		_finish(host)
		return

	# An answer that parses and matches the offer, but whose only candidate is a
	# documentation address nothing will ever answer on.
	var match_id := str(ManualSignalCode.decode(offer, "offer")["payload"]["match_id"])
	var dead_answer := ManualSignalCode.encode(
		"answer",
		match_id,
		{"description_type": "answer", "sdp": _unroutable_sdp()},
		[{"media": "0", "index": 0, "name": "candidate:1 1 UDP 2113937151 192.0.2.1 9 typ host"}],
	)
	host.accept_direct_answer(dead_answer)

	var timeout_deadline := Time.get_ticks_msec() + int((NetworkMatch.CHANNEL_OPEN_TIMEOUT_SECONDS + 15.0) * 1000.0)
	while Time.get_ticks_msec() < timeout_deadline and failure_message[0].is_empty():
		host.poll()
		await process_frame

	_check(not failure_message[0].is_empty(), "The host waited forever instead of reporting that it could not connect")
	_check(host.current_stage() == "FAILED", "A connection that never opened left the interface on the connecting screen")
	if not _failed:
		print("PASS: an unreachable peer times out instead of hanging")
	_finish(host)


func _unroutable_sdp() -> String:
	# Minimal but structurally valid: enough for the peer to accept it as an
	# answer, pointing at an address in the reserved documentation range.
	return (
		"v=0\r\no=- 0 0 IN IP4 192.0.2.1\r\ns=-\r\nt=0 0\r\n"
		+ "a=group:BUNDLE 0\r\nm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n"
		+ "c=IN IP4 192.0.2.1\r\na=mid:0\r\na=ice-ufrag:dead\r\na=ice-pwd:deadbeefdeadbeefdeadbe\r\n"
		+ "a=fingerprint:sha-256 00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00\r\n"
		+ "a=setup:active\r\na=sctp-port:5000\r\n"
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: %s" % message)


func _finish(host) -> void:
	host.shutdown()
	var result_file := FileAccess.open("res://tests/webrtc-timeout-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string("1" if _failed else "0")
	quit(1 if _failed else 0)
