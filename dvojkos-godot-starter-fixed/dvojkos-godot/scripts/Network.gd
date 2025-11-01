extends Node

## LAN auto-discovery + ENet host-or-join for 2 players
## - On start: listen for broadcast. If found a host, connect as client.
## - If not found in a short window, become host and start broadcasting presence.
## - Provides signals to the rest of the game. Keeps roles (p1/p2) simple.

signal role_assigned(role: String)
signal scores_updated(p1: int, p2: int)
signal game_over(winner: String)
signal game_reset()

const DISCOVERY_PORT := 35353
const GAME_PORT := 27015
const DISCOVERY_INTERVAL := 0.5 # seconds
const DISCOVERY_WINDOW := 1.5 # seconds to search before hosting

var _udp_listen := PacketPeerUDP.new()
var _udp_send := PacketPeerUDP.new()
var _discovery_timer := 0.0
var _broadcast_tick := 0.0
var _is_host := false
var _role := ""

# Simple server state (authoritative on host)
var _scores := { "p1": 0, "p2": 0 }
var _max_points := 10

func _ready() -> void:
	$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nStav: hľadám hru na sieti…"
	# Bind UDP for listening
	var err = _udp_listen.bind(DISCOVERY_PORT, "0.0.0.0")
	if err != OK:
		push_warning("UDP listen bind failed: %s" % err)
	# enable broadcast on sender
	_udp_send.set_broadcast_enabled(true)
	set_process(true)
	# start discovery window
	_discovery_timer = DISCOVERY_WINDOW

func _process(delta: float) -> void:
	# 1) Discovery: try to find a host
	if _role == "":
		_discovery_timer -= delta
		# Poll incoming discovery beacons
		while _udp_listen.get_available_packet_count() > 0:
			var pkt := _udp_listen.get_packet()
			var src_addr := ""
			if _udp_listen.has_method("get_packet_address"):
				src_addr = _udp_listen.get_packet_address()
			elif _udp_listen.has_method("get_packet_ip"):
				src_addr = _udp_listen.get_packet_ip()
			var txt := pkt.get_string_from_utf8()
			if txt.begins_with("DVOJKOS:"):
				var parts := txt.split(":")
				if parts.size() >= 2:
					var port := int(parts[1])
					_join_host(src_addr, port)
					return
		# Timed out: become host
		if _discovery_timer <= 0.0:
			_become_host()
			return

	# 2) If host, broadcast presence periodically
	if _is_host:
		_broadcast_tick += delta
		if _broadcast_tick >= DISCOVERY_INTERVAL:
			_broadcast_tick = 0.0
			var msg := "DVOJKOS:%d" % GAME_PORT
			_udp_send.put_packet_to(msg.to_utf8_buffer(), "255.255.255.255", DISCOVERY_PORT)

func _join_host(ip: String, port: int) -> void:
	$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nNachádzam hostiteľa na %s:%d …" % [ip, port]
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nNepodarilo sa pripojiť, stávam sa hostiteľom…"
		_become_host()
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connection_failed)

func _on_connected_ok() -> void:
	_role = "p2" # client is player 2 by default
	emit_signal("role_assigned", _role)
	$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nPripojený ako Hráč 2 (klient)."

func _on_connection_failed() -> void:
	$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nPripojenie zlyhalo, stávam sa hostiteľom…"
	_become_host()

func _become_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(GAME_PORT, 2)
	if err != OK:
		$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nNepodarilo sa hostovať (port obsadený?). Skús znova."
		return
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_role = "p1"
	emit_signal("role_assigned", _role)
	$"/root/Main/UI/Panel/Status".text = "[b]Dvojkos LAN Demo[/b]\nHostujem hru na porte %d — čakám na Hráča 2…" % GAME_PORT
	multiplayer.peer_connected.connect(_on_peer_connected)

func _on_peer_connected(id: int) -> void:
	if _is_host:
		_rpc_sync_scores.rpc_id(id, _scores) # send current score to new client

# --------- Simple score API (host authoritative) ----------

@rpc("any_peer", "call_local")
func req_score_point(role: String) -> void:
	# Only accept from the client when host; from ourselves when we are host.
	if not _is_host:
		return
	if not ["p1", "p2"].has(role):
		return
	_scores[role] += 1
	_rpc_sync_scores.rpc(_scores)
	if _scores[role] >= _max_points:
		_rpc_game_over.rpc(role)

@rpc("authority", "call_local")
func _rpc_sync_scores(new_scores: Dictionary) -> void:
	_scores = new_scores
	emit_signal("scores_updated", _scores["p1"], _scores["p2"])

@rpc("authority", "call_local")
func _rpc_game_over(winner: String) -> void:
	emit_signal("game_over", winner)

func request_score_point(role: String) -> void:
	# Client asks host to add a point; host can call directly.
	if _is_host:
		req_score_point(role)
	else:
		req_score_point.rpc(role)

func reset_game() -> void:
	if _is_host:
		_scores = { "p1": 0, "p2": 0 }
		_rpc_sync_scores.rpc(_scores)
		emit_signal("game_reset")