extends RefCounted

const PREFIX := "DD1."
const VERSION := 1


static func encode(kind: String, match_id: String, description: Dictionary, candidates: Array) -> String:
	var payload := {
		"version": VERSION,
		"kind": kind,
		"match_id": match_id,
		"description_type": str(description.get("description_type", "")),
		"sdp": str(description.get("sdp", "")),
		"candidates": candidates.duplicate(true),
	}
	return PREFIX + Marshalls.raw_to_base64(JSON.stringify(payload).to_utf8_buffer())


static func decode(code: String, expected_kind: String = "") -> Dictionary:
	var compact := code.strip_edges().replace("\r", "").replace("\n", "")
	if not compact.begins_with(PREFIX):
		return _error("This is not a Deceptive Dice connection code")
	if compact.length() > 262144:
		return _error("The connection code is too large")
	var encoded := compact.trim_prefix(PREFIX)
	if encoded.is_empty() or encoded.length() % 4 != 0:
		return _error("The connection code is damaged")
	for character in encoded:
		if character not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=":
			return _error("The connection code is damaged")
	var raw := Marshalls.base64_to_raw(encoded)
	if raw.is_empty():
		return _error("The connection code is damaged")
	var parsed = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("The connection code does not contain valid data")
	var payload: Dictionary = parsed
	if int(payload.get("version", 0)) != VERSION:
		return _error("The connection code uses an unsupported version")
	var kind := str(payload.get("kind", ""))
	if kind not in ["offer", "answer"] or (not expected_kind.is_empty() and kind != expected_kind):
		return _error("The connection code is the wrong type")
	var match_id := str(payload.get("match_id", ""))
	if not match_id.begins_with("direct-") or match_id.length() != 39:
		return _error("The connection code has no match identifier")
	var sdp := str(payload.get("sdp", ""))
	if str(payload.get("description_type", "")) != kind or sdp.is_empty() or sdp.length() > 131072:
		return _error("The connection description is incomplete")
	var candidates = payload.get("candidates")
	if typeof(candidates) != TYPE_ARRAY or candidates.size() > 256:
		return _error("The connection candidates are malformed")
	for candidate in candidates:
		if typeof(candidate) != TYPE_DICTIONARY:
			return _error("A connection candidate is malformed")
		for field in ["media", "index", "name"]:
			if not candidate.has(field):
				return _error("A connection candidate is incomplete")
		if str(candidate["media"]).length() > 64 or int(candidate["index"]) < 0 or int(candidate["index"]) > 64 or str(candidate["name"]).length() > 16384:
			return _error("A connection candidate is malformed")
	return {"ok": true, "payload": payload, "error": ""}


static func _error(message: String) -> Dictionary:
	return {"ok": false, "payload": {}, "error": message}
