extends Control

onready var game = get_node("/root/Game")
onready var p_i = game.planet_data[game.c_p]
onready var id:int = game.c_t
onready var tile = game.tile_data[id]
onready var au_int:float = tile.au_int if tile and tile.has("au_int") else 0
onready var tile_texture = load("res://Graphics/Tiles/" + String(p_i["type"]) + ".jpg")
var progress = 0#Mining tile progress
var total_mass = 0
var contents:Dictionary
var tween:Tween
var layer:String
onready var met_info = game.met_info
var metal_sprites = []
var circ_vel:Vector2 = Vector2.ONE
var points:float#Points for minigame
onready var circ = $CanvasLayer/Circle
onready var spd_mult_node = $SpdMult
var circ_disabled = false#Useful if pickaxe breaks and auto buy isn't on
var mouse_pos:Vector2
var speed_mult:float = 1.0

func _ready():
	$Pickaxe/Sprite.texture = load("res://Graphics/Pickaxes/" + game.pickaxe.name + ".png")
	if p_i.temperature > 1000:
		$Tile/TextureRect.texture = load("res://Resources/Lava.tres")
	else:
		$Tile/TextureRect.texture = tile_texture
	if not tile:
		tile = {}
	if not tile.has("mining_progress"):
		tile.mining_progress = 0.0
	if not tile.has("depth"):
		tile.depth = 0
	progress = tile.mining_progress
	update_info()
	generate_rock(false)
	$Help.visible = game.help.mining
	circ.visible = not game.help.mining
	$Help/Label.text = tr("MINE_HELP")
	$LayerInfo.visible = game.show.mining_layer
	if $LayerInfo.visible:
		$LayerAnim.play("Layer fade")
		$LayerAnim.seek(1, true)
	$AutoReplace.pressed = game.auto_replace

func update_info():
	var upper_depth
	var lower_depth 
	if tile.has("init_depth"):
		layer = "crater"
		upper_depth = tile.init_depth
		lower_depth = 3 * tile.init_depth
		$LayerInfo/Upper.text = String(upper_depth) + " m"
		$LayerInfo/Lower.text = String(lower_depth) + " m"
	elif tile.depth <= p_i.crust_start_depth:
		layer = "surface"
		upper_depth = 0
		lower_depth = p_i.crust_start_depth
		$LayerInfo/Upper.text = String(upper_depth) + " m"
		$LayerInfo/Lower.text = String(lower_depth) + " m"
	elif tile.depth <= p_i.mantle_start_depth:
		layer = "crust"
		upper_depth = p_i.crust_start_depth + 1
		lower_depth = p_i.mantle_start_depth
		$LayerInfo/Upper.text = String(upper_depth) + " m"
		$LayerInfo/Lower.text = String(lower_depth) + " m"
	elif tile.depth <= p_i.core_start_depth:
		layer = "mantle"
		upper_depth = floor(p_i.mantle_start_depth / 1000.0)
		lower_depth = floor(p_i.core_start_depth / 1000.0)
		$LayerInfo/Upper.text = String(upper_depth) + " km"
		$LayerInfo/Lower.text = String(lower_depth) + " km"
	else:
		layer = "core"
		upper_depth = floor(p_i.core_start_depth / 1000.0)
		lower_depth = floor(p_i.size / 2.0)
		$LayerInfo/Upper.text = String(upper_depth) + " km"
		$LayerInfo/Lower.text = String(lower_depth) + " km"
	$LayerInfo/Layer.text = tr("LAYER") + ": " + tr(layer.to_upper())
	$LayerInfo/Depth.position.y = range_lerp(tile.depth, upper_depth, lower_depth, 172, 628)
	$LayerInfo/Depth/Label.text = String(tile.depth) + " m"
	$Tile/SquareBar.set_progress(progress)
	$Tile/Cracks.frame = min(floor(progress / 20), 4)
	$Durability/Numbers.text = "%s / %s" % [game.pickaxe.durability, game.pickaxe_info[game.pickaxe.name].durability]	
	$Durability/Bar.value = game.pickaxe.durability / float(game.pickaxe_info[game.pickaxe.name].durability) * 100

func generate_rock(new:bool):
	var tile_sprite = $Tile
	var vbox = $Panel/VBoxContainer
	contents = {}
	if tween:
		remove_child(tween)
	tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(tile_sprite, "rect_scale", Vector2(0.3, 0.3), Vector2(1, 1), 0.4, Tween.TRANS_CIRC, Tween.EASE_OUT)
	tween.start()
	for met_sprite in metal_sprites:
		tile_sprite.remove_child(met_sprite)
	metal_sprites = []
	if not tile.has("contents") or new:
		total_mass = 0
		var other_volume = 0#in m^3
		#We assume all materials have a density of 1.5g/cm^3 to simplify things
		var rho = 1.5
		for mat in p_i.surface.keys():
			#Material quantity penalty the further you go from surface
			var depth_limit_mult = max(1, 1 + (tile.depth / 2.0 - p_i.crust_start_depth) / float(p_i.crust_start_depth))
			if randf() < p_i.surface[mat].chance / depth_limit_mult:
				var amount = game.clever_round(p_i.surface[mat].amount * rand_range(0.8, 1.2) / depth_limit_mult, 3)
				if amount < 1:
					continue
				contents[mat] = amount
				other_volume += amount / rho / 1000
		if layer != "surface":
			if not tile.has("current_deposit"):
				for met in met_info:
					var crater_metal = tile.has("init_depth") and met == tile.crater_metal
					if met_info[met].min_depth < tile.depth - p_i.crust_start_depth and tile.depth - p_i.crust_start_depth < met_info[met].max_depth or crater_metal:
						if randf() < 0.25 / met_info[met].rarity * (6 if crater_metal else 1) * pow(1 + au_int, 0.5):
							tile.current_deposit = {"met":met, "size":Helper.rand_int(4, 10), "progress":1}
			if tile.has("current_deposit"):
				var met = tile.current_deposit.met
				var size = tile.current_deposit.size
				var progress2 = tile.current_deposit.progress
				var amount_multiplier = -abs(2.0/size * progress2 - 1) + 1
				var amount = game.clever_round(met_info[met].amount * rand_range(0.4, 0.45) * amount_multiplier * pow(1 + au_int, 0.5), 3)
				for i in clamp(round(amount / 2.0), 1, 40):
					var met_sprite = Sprite.new()
					met_sprite.texture = load("res://Graphics/Metals/" + met + ".png")
					met_sprite.centered = true
					met_sprite.scale *= rand_range(0.15, 0.2)
					var half_size_in_px = met_sprite.scale.x * 128
					met_sprite.rotation = rand_range(0, 2 * PI)
					met_sprite.position.x = rand_range(half_size_in_px + 5, 195 - half_size_in_px)
					met_sprite.position.y = rand_range(half_size_in_px + 5, 195 - half_size_in_px)
					metal_sprites.append(met_sprite)
					tile_sprite.add_child(met_sprite)
				contents[met] = amount
				other_volume += amount / game.met_info[met].density / 1000
				tile.current_deposit.progress += 1
			#   									                          	    V Every km, rock density goes up by 0.01
		var stone_amount = game.clever_round((1 - other_volume) * 1000 * (2.85 + tile.depth / 100000.0), 3)
		contents.stone = stone_amount
		tile.contents = contents
	else:
		contents = tile.contents
	Helper.put_rsrc(vbox, 42, contents)
	for mass in contents.values():
		total_mass += mass
	$Panel.visible = false
	$Panel.visible = true#A weird workaround to make sure Panel has the right rekt_size

func _input(event):
	if event is InputEventMouse:
		mouse_pos = event.position
		$Pickaxe.position = mouse_pos - Vector2(512, 576)
	Helper.set_back_btn($Back)

func _on_Back_pressed():
	tile.mining_progress = progress
	game.tile_data[id] = tile
	Helper.save_tiles(game.c_p)
	game.switch_view("planet")
	queue_free()

var crumbles = []

func place_crumbles(num:int, sc:float, v:float):
	for i in num:
		var crumble = Sprite.new()
		if p_i.temperature > 1000:
			crumble.texture = load("res://Resources/Lava.tres")
		else:
			crumble.texture = tile_texture
		crumble.scale *= sc
		crumble.centered = true
		add_child(crumble)
		crumble.position = mouse_pos
		crumbles.append({"sprite":crumble, "velocity":Vector2(rand_range(-2, 2), rand_range(-8, -4)) * v, "angular_velocity":rand_range(-0.08, 0.08)})

func hide_help():
	$Help.visible = false
	game.help.mining = false
	var tween:Tween = Tween.new()
	circ.modulate.a = 0
	circ.visible = true
	tween.interpolate_property(circ, "modulate", null, Color(1, 1, 1, 0.5), 2)
	add_child(tween)
	tween.start()
	yield(tween, "tween_all_completed")
	remove_child(tween)

var help_counter = 0
func pickaxe_hit():
	if not game.pickaxe:
		return
	if tile.has("current_deposit"):
		var amount_multiplier = -abs(2.0/tile.current_deposit.size * (tile.current_deposit.progress - 1) - 1) + 1
		$HitMetalSound.pitch_scale = rand_range(0.8, 1.2)
		$HitMetalSound.volume_db = -3 - (1 - amount_multiplier) * 10
		$HitRockSound.volume_db = -10 - (amount_multiplier) * 10
		$HitMetalSound.play()
		$HitRockSound.play()
	else:
		$HitRockSound.volume_db = -10
		$HitRockSound.pitch_scale = rand_range(0.8, 1.2)
		$HitRockSound.play()
	if $Help.visible:
		help_counter += 1
		if help_counter >= 10:
			$HelpAnim.play("Help fade")
	place_crumbles(5, 0.1, 1)
	progress += game.pickaxe.speed / total_mass * 3000 * speed_mult
	game.pickaxe.durability -= 1
	tile.mining_progress = progress
	if progress >= 100:
		$MiningSound.pitch_scale = rand_range(0.8, 1.2)
		$MiningSound.play()
		for content in contents:
			var amount = contents[content]
			if game.mats.has(content):
				game.mats[content] += amount
				if not game.show.plant_button and content == "soil":
					game.show.plant_button = true
				if not game.show.materials:
					game.long_popup(tr("YOU_MINED_MATERIALS"), tr("MATERIALS"))
					game.inventory.get_node("Tabs/Materials").visible = true
					game.show.materials = true
			elif game.mets.has(content):
				if not game.show.metals:
					game.long_popup(tr("YOU_MINED_METALS"), tr("METALS"))
					game.inventory.get_node("Tabs/Metals").visible = true
					game.show.metals = true
				game.mets[content] += amount
			elif content == "stone":
				var layer2 = "crust" if layer == "surface" or layer == "crater" else layer
				for comp in p_i[layer2]:
					if game.stone.has(comp):
						game.stone[comp] += p_i[layer2][comp] * amount
					else:
						game.stone[comp] = p_i[layer2][comp] * amount
			else:
				game[content] += amount
			if game.show.has(content):
				game.show[content] = true
		progress -= 100
		if tile.has("current_deposit") and tile.current_deposit.progress > tile.current_deposit.size - 1:
			tile.erase("current_deposit")
		tile.depth += 1
		if tile.has("init_depth") and tile.depth > 3 * tile.init_depth:
			tile.erase("init_depth")
		game.show.stone = true
		if not $LayerInfo.visible and tile.depth >= 5:
			game.show.mining_layer = true
			$LayerAnim.play("Layer fade")
			$LayerInfo.visible = true
		place_crumbles(15, 0.2, 2)
		generate_rock(true)
		game.HUD.refresh()
	update_info()
	if game.pickaxe.durability == 0:
		var curr_pick_info = game.pickaxe_info[game.pickaxe.name]
		var costs = curr_pick_info.costs
		if $AutoReplace.pressed and game.check_enough(costs):
			game.deduct_resources(costs)
			game.pickaxe.durability = curr_pick_info.durability
			update_info()
		else:
			game.pickaxe.clear()
			circ_disabled = true
			game.popup(tr("PICKAXE_BROKE"), 1.5)
			$Pickaxe.visible = false

func _process(_delta):
	for cr in crumbles:
		cr.sprite.position += cr.velocity
		cr.velocity.y += 0.6
		cr.sprite.rotation += cr.angular_velocity
		if cr.sprite.position.y > 1000:
			remove_child(cr.sprite)
			crumbles.erase(cr)
	if circ.visible and not circ_disabled:
		circ.position += circ_vel * max(1, pow(points / 60.0, 0.28))
		if circ.position.x < 284:
			circ_vel.x = -sign(circ_vel.x) * rand_range(0.95, 1.1)
			circ.position.x = 284
		if circ.position.x > 484 - 100 * circ.scale.x:
			circ_vel.x = -sign(circ_vel.x) * rand_range(0.95, 1.1)
			circ.position.x = 484 - 100 * circ.scale.x
		if circ.position.y < 284:
			circ_vel.y = -sign(circ_vel.y) * rand_range(0.95, 1.1)
			circ.position.y = 284
		if circ.position.y > 484 - 100 * circ.scale.x:
			circ_vel.y = -sign(circ_vel.y) * rand_range(0.95, 1.1)
			circ.position.y = 484 - 100 * circ.scale.x
		if spd_mult_node.visible:
			speed_mult = game.clever_round(points / 3000.0 + 1) * ((game.MUs.MSMB - 1) * 0.05 + 1)
			spd_mult_node.text = tr("SPEED_MULTIPLIER") + ": x %s" % [speed_mult]
		spd_mult_node.visible = bool(points)
		if Input.is_action_pressed("left_click") and Geometry.is_point_in_circle(mouse_pos, circ.position + 50 * circ.scale, 50 * circ.scale.x):
			points += 1
			spd_mult_node["custom_colors/font_color"] = Color(0, 1, 0, 1)
		else:
			if points > 0:
				points = max(points - 3, 0)
				spd_mult_node["custom_colors/font_color"] = Color(1, 0, 0, 1)

func _on_Button_button_down():
	if not game.pickaxe.empty():
		circ_disabled = false
		$PickaxeAnim.get_animation("Pickaxe swing").loop = true
		$PickaxeAnim.play("Pickaxe swing")

func _on_Button_button_up():
	circ_disabled = true
	$PickaxeAnim.get_animation("Pickaxe swing").loop = false

func _on_CheckBox_mouse_entered():
	game.show_tooltip(tr("AUTO_REPLACE_DESC"))

func _on_CheckBox_mouse_exited():
	game.hide_tooltip()

func _on_Layer_mouse_entered():
	game.show_tooltip(tr(layer.to_upper() + "_DESC"))

func _on_Layer_mouse_exited():
	game.hide_tooltip()

func _on_AutoReplace_pressed():
	game.auto_replace = $AutoReplace.pressed
