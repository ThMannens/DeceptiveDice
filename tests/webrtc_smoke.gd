extends SceneTree

const WebRTCTransport = preload("res://src/network/webrtc_transport.gd")

var host := WebRTCTransport.new()
var joiner := WebRTCTransport.new()
var started_at := 0
var sent_test_message := false
var received_test_message := false
var received_reply := false
var failed := false


func _initialize() -> void:
	started_at = Time.get_ticks_msec()
	host.local_signal_created.connect(func(payload): joiner.accept_signal(payload))
	joiner.local_signal_created.connect(func(payload): host.accept_signal(payload))
	host.transport_failed.connect(func(message): _fail(message))
	joiner.transport_failed.connect(func(message): _fail(message))
	host.disconnected.connect(func(message): _fail(message))
	joiner.disconnected.connect(func(message): _fail(message))
	host.message_received.connect(_on_host_message)
	joiner.message_received.connect(_on_joiner_message)
	var host_error := host.initialize(true)
	var joiner_error := joiner.initialize(false)
	if host_error != OK or joiner_error != OK:
		_fail("WebRTC transports failed to initialize")
		_finish()
		return
	if host.start_offer() != OK:
		_fail("WebRTC host failed to create an offer")
		_finish()


func _process(_delta: float) -> bool:
	host.poll()
	joiner.poll()
	if not sent_test_message and host.is_connected and joiner.is_connected:
		sent_test_message = true
		if host.send_message({"type": "smoke", "value": 42}) != OK:
			_fail("Host could not send a WebRTC data message")
	if received_test_message and received_reply:
		print("PASS: local WebRTC data channel smoke test")
		_finish()
	elif Time.get_ticks_msec() - started_at > 12000:
		_fail("Local WebRTC peers did not exchange data within 12 seconds")
		_finish()
	return false


func _on_joiner_message(message: Dictionary) -> void:
	if message.get("type") == "smoke" and int(message.get("value", 0)) == 42:
		received_test_message = true
		if joiner.send_message({"type": "reply", "value": 84}) != OK:
			_fail("Joiner could not reply over WebRTC")


func _on_host_message(message: Dictionary) -> void:
	if message.get("type") == "reply" and int(message.get("value", 0)) == 84:
		received_reply = true


func _fail(message: String) -> void:
	if not failed:
		printerr("FAIL: %s" % message)
	failed = true


func _finish() -> void:
	host.close()
	joiner.close()
	var result_file := FileAccess.open("res://tests/webrtc-smoke-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string("1" if failed else "0")
	quit(1 if failed else 0)
