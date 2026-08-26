extends RefCounted

const CommitReveal = preload("res://src/protocol/commit_reveal.gd")


static func hash_state(state: Dictionary) -> String:
	return CommitReveal.sha256_text(canonical_encode(state))


static func canonical_encode(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return JSON.stringify(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_ARRAY:
			var encoded_items := PackedStringArray()
			for item in value:
				encoded_items.append(canonical_encode(item))
			return "[%s]" % ",".join(encoded_items)
		TYPE_DICTIONARY:
			var keys: Array = value.keys()
			keys.sort_custom(func(left, right): return str(left) < str(right))
			var encoded_fields := PackedStringArray()
			for key in keys:
				encoded_fields.append("%s:%s" % [JSON.stringify(str(key)), canonical_encode(value[key])])
			return "{%s}" % ",".join(encoded_fields)
		_:
			return JSON.stringify(value)
