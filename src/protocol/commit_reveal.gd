extends RefCounted


static func generate_secret() -> String:
	return Crypto.new().generate_random_bytes(32).hex_encode()


static func secret_commit(secret: String) -> String:
	return sha256_text("secret|%s" % secret)


static func decision_commit(kind: String, nonce: String, value: Variant) -> String:
	return sha256_text("%s|%s|%s" % [kind, nonce, JSON.stringify(value)])


static func verify_secret(secret: String, expected_commit: String) -> bool:
	return secret_commit(secret) == expected_commit


static func verify_decision(kind: String, nonce: String, value: Variant, expected_commit: String) -> bool:
	return decision_commit(kind, nonce, value) == expected_commit


static func derive_roll(roller_secret: String, observer_secret: String) -> int:
	var digest := sha256_bytes("roll|%s|%s" % [roller_secret, observer_secret])
	var remainder := 0
	for byte in digest:
		remainder = (remainder * 256 + int(byte)) % 20
	return remainder + 1


static func sha256_text(value: String) -> String:
	return sha256_bytes(value).hex_encode()


static func sha256_bytes(value: String) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish()
