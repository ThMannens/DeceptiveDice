extends SceneTree

## Reports what ICE actually produces on this machine and whether two local peers
## can complete a connection through the manual-code path.

const NetworkMatch = preload("res://src/network/network_match.gd")
const ManualSignalCode = preload("res://src/network/manual_signal_code.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var host = NetworkMatch.new()
	var joiner = NetworkMatch.new()
	host.host_direct()

	var offer := ""
	var answer := ""
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline:
		host.poll()
		joiner.poll()
		if offer.is_empty() and host.current_stage() == "DIRECT_HOST_OFFER":
			offer = str(host.manual_code)
			var decoded := ManualSignalCode.decode(offer, "offer")
			var cands: Array = decoded["payload"]["candidates"]
			print("offer ready: %d candidates" % cands.size())
			for c in cands:
				print("   ", str(c["name"]).substr(0, 90))
			joiner.join_direct(offer)
		elif not offer.is_empty() and answer.is_empty() and joiner.current_stage() == "DIRECT_JOIN_ANSWER":
			answer = str(joiner.manual_code)
			var d2 := ManualSignalCode.decode(answer, "answer")
			print("answer ready: %d candidates" % d2["payload"]["candidates"].size())
			host.accept_direct_answer(answer)
		if host.connected and joiner.connected:
			break
		await process_frame

	print("host connected=%s joiner connected=%s" % [host.connected, joiner.connected])
	print("host stage=%s joiner stage=%s" % [host.current_stage(), joiner.current_stage()])
	if host.transport != null and host.transport.peer != null:
		print("host ice conn state=%d gathering=%d" % [
			host.transport.peer.get_connection_state(),
			host.transport.peer.get_gathering_state(),
		])
	quit(0)
