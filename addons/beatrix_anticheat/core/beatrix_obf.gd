extends RefCounted
class_name BeatrixObf
## Runtime XOR helper to hide string literals from trivial grep (not encryption — keys ship with the game).
## Prefer Godot export encryption / compiled GDScript; use this only as a light extra layer.


static func encode_utf8(plain: String, passphrase: String) -> PackedByteArray:
	var p: PackedByteArray = plain.to_utf8_buffer()
	var k: PackedByteArray = passphrase.to_utf8_buffer()
	if k.is_empty():
		k.append(85)
	var out: PackedByteArray = PackedByteArray()
	out.resize(p.size())
	for i: int in p.size():
		out[i] = p[i] ^ k[i % k.size()]
	return out


static func decode_utf8(data: PackedByteArray, passphrase: String) -> String:
	if data.is_empty():
		return ""
	var k: PackedByteArray = passphrase.to_utf8_buffer()
	if k.is_empty():
		k.append(85)
	var out: PackedByteArray = PackedByteArray()
	out.resize(data.size())
	for i: int in data.size():
		out[i] = data[i] ^ k[i % k.size()]
	return out.get_string_from_utf8()


## Split passphrase and merge at runtime to avoid one literal holding the whole key.
static func decode_utf8_joined(data: PackedByteArray, key_parts: PackedStringArray) -> String:
	var joined: String = "".join(key_parts)
	return decode_utf8(data, joined)
