extends SceneTree

## One player leaving used to leave the other polling a torn-down ENet peer once
## per frame, filling the log with "The multiplayer instance isn't currently
## active". This connects two NetworkMatch peers the way the interface does,
## drops one, and keeps polling the survivor exactly as _process would.

const NetworkMatch = preload("res://src/network/network_match.gd")
const DirectTransport = preload("res://src/network/direct_transport.gd")

const PORT := 8951

var host: Variant = NetworkMatch.new()
var joiner: Variant = NetworkMatch.new()
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if host.host_address(PORT) != OK:
		_check(false, "Host could not start listening")
		_finish()
		return

	var joined := false
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		host.poll()
		joiner.poll()
		if not joined:
			joined = true
			if joiner.join_address("127.0.0.1:%d" % PORT) != OK:
				_check(false, "Joiner could not connect to the host")
				_finish()
				return
		if host.connected and joiner.connected:
			break
		await process_frame
	_check(host.connected and joiner.connected, "The two peers never connected")
	if not (host.connected and joiner.connected):
		_finish()
		return

	# The joiner quits, the way closing a window does.
	joiner.shutdown()

	# The survivor keeps being polled every frame. Reaching the end of this loop
	# without the engine erroring is the assertion; the guard that makes it hold
	# is in DirectTransport.poll and NetworkMatch.poll.
	for _frame in 240:
		host.poll()
		await process_frame
	_check(not host.connected, "The host still reports a live link after the opponent left")
	_check(host.transport == null, "The host is still holding a transport it can only poll into an error")

	# A joiner that never reaches a host must give up rather than hang forever.
	var orphan: Variant = NetworkMatch.new()
	var orphan_failed := [false]
	orphan.match_failed.connect(func(_message): orphan_failed[0] = true)
	orphan.join_address("127.0.0.1:%d" % (PORT + 7))
	var orphan_deadline := Time.get_ticks_msec() + int((DirectTransport.CONNECT_TIMEOUT_SECONDS + 5.0) * 1000.0)
	while Time.get_ticks_msec() < orphan_deadline and not orphan_failed[0]:
		orphan.poll()
		await process_frame
	_check(orphan_failed[0], "A joiner that cannot reach a host never reported the failure")
	orphan.shutdown()

	if not _failed:
		print("PASS: direct transport survives a disconnect")
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		printerr("FAIL: %s" % message)


func _finish() -> void:
	host.shutdown()
	joiner.shutdown()
	var result_file := FileAccess.open("res://tests/direct-disconnect-result.tmp", FileAccess.WRITE)
	if result_file != null:
		result_file.store_string("1" if _failed else "0")
	quit(1 if _failed else 0)
