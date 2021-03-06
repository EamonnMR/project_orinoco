extends Control

# TODO: add a signal to the lobby player
# That gets transmitted when they edit
# an attribute. Connect it to a sync or
# remote function on the gamestate which
# checks to make sure it's from the right
# peer ID, and if so, updates the players
# list and (either way) updates the on-screen
# list.

const GAME_TYPE = "orbital_fortress"
# const TRACKER = "http://127.0.0.1:8000"  
const TRACKER = "http://tracker.eamonnmr.com"

func _ready():
	# Called every time the node is added to the scene.
	gamestate.connect("connection_failed", self, "_on_connection_failed")
	gamestate.connect("connection_succeeded", self, "_on_connection_success")
	gamestate.connect("player_list_changed", self, "refresh_lobby")
	gamestate.connect("game_ended", self, "_on_game_ended")
	gamestate.connect("game_error", self, "_on_game_error")
	# Set the player name according to the system username. Fallback to the path.
	if OS.has_environment("USERNAME"):
		$Connect/Name.text = OS.get_environment("USERNAME")
	else:
		var desktop_path = OS.get_system_dir(0).replace("\\", "/").split("/")
		$Connect/Name.text = desktop_path[desktop_path.size() - 2]

func _on_host_pressed():
	
	register_game()
	
	if $Connect/Name.text == "":
		$Connect/ErrorLabel.text = "Invalid name!"
		return

	$Connect.hide()
	$Players.show()
	$Connect/ErrorLabel.text = ""

	var player_name = $Connect/Name.text
	gamestate.host_game(player_name)
	refresh_lobby()


func _on_join_pressed():
	if $Connect/Name.text == "":
		$Connect/ErrorLabel.text = "Invalid name!"
		return

	var ip = $Connect/IPAddress.text
	if not ip.is_valid_ip_address():
		$Connect/ErrorLabel.text = "Invalid IP address!"
		return

	$Connect/ErrorLabel.text = ""
	$Connect/Host.disabled = true
	$Connect/Join.disabled = true

	var player_name = $Connect/Name.text
	gamestate.join_game(ip, player_name)


func _on_connection_success():
	print("Connection success")
	$Game_Browser.hide()
	$Connect.hide()
	$Players.show()


func _on_connection_failed():
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false
	$Connect/ErrorLabel.set_text("Connection failed.")


func _on_game_ended():
	show()
	$Connect.show()
	$Players.hide()
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false


func _on_game_error(errtxt):
	$ErrorDialog.dialog_text = errtxt
	$ErrorDialog.popup_centered_minsize()
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false


func refresh_lobby():
	# print("Refresh lobby")
	var players = gamestate.players
	_clear_list()
	# print(players)
	for p in players.values():
		_add_lobby_player(p)

	$Players/Start.disabled = not get_tree().is_network_server()


func _on_start_pressed():
	deregister_game()
	gamestate.begin_game()
	
func _on_add_bot_pressed():
	pass
	# TODO: gamestate.add_bot()
	
func _on_kick_player(player_id):
	print("TODO: Remove player: " + player_id)
	# TODO: gamestate.remove_player(id)

func _on_update_player_config_in_lobby(player_id, attr, value):
	print("_on_update_player_config_in_lobby")
	gamestate.modify_player_attribute(player_id, attr, value)
	
func _clear_list():
	for list in [$Players/List_t0, $Players/List_t1]:
		for n in list.get_children():
			list.remove_child(n)
			n.queue_free()

func _add_lobby_player(player):
	var lobby_player = preload("res://LobbyPlayer.tscn").instance()
	if(player["team"]) == 0:
		$Players/List_t0.add_child(lobby_player)
	if(player["team"]) == 1:
		$Players/List_t1.add_child(lobby_player)
	lobby_player.set_attributes(player, false)
	lobby_player.connect("list_item_changed", self, "_on_update_player_config_in_lobby")
	lobby_player.connect("remove_player", self, "_on_kick_player")

func register_game():
	var game_name = $Connect/Name.text + "'s game"
	if $Connect/GameName.text:
		game_name = $Connect/GameName.text
	var query = JSON.print({
		"port": gamestate.DEFAULT_PORT,
		"name": game_name,
		"type": gamestate.GAMETYPE
	})
	
	var headers = ["Content-Type: application/json"]
	$HTTPRequest.request(TRACKER + "/game", headers, false, HTTPClient.METHOD_PUT, query)
	

func deregister_game():
	# $HTTPRequest.request("localhost:8000/game", [], false, HTTPClient.DELETE, null)
	pass


func _on_HTTPRequest_request_completed(result, response_code, headers, body):
	var browser_game = preload("res://BrowserGame.tscn")
	print(body.get_string_from_utf8())
	var games = JSON.parse(body.get_string_from_utf8())
	print(games)
	for game in games.result:
		var game_widget = browser_game.instance()
		print(game)
		game_widget.apply_game(game)
		game_widget.connect("join_game", self, "_on_browser_Start_pressed")
		$Game_Browser/game_list.add_child(game_widget)
		


func _on_Find_Online_pressed():
	$HTTPRequest_get_games.request(TRACKER + "/games?type=orbital_fortress", [], false, HTTPClient.METHOD_GET, "")
	$Connect.hide()
	$Game_Browser.show()
	$Connect/ErrorLabel.text = ""


func _on_browser_Start_pressed(game):
	print("Browser Start")
	var player_name = $Connect/Name.text
	gamestate.join_game(game["address"], player_name)

func _on_browser_Return_pressed():
		$Game_Browser.hide()
		$Connect.show()
