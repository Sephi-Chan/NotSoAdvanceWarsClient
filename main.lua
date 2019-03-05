io.stdout:setvbuf('no')
if arg[#arg] == "-debug" then require("mobdebug").start() end

scale        = 2
lg           = love.graphics
font         = lg.newFont(12); lg.setFont(font)
arrow_cursor = love.mouse.getSystemCursor("arrow")
hand_cursor  = love.mouse.getSystemCursor("hand")
env          = "prod"
server_ip    = env == "dev" and "192.168.1.12" or "163.172.97.119"

socket     = require("socket")
json       = require("lib/json")
lua_fsm    = require("lib/fsm")
unit_types = require("data/unit_types")
animations = require("data/animations")
sound_box  = require("lib/sound_box")
utils      = require("lib/utils")

sound_box.register_sound("submachine_gun", "assets/mp5.wav")
sound_box.register_sound("cannon",         "assets/cannon.wav")
sound_box.register_sound("horn",           "assets/horn.wav")

main_menu       = require("main_menu")
game_screen     = require("game_screen")
fight_cinematic = require("fight_cinematic")

self_color  = { 51/255, 102/255, 255/255 }
error_color = { 1, 0, 0 }

love.filesystem.setIdentity("NotSoAdvanceWars")
love.window.setTitle("Not so Advance Wars")

math.randomseed(os.time())
math.random(); math.random(); math.random()

local network = {
  client    = socket.tcp(),
  connected = false
}

local app = lua_fsm.create({
  events = {
    { name = "startup",              from = "none",             to = "main_menu" },
    { name = "display_main_menu",    from = "game_screen",      to = "main_menu" },
    { name = "display_main_menu",    from = "main_menu",        to = "main_menu" },
    { name = "display_game_screen",  from = "main_menu",        to = "game_screen" },
    { name = "display_game_screen",  from = "cinematic_screen", to = "game_screen" },
    { name = "play_fight_cinematic", from = "game_screen",      to = "cinematic_screen"}
  },
  callbacks = {
    on_startup = function(self, event, from, to, player_id)
      self.data = {
        player_id = player_id,
        fsm       = main_menu.create(self, player_id),
        callbacks = main_menu.callbacks
      }
    end,


    on_display_game_screen = function(self, event, from, to, game, player_id)
      local fsm = game_screen.create()
      fsm.startup(self, game, player_id)

      self.data.fsm       = fsm
      self.data.callbacks = game_screen.callbacks
    end,


    on_play_fight_cinematic = function(self, event, from, to, game, attacking_unit, target_unit, result)
      local previous_fsm       = self.data.fsm
      local previous_callbacks = self.data.callbacks

      local callback = function()
        self.current = "game_screen"
        self.data.fsm       = previous_fsm
        self.data.callbacks = previous_callbacks
      end

      self.data.fsm       = fight_cinematic.create(attacking_unit, target_unit, result, callback)
      self.data.callbacks = fight_cinematic.callbacks
    end,


    on_display_main_menu = function(self, event, from, to, player_id)
      local fsm = main_menu.create(self, player_id)
      fsm.refresh()

      self.data.fsm       = fsm
      self.data.callbacks = main_menu.callbacks
    end
  }
})


function love.load()
  app.startup(get_player_id())
end


function love.update(delta)
  app.data.callbacks.update(app.data.fsm, delta)
  connect_or_poll_server(network, app.data.player_id, delta, app.data.callbacks.event_received)
end


function love.draw()
  lg.setLineWidth(1)
  lg.setLineStyle("rough")

  app.data.callbacks.draw(app.data.fsm)
end


function love.keypressed(key)
  app.data.callbacks.keypressed(app.data.fsm, key)
end


function love.mousepressed(x, y, button)
  app.data.callbacks.mousepressed(app.data.fsm, x, y, button)
end


function love.mousemoved(x, y, dx, dy)
  app.data.callbacks.mousemoved(app.data.fsm, x, y)
end


function send(table)
  network.client:send(json.encode(table) .."\n")
end


function connect_or_poll_server(network, player_id, delta, event_received_callback)
  if network.connected == false then
    network.client:settimeout(0)
    local result, connection_error = network.client:connect(server_ip, 4040)

    if connection_error == "already connected" then
      network.connected = true
      send({ type = "player_joins_server", player_id = player_id })
    end
  end

  local event, error = network.client:receive()

  if not error then
    event_received_callback(app.data.fsm, json.decode(event))

  elseif error == "closed" then
    network.connected = false
    network.client = socket.tcp() -- prevent connect() to still return "already connected" whereas the server has been restarted.
  end
end


function get_player_id()
  local path ="player_id.txt"
  local file = love.filesystem.getInfo(path)
  if not file then love.filesystem.write(path, math.random(10000, 99999)) end
  return string.gsub(love.filesystem.read(path), "[%W]", "")
end


function j(data)
  return json.encode(data)
end
