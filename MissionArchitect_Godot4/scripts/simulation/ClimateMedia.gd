class_name ClimateMedia
extends Node

## Fetches real NASA WorldView imagery at runtime and caches it under
## user://climate_media/ so the mission stays fully playable offline after
## the first pass.  Every consumer degrades to the numeric data card when a
## fetch fails — the imagery is proof, not a dependency.

signal image_ready(texture: Texture2D)

const CACHE_DIR := "user://climate_media/"

var _req: HTTPRequest
var _url := ""

func _ready() -> void:
	_req = HTTPRequest.new()
	_req.timeout = 20.0
	add_child(_req)
	_req.request_completed.connect(_on_done)

static func cache_path(url: String) -> String:
	return CACHE_DIR + str(url.hash()) + ".jpg"

## Blocking read of an already-cached image (used by the mission report,
## which must never wait on the network).
static func load_cached(url: String) -> Texture2D:
	if url.is_empty():
		return null
	var p := cache_path(url)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.load_from_file(p)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)

func fetch(url: String) -> void:
	_url = url
	var hit := load_cached(url)
	if hit != null:
		image_ready.emit(hit)
		return
	if url.is_empty():
		image_ready.emit(null)
		return
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	_req.download_file = cache_path(url)
	if _req.request(url) != OK:
		image_ready.emit(null)

func _on_done(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var tex: Texture2D = null
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		tex = load_cached(_url)
	image_ready.emit(tex)
