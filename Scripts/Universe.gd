extends Node2D

onready var game = self.get_parent().get_parent()
onready var view = self.get_parent()
onready var superclusters_id = game.universe_data[game.c_u]["superclusters"]
var superclusters_info = []
var btns = []

func _ready():
	for i in superclusters_id:
		superclusters_info.append(game.supercluster_data[i])
	for sc_i in superclusters_info:
		var supercluster_btn = TextureButton.new()
		var supercluster = Sprite.new()
		var supercluster_texture = load("res://Graphics/Clusters/" + String(sc_i["type"]) + ".png")
		supercluster_btn.texture_normal = supercluster_texture
		self.add_child(supercluster)
		supercluster.add_child(supercluster_btn)
		supercluster_btn.connect("mouse_entered", self, "on_supercluster_over", [sc_i["id"]])
		supercluster_btn.connect("mouse_exited", self, "on_supercluster_out")
		supercluster_btn.connect("pressed", self, "on_supercluster_click", [sc_i["id"]])
		supercluster_btn.rect_position = Vector2(-640 / 2, -640 / 2)
		supercluster_btn.rect_pivot_offset = Vector2(640 / 2, 640 / 2)
		var radius = pow(sc_i["cluster_num"] / game.SC_SCALE_DIV, 0.5) * view.scale_mult
		supercluster_btn.rect_scale.x = radius
		supercluster_btn.rect_scale.y = radius
		supercluster.position = sc_i["pos"]
		btns.append(supercluster_btn)

func on_supercluster_over (id:int):
	var sc_i = game.supercluster_data[id]
	game.show_tooltip(tr("SUPERCLUSTER_INFO") % [sc_i.name, sc_i.cluster_num, sc_i.dark_energy])

func on_supercluster_out ():
	game.hide_tooltip()

func on_supercluster_click (id:int):
	if not view.dragged:
		game.c_sc = id
		game.switch_view("supercluster")

var change_alpha = 0.05
func _process(_delta):
	if modulate.a < 1:
		modulate.a += change_alpha
	if modulate.a <= 0:
		game.hide_tooltip()
		for i in range(0, btns.size()):
			var radius = pow(superclusters_info[i]["cluster_num"] / game.SC_SCALE_DIV, 0.5) * view.scale_mult
			btns[i].rect_scale.x = radius
			btns[i].rect_scale.y = radius
		change_alpha *= -1
		modulate.a = change_alpha


func _on_Cluster_tree_exited():
	queue_free()
