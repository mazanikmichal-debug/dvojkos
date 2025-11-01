extends Node2D

## Minimal demo gameplay to prove networking:
## - Press [A] to score for Player 1 (host).
## - Press [L] to score for Player 2 (client).
## - Shows two paddles you can move with mouse (host) or arrow keys (client).
## Replace with your real game later; keep the Network.gd API.

@onready var network = $"../Network"
@onready var status = $"/root/Main/UI/Panel/Status"

var my_role := ""

var p1_x := 120.0
var p2_x := 1160.0
var p_speed := 420.0

func _ready() -> void:
	network.role_assigned.connect(func(role): my_role = role)
	network.scores_updated.connect(_on_scores)
	network.game_over.connect(_on_game_over)
	network.game_reset.connect(func(): queue_redraw())

func _process(delta: float) -> void:
	# Simple local control for paddles so we see something moving
	if my_role == "p1":
		# host moves left paddle with mouse Y
		p1_x = 120.0
	else:
		p2_x = 1160.0
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_A:
			network.request_score_point("p1")
		if event.keycode == KEY_L:
			network.request_score_point("p2")
		if event.keycode == KEY_R:
			network.reset_game()

func _on_scores(p1: int, p2: int) -> void:
	status.text = "[b]Dvojkos LAN Demo[/b]\nSkóre — Hráč 1: %d | Hráč 2: %d\n(R = reset, A = bod pre P1, L = bod pre P2)" % [p1, p2]

func _on_game_over(winner: String) -> void:
	status.text = "[b]Dvojkos LAN Demo[/b]\nVíťaz: %s\n(R = reset)" % (winner == "p1" ? "Hráč 1" : "Hráč 2")

func _draw() -> void:
	# Background
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color(0.06,0.09,0.16))
	# Center line
	var h := get_viewport_rect().size.y
	for y in range(0, int(h), 20):
		draw_rect(Rect2(Vector2(640-2, y), Vector2(4,10)), Color(0.2,0.25,0.35))
	# Paddles (just for movement demo)
	draw_rect(Rect2(Vector2(p1_x-8, h*0.5-60), Vector2(16,120)), Color(0.2,0.8,0.9))
	draw_rect(Rect2(Vector2(p2_x-8, h*0.5-60), Vector2(16,120)), Color(0.7,0.6,1.0))