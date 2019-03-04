local callbacks = {}
local json = require("lib/json")

function create(app, player_id)
  return lua_fsm.create({
    initial = "idle",
    events = {
      { name = "startup",              from = "none",                   to = "idle" },
      { name = "connection_succeeded", from = "idle",                   to = "idle" },
      { name = "new_player_joined",    from = "*",                      to = "*" },
      { name = "player_left",          from = "*",                      to = "*" },
      { name = "new_lobby_opened",     from = "*",                      to = "*" },
      { name = "lobby_closed",         from = "*",                      to = "*" },
      { name = "add_lobby",            from = "idle",                   to = "idle" },
      { name = "join_lobby",           from = "idle",                   to = "waiting_for_game_start" },
      { name = "game_started",         from = "waiting_for_game_start", to = "transition_to_game_screen" },
      { name = "game_started",         from = "idle",                   to = "transition_to_game_screen" },
      { name = "refresh",              from = "*",                      to = "*" },
      { name = "refreshed",            from = "*",                      to = "*" }
    },
    callbacks = {
      on_startup = function(self, event, from, to)
        self.data = {
          app       = app,
          player_id = player_id,
          ui = {
            hover = {},
            online_players_box = { x = 455, y = 5, width = 340, height = 590, children = {} },
            open_lobbies_box   = { x = 5, y = 5, width = 440, height = 590, children = {} },
            add_lobby_button   = { x = 310, y = 10, width = 130, height = 25 }
          },
          online_players = {},
          open_lobbies   = {}
        }
      end,


      on_refresh = function(self, event, from, to)
        self.current = from
        send({ type = "what_is_online" })
      end,


      on_connection_succeeded = function(self, event, from, to, online_players, open_lobbies, running_game)
        self.data.online_players = online_players
        self.data.open_lobbies   = open_lobbies

        if running_game then
          self.data.app.display_game_screen(running_game, self.data.player_id)
        end

        update_online_players_box(self)
        update_open_lobbies_box(self)
      end,


      on_refreshed = function(self, event, from, to, online_players, open_lobbies)
        self.current             = from
        self.data.online_players = online_players
        self.data.open_lobbies   = open_lobbies

        update_online_players_box(self)
        update_open_lobbies_box(self)
      end,


      on_leave_idle = function(self)
        self.data.ui.hover = {}
      end,


      on_new_player_joined = function(self, event, from, to, player_id)
        self.data.online_players[player_id] = { id = player_id }
        self.current = from
        update_online_players_box(self)
      end,


      on_player_left = function(self, event, from, to, player_id)
        self.data.online_players[player_id] = nil
        self.current = from
        update_online_players_box(self)
      end,


      on_new_lobby_opened = function(self, event, from, to, lobby_id, player_id)
        self.data.open_lobbies[lobby_id] = { id = lobby_id, player_1 = player_id }
        self.current = from
        update_open_lobbies_box(self)
      end,


      on_lobby_closed = function(self, event, from, to, lobby_id)
        self.data.open_lobbies[lobby_id] = nil
        self.current = from
        update_open_lobbies_box(self)
      end,


      on_add_lobby = function(self, event, from, to)
        send({ type = "player_opens_lobby" })
      end,


      on_join_lobby = function(self, event, from, to, lobby_id)
        send({ type = "player_joins_lobby", lobby_id = lobby_id })
      end,


      on_game_started = function(self, event, from, to, game)
        self.data.app.display_game_screen(game, self.data.player_id)
      end,
    }
  })
end


function callbacks.update(fsm, delta)
end


function update_online_players_box(fsm)
  local box = fsm.data.ui.online_players_box
  local y   = box.y + 35

  box.children = {}

  for _, player in pairs(fsm.data.online_players) do
    fsm.data.ui.online_players_box.children[player.id] = { x = box.x + 5, y = y, width = box.width - 10, height = 25 }
    y = y + 30
  end
end


function update_open_lobbies_box(fsm)
  local box = fsm.data.ui.open_lobbies_box
  local y   = box.y + 35

  box.children = {}

  for _, lobby in pairs(fsm.data.open_lobbies) do
    box.children[lobby.id] = { x = box.x + 5, y = y, width = box.width - 10, height = 25 }
    y = y + 30
  end
end


function callbacks.draw(fsm)
  draw_online_players_box(fsm)
  draw_open_lobbies_box(fsm)
  set_cursor(fsm)
end


function draw_online_players_box(fsm)
  box = fsm.data.ui.online_players_box

  lg.setColor(1, 1, 1)
  lg.rectangle("line", box.x, box.y, box.width, box.height)
  lg.print(online_player_box_title(utils.count(fsm.data.online_players)), box.x + 5, box.y + 5)

  for player_id, player_box in pairs(box.children) do
    local hover  = fsm.data.ui.hover.online_player_box == player_id
    local me     = fsm.data.player_id == player_id
    local suffix = me and " (vous)" or ""

    lg.setColor(hover and { 0.6, 0.6, 0.6 } or { 0, 0, 0 })
    lg.rectangle("fill", player_box.x, player_box.y, player_box.width, player_box.height)

    lg.setColor(me and self_color or { 1, 1, 1 })
    lg.rectangle("line", player_box.x, player_box.y, player_box.width, player_box.height)
    lg.print(player_id .. suffix, player_box.x + 5, player_box.y + 5)
  end
end


function draw_open_lobbies_box(fsm)
  local box = fsm.data.ui.open_lobbies_box

  lg.setColor(1, 1, 1)
  lg.rectangle("line", box.x, box.y, box.width, box.height)
  lg.print(open_lobbies_box_title(utils.count(fsm.data.open_lobbies)), box.x + 5, box.y + 5)

  for lobby_id, lobby_box in pairs(box.children) do
    local lobby  = fsm.data.open_lobbies[lobby_id]
    local owner  = lobby.player_1 == fsm.data.player_id
    local hover  = not owner and fsm.data.ui.hover.open_lobby_box == lobby_id
    local title  = "Duel contre " .. lobby.player_1
    local suffix = owner and " (non, vous ne pouvez pas !)" or ""

    lg.setColor(hover and { 0.6, 0.6, 0.6 } or { 0, 0, 0 })
    lg.rectangle("fill", lobby_box.x, lobby_box.y, lobby_box.width, lobby_box.height)

    lg.setColor(owner and self_color or { 1, 1, 1 })
    lg.rectangle("line", lobby_box.x, lobby_box.y, lobby_box.width, lobby_box.height)
    lg.print(title .. suffix, lobby_box.x + 5, lobby_box.y + 5)
  end

  draw_add_lobby_button(fsm)
end



function draw_add_lobby_button(fsm)
  local button = fsm.data.ui.add_lobby_button
  local hover  = fsm.data.ui.hover.add_lobby_button

  lg.setColor(hover and { 0.6, 0.6, 0.6 } or { 0, 0, 0 })
  lg.rectangle("fill", button.x, button.y, button.width, button.height)

  lg.setColor(1, 1, 1)
  lg.rectangle("line", button.x, button.y, button.width, button.height)
  lg.print("Ajouter une partie !", button.x + 5, button.y + 5)
end


function online_player_box_title(online_players_count)
  if online_players_count == 0 then
    return "Aucun joueur connecté"
  elseif online_players_count == 1 then
    return "1 joueur connecté"
  else
    return online_players_count .. " joueurs connectés"
  end
end


function open_lobbies_box_title(open_lobbies_count)
  if open_lobbies_count == 0 then
    return "Aucune partie disponible"
  elseif open_lobbies_count == 1 then
    return "1 partie disponible"
  else
    return open_lobbies_count .. " parties disponibles"
  end
end


function callbacks.event_received(fsm, event)
  -- print("event received", event.type, json.encode(event))

  if event.type == "connection_succeeded" then
    fsm.connection_succeeded(event.online_players, event.open_lobbies, event.running_game)

  elseif event.type == "player_joined_server" then
    fsm.new_player_joined(event.player_id)

  elseif event.type == "player_left_server" then
    fsm.player_left(event.player_id)

  elseif event.type == "lobby_opened" then
    fsm.new_lobby_opened(event.lobby_id, event.player_1)

  elseif event.type == "lobby_closed" then
    fsm.lobby_closed(event.lobby_id)

  elseif event.type == "game_started" then
    fsm.game_started(event.game)

  elseif event.type == "this_is_online" then
    fsm.refreshed(event.online_players, event.open_lobbies)
  end
end


function callbacks.mousemoved(fsm, x, y)
  fsm.data.ui.hover.online_player_box = nil
  fsm.data.ui.hover.open_lobby_box = nil
  fsm.data.ui.hover.add_lobby_button = false

  if fsm.current == "idle" and utils.is_within_box(x, y, fsm.data.ui.online_players_box) then

    for player_id, player_box in pairs(fsm.data.ui.online_players_box.children) do
      if utils.is_within_box(x, y, player_box) then
        -- Invitations are not yet available.
        -- fsm.data.ui.hover.online_player_box = player_id
        break
      end
    end

  elseif fsm.current == "idle" and utils.is_within_box(x, y, fsm.data.ui.open_lobbies_box) then
    fsm.data.ui.hover.open_lobby_box = nil

    if utils.is_within_box(x, y, fsm.data.ui.add_lobby_button) then
      fsm.data.ui.hover.add_lobby_button = true

    else
      for lobby_id, lobby_box in pairs(fsm.data.ui.open_lobbies_box.children) do
        local lobby = fsm.data.open_lobbies[lobby_id]
        if utils.is_within_box(x, y, lobby_box) and lobby.player_1 ~= fsm.data.player_id then
          fsm.data.ui.hover.open_lobby_box = lobby_id
          break
        end
      end
    end
  end
end


function set_cursor(fsm)
  love.mouse.setCursor(arrow_cursor)
  for id, hover in pairs(fsm.data.ui.hover) do
    if hover then
      love.mouse.setCursor(hand_cursor)
      break
    end
  end
end


function callbacks.mousepressed(fsm, x, y, button)
  handle_click_on_online_player(fsm, x, y, button)
  handle_click_on_add_lobby_button(fsm, x, y, button)
  handle_click_on_open_lobby(fsm, x, y, button)
end


function handle_click_on_online_player(fsm, x, y, button)
  local clicked_player_id = nil

  if utils.is_within_box(x, y, fsm.data.ui.online_players_box) then
    for player_id, player_box in pairs(fsm.data.ui.online_players_box.children) do
      clicked_player_id = utils.is_within_box(x, y, player_box) and player_id or nil
    end
  end

  if clicked_player_id and fsm.data.player_id ~= clicked_player_id then
    -- fsm.send_invitation(clicked_player_id)
  end
end


function handle_click_on_add_lobby_button(fsm, x, y, button)
  if utils.is_within_box(x, y, fsm.data.ui.add_lobby_button) then
    fsm.add_lobby()
  end
end


function handle_click_on_open_lobby(fsm, x, y, button)
  local clicked_lobby_id = nil

  if utils.is_within_box(x, y, fsm.data.ui.open_lobbies_box) then
    for lobby_id, lobby_box in pairs(fsm.data.ui.open_lobbies_box.children) do
      if utils.is_within_box(x, y, lobby_box) then
        clicked_lobby_id = lobby_id
        break
      end
    end
  end

  if clicked_lobby_id and fsm.data.player_id ~= fsm.data.open_lobbies[clicked_lobby_id].player_1 then
    fsm.join_lobby(clicked_lobby_id)
  end
end

function callbacks.keypressed(fsm, key)
  if key == "escape" then
    love.event.quit()

  elseif key == "space" then
    fsm.add_lobby()

  elseif key == "backspace" then
    fsm.data.app.display_main_menu(fsm.data.player_id)
  end
end


return { create = create, callbacks = callbacks }
