local board = require("board")
local game = require("game")
local callbacks = {}

function create()
  return lua_fsm.create(
    {
      events = {
        {name = "startup",              from = "none", to = "idle|waiting_actions"},
        {name = "end_turn",             from = "*",    to = "idle"},
        {name = "turn_started",         from = "*",    to = "waiting_actions|idle"},
        {name = "leave",                from = "*",    to = "finished"},
        {name = "player_left",          from = "*",    to = "finished"},
        {name = "hovered_tile_changed", from = "*",    to = "*"},

        -- Training new units.
        {name = "select_building",    from = "waiting_actions",             to = "display_units_shop|waiting_actions"},
        {name = "close_units_shop",   from = "display_units_shop",          to = "waiting_actions"},
        {name = "select_unit_to_buy", from = "display_units_shop",          to = "waiting_deployment_location"},
        {name = "cancel_unit_buying", from = "waiting_deployment_location", to = "waiting_actions"},
        {name = "deploy_unit",        from = "waiting_deployment_location", to = "waiting_actions"},
        {name = "unit_bought",        from = "*",                           to = "*"},

        -- Moving or attacking with units.
        {name = "select_unit",        from = "waiting_actions",          to = "waiting_unit_action"},
        {name = "cancel_unit_action", from = "waiting_unit_action",      to = "waiting_actions"},
        {name = "select_unit_action", from = "waiting_unit_action",      to = "waiting_move_destination|waiting_attack_target"},
        {name = "cancel_unit_action", from = "waiting_move_destination", to = "waiting_actions"},
        {name = "cancel_unit_action", from = "waiting_attack_target",    to = "waiting_actions"},
        {name = "move_unit",          from = "waiting_move_destination", to = "waiting_actions"},
        {name = "unit_moved",         from = "*",                        to = "*"},
        {name = "attack_unit",        from = "waiting_attack_target",    to = "waiting_actions"},
        {name = "fight_ended",        from = "*",                        to = "*|finished"}
      },
      callbacks = {
        on_startup = function(self, event, from, to, app, game, player_id)
          self.data = {
            app = app,
            player_id = player_id,
            whoami = game.player_1 == player_id and "player_1" or "player_2",
            game = game,
            ui = {
              moving_units = {},
              anims = {
                player_1_headquarter = {frame = 1, frames = 2, frame_countdown = math.random(), frame_duration = 0.5},
                player_2_headquarter = {frame = 1, frames = 2, frame_countdown = math.random(), frame_duration = 0.5}
              },
              hover = {},
              board_box = {
                x = math.floor((800 - (game.map.columns * board.tile_side)) / 2),
                y = math.floor((600 - (game.map.rows * board.tile_side)) / 2),
                width = game.map.columns * board.tile_side,
                height = game.map.rows * board.tile_side
              },
              winner_box = {
                width = 300,
                height = 200,
                x = math.floor(800 / 2 - 300 / 2),
                y = math.floor(600 / 2 - 200 / 2)
              },
              units_shop_box = build_shop_box({x = 10, y = 10, width = 300}, unit_types),
              end_turn_button = {x = 400 - 110 / 2, y = 5, width = 110, height = 25},
              unit_action_box = {width = 120, height = 100, children = {}}
            }
          }

          self.current = self.data.whoami == self.data.game.current_player and "waiting_actions" or "idle"
        end,


        on_hovered_tile_changed = function(self, event, from, to, from_tile, to_tile)
          self.current = from

          if self.is("waiting_move_destination") then
            local path = board.path(self.data.game, self.data.acting_unit, to_tile)
            local move = unit_types[self.data.acting_unit.unit_type_id].move
            self.data.move_path = path and utils.take_n(path, move) or {}
          end
        end,


        on_end_turn = function(self, event, from, to)
          self.data.game.current_player = self.data.whoami == "player_1" and "player_2" or "player_1"
          self.current = "idle"
          send({type = "end_turn"})
        end,


        on_turn_started = function(self, event, from, to, current_player, turn)
          self.current = current_player == self.data.whoami and "waiting_actions" or "idle"
          self.data.game.current_player = current_player
          self.data.game.turn = turn

          if current_player == self.data.whoami then
            sound_box.play_sound("horn", 0.4)
          end

          game.reset_units(self.data.game.units, current_player)
        end,


        on_select_building = function(self, event, from, to, building)
          if board.is_building_mine(building, self.data.whoami) then
            self.current = "display_units_shop"
          else
            self.current = from
          end
        end,


        on_enter_waiting_deployment_location = function(self, event, from, to, building)
          local headquarter_tile = board.headquarter_tile(self.data.game.map, self.data.whoami)
          self.data.available_tiles = board.available_tiles_around(self.data.game, headquarter_tile)
        end,


        on_select_unit_to_buy = function(self, event, from, to, unit_type)
          self.data.unit_to_buy = unit_type
        end,


        on_cancel_unit_buying = function(self, event, from, to)
          self.data.available_tiles = nil
        end,


        on_deploy_unit = function(self, event, from, to, unit_type, destination)
          local x, y = destination[1], destination[2]
          self.data.available_tiles = nil
          send({type = "buy_unit", unit_type = unit_type, tile = destination})
        end,


        on_unit_bought = function(self, event, from, to, unit, gold)
          if gold ~= nil then
            self.data.game.players[self.data.whoami].gold = gold
          end
          self.data.game.units[unit.x .. "_" .. unit.y] = unit
          self.current = from
        end,


        on_select_unit = function(self, event, from, to, unit)
          self.data.acting_unit = unit
          update_unit_action_box(self, unit, self.data.ui.unit_action_box)
        end,


        on_select_unit_action = function(self, event, from, to, action)
          local x, y = self.data.acting_unit.x, self.data.acting_unit.y

          if action == "attack" then
            self.current = "waiting_attack_target"
            self.data.available_tiles =
              board.attackable_tiles_around(self.data.game, self.data.whoami, self.data.acting_unit)
            self.data.tiles_in_range = board.tiles_in_range(self.data.game.map, self.data.acting_unit)
          else
            local radius = unit_types[self.data.acting_unit.unit_type_id].move
            self.current = "waiting_move_destination"
            self.data.available_tiles = board.movable_tiles_around(self.data.game, {x, y}, radius)
          end
        end,


        on_move_unit = function(self, event, from, to, unit, destination_tile)
          local ox, oy = unit.x, unit.y
          local move = unit_types[self.data.acting_unit.unit_type_id].move
          local path = board.path(self.data.game, unit, destination_tile)
          local real_path = path and utils.take_n(path, move)
          local final_tile = real_path and real_path[#real_path] or nil

          if final_tile then
            self.data.available_tiles = nil
            self.data.acting_unit = nil

            send({type = "move_unit", unit_id = unit.id, tile = {final_tile.x, final_tile.y}})
          end
        end,


        on_cancel_unit_action = function(self, event, from, to)
          self.data.available_tiles = nil
          self.data.acting_unit = nil
          self.data.tiles_in_range = nil
        end,


        on_unit_moved = function(self, event, from, to, unit, origin_tile, destination_tile)
          local ox, oy = origin_tile[1], origin_tile[2]
          local dx, dy = destination_tile[1], destination_tile[2]
          local path = board.path(self.data.game, {x = ox, y = oy}, destination_tile)

          self.data.ui.moving_units[unit.id] = {path = path, current = 1}
          self.current = from
        end,


        on_attack_unit = function(self, event, from, to, attacking_unit, target_tile)
          local tx, ty = target_tile[1], target_tile[2]
          local target_unit = self.data.game.units[tx .. "_" .. ty]
          self.data.tiles_in_range = nil
          attacking_unit.fired = true
          attacking_unit.moved = true
          send({type = "attack_unit", unit_id = attacking_unit.id, tile = target_tile})
        end,


        on_fight_ended = function(self, event, from, to, attacking_unit, target_unit, result, winner)
          self.data.app.play_fight_cinematic(self.data.game, attacking_unit, target_unit, result)
          game.apply_fight_result(self, result)

          if winner then
            self.data.game.winner = winner
            self.current = "finished"
          else
            self.current = from
          end
        end,


        on_leave = function(self)
          send({type = "player_leaves_game"})
        end,


        on_player_left = function(self, event, from, to, winner)
          self.data.game.winner = winner
        end
      }
    }
  )
end


function callbacks.update(fsm, delta)
  animate_units(fsm.data.game.units, delta)
  animate_buildings(fsm.data.ui.anims, delta)
  update_moving_units(fsm, fsm.data.ui.moving_units, delta)
end


function animate_units(units, delta)
  for _, unit in pairs(units) do
    unit.animation       = unit.animation or "map_idle"
    unit.frame           = unit.frame or 1
    unit.frame_duration  = unit.frame_duration or 0.2
    unit.frame_countdown = unit.frame_countdown or unit.frame_duration

    unit.frame_countdown = unit.frame_countdown - delta
    if unit.frame_countdown <= 0 then
      unit.frame_countdown = unit.frame_duration
      unit.frame = unit.frame + 1

      if unit.frame > #animations[unit.owner][unit.unit_type_id][unit.animation] then
        unit.frame = 1
      end
    end
  end
end


function update_unit_action_box(fsm, unit, box)
  local board_box = fsm.data.ui.board_box
  local x, y = board.coords_of(unit.x, unit.y)
  box.x = board_box.x + x + 20
  box.y = board_box.y + y
  box.width = 80
  box.height = 5 + 25 + 5 + 25 + 5
  box.children.move_box = {
    id = "move",
    label = "Bouger",
    x = box.x + 5,
    y = box.y + 5,
    width = box.width - 10,
    height = 25,
    disabled = unit.moved
  }
  box.children.attack_box = {
    id = "attack",
    label = "Attaquer",
    x = box.x + 5,
    y = box.y + 5 + 25 + 5,
    width = box.width - 10,
    height = 25,
    disabled = unit.fired
  }
end


function animate_buildings(anims, delta)
  for id, anim in pairs(anims) do
    anim.frame_countdown = anim.frame_countdown - delta
    if anim.frame_countdown <= 0 then
      anim.frame = anim.frame + 1
      anim.frame_countdown = anim.frame_duration

      if anim.frame > anim.frames then
        anim.frame = 1
      end
    end
  end
end


function update_moving_units(fsm, moving_units, delta)
  for _, unit in pairs(fsm.data.game.units) do
    if moving_units[unit.id] then
      local data = moving_units[unit.id]
      local next_step_index = data.current + 1
      local last_step = data.path[data.current]
      local next_step = data.path[next_step_index]
      local speed = 100

      unit.shift_x = unit.shift_x or 0
      unit.shift_y = unit.shift_y or 0
      unit.step_shift_x = unit.step_shift_x or 0
      unit.step_shift_y = unit.step_shift_y or 0

      if next_step then
        local direction = get_direction(last_step, next_step)

        if direction == "right" then
          unit.animation = "map_right"
          if unit.step_shift_x < 32 then
            unit.step_shift_x = unit.step_shift_x + speed * delta
            unit.shift_x = unit.shift_x + speed * delta
          else
            unit.step_shift_x = 0
            data.current = data.current + 1
            unit.frame = 1
          end

        elseif direction == "down" then
          unit.animation = "map_down"
          if unit.step_shift_y < 32 then
            unit.step_shift_y = unit.step_shift_y + speed * delta
            unit.shift_y = unit.shift_y + speed * delta
          else
            unit.step_shift_y = 0
            data.current = data.current + 1
            unit.frame = 1
          end

        elseif direction == "left" then
          unit.animation = "map_left"
          if unit.step_shift_x > -32 then
            unit.step_shift_x = unit.step_shift_x - speed * delta
            unit.shift_x = unit.shift_x - speed * delta
          else
            unit.step_shift_x = 0
            data.current = data.current + 1
            unit.frame = 1
          end

        elseif direction == "up" then
          unit.animation = "map_up"
          if unit.step_shift_y > -32 then
            unit.step_shift_y = unit.step_shift_y - speed * delta
            unit.shift_y = unit.shift_y - speed * delta
          else
            unit.step_shift_y = 0
            data.current = data.current + 1
            unit.frame = 1
          end
        end

      else
        -- Arrival!
        origin = data.path[1]
        unit.x = last_step.x
        unit.shift_x = 0
        unit.y = last_step.y
        unit.shift_y = 0
        unit.moved = true
        moving_units[unit.id] = nil
        fsm.data.game.units[origin.x .. "_" .. origin.y] = nil
        fsm.data.game.units[unit.x .. "_" .. unit.y] = unit
        unit.animation = "map_idle"
      end
    end
  end
end


function get_direction(last_step, next_step)
  if next_step.x < last_step.x then return "left" end
  if last_step.x < next_step.x then return "right" end
  if last_step.y < next_step.y then return "down" end
  if next_step.y < last_step.y then return "up" end
end


function callbacks.draw(fsm)
  draw_board(fsm, fsm.data.game.map, fsm.data.ui.board_box)
  draw_deployment_locations(fsm, fsm.data.ui.board_box)
  draw_move_destinations(fsm, fsm.data.ui.board_box)
  draw_attack_targets(fsm, fsm.data.ui.board_box)

  draw_units(fsm, fsm.data.game.units, fsm.data.ui.board_box)
  draw_buildings(fsm, fsm.data.game.map, fsm.data.ui.board_box)
  draw_selection_rectangle(fsm, fsm.data.ui.board_box)

  draw_self_portrait(fsm)
  draw_ennemy_portrait(fsm)
  draw_end_turn_button(fsm)

  draw_unit_action_box(fsm, fsm.data.ui.unit_action_box)
  draw_units_shop_box(fsm, fsm.data.ui.units_shop_box)
  draw_winner_box(fsm, fsm.data.ui.winner_box)
  draw_tips(fsm)

  set_cursor(fsm)
end


function draw_self_portrait(fsm)
  lg.setColor(0, 0, 0)
  lg.rectangle("fill", 0, 0, 115, 45)

  lg.setColor(1, 1, 1)
  lg.rectangle("line", 5, 5, 36, 36)

  lg.setColor(1, 1, 1)
  lg.line(15, 45, 115, 45)
  lg.line(115, 27, 115, 44)

  lg.setColor(1, 1, 1)
  lg.draw(animations.sprites.characters, animations[fsm.data.whoami].portrait[1], 5, 5)
  lg.print(fsm.data.player_id, 46, 5)
  lg.print(fsm.data.game.players[fsm.data.whoami].gold .. " €", 46, 25)
end


function draw_ennemy_portrait(fsm)
  local other_player = fsm.data.whoami == "player_1" and "player_2" or "player_1"

  lg.setColor(0, 0, 0)
  lg.rectangle("fill", 800 - 45, 0, 45, 45)

  lg.setColor(1, 1, 1)
  lg.rectangle("line", 759, 5, 36, 36)
  lg.line(754, 45, 784, 45)
  lg.line(755, 27, 755, 44)
  lg.draw(animations.sprites.characters, animations[other_player].portrait[1], 759, 5)
  lg.printf(fsm.data.game[other_player], 600, 5, 152, "right")
end


function draw_winner_box(fsm, box)
  if not fsm.is("finished") then return end

  lg.setColor(0, 0, 0)
  lg.rectangle("fill", box.x, box.y, box.width, box.height)

  lg.setColor(1, 1, 1)
  lg.rectangle("line", box.x, box.y, box.width, box.height)

  lg.setColor(1, 1, 1)
  if fsm.data.game.winner == fsm.data.whoami then
    local text = "Victoire ! Félicitations !"
    lg.printf(text, box.x, box.y + 10, box.width, "center")
  else
    local text = "Défaite… Quelle déception."
    lg.printf(text, box.x, box.y + 10, box.width, "center")
  end
end


function draw_attack_targets(fsm, board_box)
  if not fsm.is("waiting_attack_target") then return end

  for _, tile in ipairs(fsm.data.tiles_in_range) do
    local x, y = board.coords_of(tile[1], tile[2])
    lg.setColor(1, 0, 1, 0.3)
    lg.rectangle("fill", board_box.x + x, board_box.y + y, board.tile_side, board.tile_side)
  end
end


function draw_unit_action_box(fsm, box)
  if not fsm.is("waiting_unit_action") then return end

  lg.setColor(0, 0, 0)
  lg.rectangle("fill", box.x, box.y, box.width, box.height)

  lg.setColor(1, 1, 1)
  lg.rectangle("line", box.x, box.y, box.width, box.height)

  for id, action_box in pairs(box.children) do
    local hover = fsm.data.ui.hover.unit_action == action_box.id
    lg.setColor(hover and {0.6, 0.6, 0.6} or {0, 0, 0})
    lg.rectangle("fill", action_box.x, action_box.y, action_box.width, action_box.height)

    lg.setColor(action_box.disabled and error_color or {1, 1, 1})
    lg.rectangle("line", action_box.x, action_box.y, action_box.width, action_box.height)
    lg.print(action_box.label, action_box.x + 5, action_box.y + 5)
  end
end


function draw_units(fsm, units, board_box)
  for _, unit in pairs(units) do
    if unit.animation == nil then break end

    local tx, ty = board.coords_of(unit.x, unit.y)
    local sprite = animations[unit.owner][unit.unit_type_id].map_sprite
    local quad   = animations[unit.owner][unit.unit_type_id][unit.animation][unit.frame]
    local done   = unit.moved and unit.fired
    local x = math.floor(board_box.x + tx + (unit.shift_x or 0))
    local y = math.floor(board_box.y + ty + (unit.shift_y or 0))

    lg.setColor(done and {0.5, 0.5, 0.5} or {1, 1, 1})
    if quad then
      lg.draw(sprite, quad, x, y, 0, scale, scale)
    else
      -- FIXME: How can unit frame go too high despite the frame check in animate_units?
      -- Bug noticed with artillery when going upright.
      print("FAIL: No quad for", tostring(unit.owner), tostring(unit.unit_type_id), tostring(unit.animation), tostring(unit.frame))
    end

    if unit.count < 10 then
      local rw, rh = 10, 14
      local rx, ry = x + board.tile_side - rw, y + board.tile_side - rh

      lg.setColor(0, 0, 0)
      lg.rectangle("fill", rx, ry, rw, rh)

      lg.setColor(1, 1, 1)
      lg.print(unit.count, rx + 1, ry)
    end
  end
end


function draw_tips(fsm)
  local text = nil

  if fsm.data.ui.hover.end_turn_button then
    text = "Cliquez sur ce bouton ou appuyez sur [retour arrière] pour terminer votre tour."

  elseif fsm.is("idle") then
    text = "Astuce : Les montagnes et forêts assurent une protection à vos unités. Profitez-en !"

  elseif fsm.is("waiting_actions") then
    if fsm.data.whoami == "player_1" then
      text = "Vous êtes ROUGE. Cliquez sur votre quartier général pour créer des unités, puis cliquez sur vos unités pour agir."
    else
      text = "Vous êtes BLEU. Cliquez sur votre quartier général pour créer des unités, puis cliquez sur vos unités pour agir."
    end

  elseif fsm.is("finished") then
    if fsm.data.game.winner == fsm.data.whoami then
      text = "Félicitations ! Appuyez sur [échap] pour retourner au menu principal. Continuez comme ça !"
    else
      text = "Vous avez perdu ! Appuyez honteusement sur [échap] pour retourner au menu principal. Tâchez de faire mieux !"
    end

  elseif fsm.is("waiting_deployment_location") or fsm.is("waiting_move_destination") or fsm.is("waiting_attack_target") then
    text = "Cliquez gauche pour valider. Cliquez droit ou appuyez sur [échap] pour annuler l'ordre."

  elseif fsm.is("display_units_shop") then
    text = "Cliquez droit ou appuyez sur [échap] pour fermer la fenêtre d'achat."
  end

  if text then
    lg.setColor(1, 1, 1)
    lg.printf(text, 0, 578, 800, "center")
  end
end


function draw_deployment_locations(fsm, board_box)
  if not fsm.is("waiting_deployment_location") then return end

  for _, tile in ipairs(fsm.data.available_tiles) do
    local x, y = board.coords_of(tile[1], tile[2])
    lg.setColor(0, 1, 1, 0.3)
    lg.rectangle("fill", board_box.x + x, board_box.y + y, board.tile_side, board.tile_side)
  end
end


function draw_move_destinations(fsm, board_box)
  if not fsm.is("waiting_move_destination") then return end

  for _, tile in ipairs(fsm.data.available_tiles) do
    local x, y = board.coords_of(tile[1], tile[2])
    lg.setColor(0, 1, 1, 0.3)
    lg.rectangle("fill", board_box.x + x, board_box.y + y, board.tile_side, board.tile_side)
  end

  for _, tile in ipairs(fsm.data.move_path or {}) do
    local x, y = board.coords_of(tile.x, tile.y)
    lg.setColor(1, 1, 1, 0.3)
    lg.rectangle("fill", board_box.x + x, board_box.y + y, board.tile_side, board.tile_side)
  end
end


function draw_units_shop_box(fsm, box)
  if not fsm.is("display_units_shop") then return end

  lg.setColor(0, 0, 0)
  lg.rectangle("fill", box.x, box.y, box.width, box.height)
  lg.setColor(1, 1, 1)
  lg.rectangle("line", box.x, box.y, box.width, box.height)

  for unit_type, unit_box in pairs(box.children) do
    local hover = fsm.data.ui.hover.units_shop_unit == unit_type
    lg.setColor(hover and {0.6, 0.6, 0.6} or {0, 0, 0})
    lg.rectangle("fill", unit_box.x, unit_box.y, unit_box.width, unit_box.height)

    lg.setColor(1, 1, 1)
    lg.setColor(game.has_enough_gold(fsm, unit_box.cost) and {1, 1, 1} or error_color)
    lg.rectangle("line", unit_box.x, unit_box.y, unit_box.width, unit_box.height)
    lg.print(unit_box.label, unit_box.x + 5, unit_box.y + 5)
    lg.printf(unit_box.cost .. " €", unit_box.x, unit_box.y + 5, unit_box.width - 5, "right")
  end
end


function draw_board(fsm, map, box)
  for j = 1, map.rows do
    for i = 1, map.columns do
      if map.special_tiles[i .. "_" .. j] then
        draw_tile(map.special_tiles[i .. "_" .. j], i, j, box)
      else
        local left_tile = map.special_tiles[i - 1 .. "_" .. j]
        if left_tile and left_tile == "mountains" or left_tile == "forest" or left_tile == "hills" then
          draw_tile("plain_shadowed", i, j, box)
        else
          draw_tile("plain", i, j, box)
        end
      end
    end
  end

  lg.setColor(1, 1, 1)
  lg.rectangle("line", box.x, box.y, box.width, box.height)
end


function draw_selection_rectangle(fsm, box)
  if fsm.is("waiting_unit_action") then return end

  if fsm.data.ui.hover.tile then
    local i, j = fsm.data.ui.hover.tile[1], fsm.data.ui.hover.tile[2]
    local x, y = board.coords_of(i, j)

    lg.setColor(1, 1, 1)
    lg.rectangle("line", box.x + x, box.y + y, board.tile_side, board.tile_side)
  end
end


function set_cursor(fsm)
  love.mouse.setCursor(arrow_cursor)

  if fsm.is("waiting_deployment_location") or fsm.is("waiting_move_destination") or fsm.is("waiting_attack_target") then
    local hover_tile = fsm.data.ui.hover.tile
    local tx, ty = (hover_tile and hover_tile[1]), (hover_tile and hover_tile[2])

    for _, tile in ipairs(fsm.data.available_tiles) do
      local x, y = tile[1], tile[2]
      if tx == x and ty == y then
        love.mouse.setCursor(hand_cursor)
        break
      end
    end
  end

  for id, hover in pairs(fsm.data.ui.hover) do
    if id == "tile" then
      local coords = hover[1] .. "_" .. hover[2]
      if
        fsm.is("waiting_actions") and
          ((fsm.data.game.units[coords] and fsm.data.whoami == fsm.data.game.units[coords].owner) or
            fsm.data.game.map.buildings[coords] and
              board.is_building_mine(fsm.data.game.map.buildings[coords], fsm.data.whoami))
       then
        love.mouse.setCursor(hand_cursor)
        break
      end
    elseif hover then
      love.mouse.setCursor(hand_cursor)
      break
    end
  end
end


function draw_end_turn_button(fsm)
  if fsm.is("finished") then return end
  if fsm.data.whoami ~= fsm.data.game.current_player then return end

  local button = fsm.data.ui.end_turn_button
  local hover = fsm.data.ui.hover.end_turn_button

  lg.setColor(0, 0, 0)
  lg.rectangle("fill", button.x - 6, button.y - 5, button.width + 11, button.height + 10)
  lg.setColor(1, 1, 1)
  lg.rectangle("line", button.x - 6, button.y - 5, button.width + 11, button.height + 10)
  lg.setColor(0, 0, 0)
  lg.rectangle("fill", button.x - 10, 0, button.width + 20, 27)

  lg.setColor(hover and {0.6, 0.6, 0.6} or {0, 0, 0})
  lg.rectangle("fill", button.x, button.y, button.width, button.height)

  lg.setColor(1, 1, 1)
  lg.rectangle("line", button.x, button.y, button.width, button.height)
  lg.printf("Terminer le tour", button.x, button.y + 5, button.width, "center")
end


function draw_tile(terrain, i, j, box)
  local x, y = board.coords_of(i, j)
  local offset = board.is_two_tiles_high(building) and -board.tile_side or 0
  lg.setColor(1, 1, 1)
  lg.draw(board.sprite, board[terrain], box.x + x, box.y + y + offset, 0, scale, scale)
end


function draw_buildings(fsm, map, board_box)
  for j = 1, map.rows do
    for i = 1, map.columns do
      if map.buildings[i .. "_" .. j] then
        draw_building(fsm, map.buildings[i .. "_" .. j], i, j, board_box)
      end
    end
  end
end


function draw_building(fsm, building, i, j, box)
  local x, y = board.coords_of(i, j)
  local frame = fsm.data.ui.anims[building].frame
  local quad = board[building][frame]
  local offset = board.is_two_tiles_high(building) and -board.tile_side or 0
  lg.setColor(1, 1, 1)
  lg.draw(board.sprite, quad, box.x + x, box.y + y + offset, 0, scale, scale)
end


function callbacks.event_received(fsm, event)
  -- print("event received", event.type, json.encode(event))

  if event.type == "turn_started" then
    fsm.turn_started(event.current_player, event.turn)

  elseif event.type == "unit_bought" then
    fsm.unit_bought(event.unit, event.gold)

  elseif event.type == "unit_moved" then
    fsm.unit_moved(event.unit, event.origin, event.destination)

  elseif event.type == "fight_ended" then
    fsm.fight_ended(event.attacking_unit, event.target_unit, event.result, event.winner)

  elseif event.type == "player_left" then
    fsm.player_left(event.winner)
  end
end


function callbacks.mousemoved(fsm, x, y)
  fsm.data.ui.hover.end_turn_button = false
  fsm.data.ui.hover.units_shop_unit = nil
  fsm.data.ui.hover.deployment_tile = nil
  fsm.data.ui.hover.unit_action = nil

  if fsm.is("display_units_shop") and utils.is_within_box(x, y, fsm.data.ui.units_shop_box) then
    for unit_type, unit_box in pairs(fsm.data.ui.units_shop_box.children) do
      if utils.is_within_box(x, y, unit_box) and game.has_enough_gold(fsm, unit_box.cost) then
        fsm.data.ui.hover.units_shop_unit = unit_type
        break
      end
    end

  elseif fsm.is("waiting_unit_action") then
    for id, action_box in pairs(fsm.data.ui.unit_action_box.children) do
      if utils.is_within_box(x, y, action_box) and not action_box.disabled then
        fsm.data.ui.hover.unit_action = action_box.id
        break
      end
    end
  end

  if utils.is_within_box(x, y, fsm.data.ui.board_box) then
    local previous_tile = fsm.data.ui.hover.tile
    local new_tile = board.tile_at(fsm.data.game.map, x - fsm.data.ui.board_box.x, y - fsm.data.ui.board_box.y)

    if previous_tile and new_tile and (previous_tile[1] ~= new_tile[1] or previous_tile[2] ~= new_tile[2]) then
      fsm.hovered_tile_changed(previous_tile, new_tile)
    end

    fsm.data.ui.hover.tile = new_tile
  else
    fsm.data.ui.hover.tile = nil
  end

  if not fsm.is("finished") and utils.is_within_box(x, y, fsm.data.ui.end_turn_button) then
    fsm.data.ui.hover.end_turn_button = true
  end
end


function callbacks.mousepressed(fsm, x, y, button)
  if button == 2 and fsm.is("display_units_shop") then
    fsm.close_units_shop()
    return

  elseif button == 1 and fsm.is("display_units_shop") and fsm.data.ui.hover.units_shop_unit then
    fsm.select_unit_to_buy(fsm.data.ui.hover.units_shop_unit)
    return

  elseif button == 2 and fsm.is("waiting_deployment_location") then
    fsm.cancel_unit_buying()
    return

  elseif button == 2 and (fsm.is("waiting_unit_action") or fsm.is("waiting_move_destination") or fsm.is("waiting_attack_target")) then
    fsm.cancel_unit_action()
    return

  elseif button == 1 and fsm.is("waiting_unit_action") and fsm.data.ui.hover.unit_action then
    fsm.select_unit_action(fsm.data.ui.hover.unit_action)
    return

  elseif button == 1 and fsm.is("waiting_move_destination") then
    local chosen_tile = board.tile_at(fsm.data.game.map, x - fsm.data.ui.board_box.x, y - fsm.data.ui.board_box.y)

    for _, tile in ipairs(fsm.data.available_tiles) do
      if chosen_tile[1] == tile[1] and chosen_tile[2] == tile[2] then
        fsm.move_unit(fsm.data.acting_unit, chosen_tile)
        return
      end
    end

  elseif button == 1 and fsm.is("waiting_attack_target") then
    local chosen_tile = board.tile_at(fsm.data.game.map, x - fsm.data.ui.board_box.x, y - fsm.data.ui.board_box.y)

    for _, tile in ipairs(fsm.data.available_tiles) do
      if chosen_tile[1] == tile[1] and chosen_tile[2] == tile[2] then
        fsm.attack_unit(fsm.data.acting_unit, chosen_tile)
        return
      end
    end

  elseif button == 1 and fsm.is("waiting_deployment_location") then
    local chosen_tile = board.tile_at(fsm.data.game.map, x - fsm.data.ui.board_box.x, y - fsm.data.ui.board_box.y)

    for _, tile in ipairs(fsm.data.available_tiles) do
      if chosen_tile[1] == tile[1] and chosen_tile[2] == tile[2] then
        fsm.deploy_unit(fsm.data.unit_to_buy, chosen_tile)
        return
      end
    end
  end

  local tile_clicked = nil

  if utils.is_within_box(x, y, fsm.data.ui.board_box) then
    tile_clicked = board.tile_at(fsm.data.game.map, x - fsm.data.ui.board_box.x, y - fsm.data.ui.board_box.y)
    local coords = tile_clicked[1] .. "_" .. tile_clicked[2]
    local unit = fsm.data.game.units[coords]

    if unit then
      if fsm.is("waiting_actions") and fsm.data.whoami == unit.owner then
        fsm.select_unit(unit)

      elseif fsm.is("waiting_unit_action") and fsm.data.whoami == unit.owner then
        fsm.cancel_unit_action()
        fsm.select_unit(unit)
      end

    elseif fsm.can("select_building") and button == 1 then
      fsm.select_building(fsm.data.game.map.buildings[coords])
    end

  elseif utils.is_within_box(x, y, fsm.data.ui.end_turn_button) then
    fsm.end_turn()
  end
end


function callbacks.keypressed(fsm, key)
  if key == "escape" and fsm.is("display_units_shop") then
    fsm.close_units_shop()

  elseif key == "escape" and fsm.is("waiting_deployment_location") then
    fsm.cancel_unit_buying()

  elseif key == "escape" and (fsm.is("waiting_unit_action") or fsm.is("waiting_move_destination") or fsm.is("waiting_attack_target")) then
    fsm.cancel_unit_action()

  elseif key == "escape" and fsm.is("finished") then
    fsm.data.app.display_main_menu(fsm.data.player_id)

  elseif key == "escape" then
    fsm.leave()

  elseif key == "backspace" then
    fsm.end_turn()

  elseif key == "q" then
    love.event.quit()
  end
end


function build_shop_box(box, unit_types)
  local children = {}
  for i, id in ipairs({"recon", "tank", "medium_tank", "artillery"}) do
    local unit_type = unit_types[id]
    children[id] = {
      x = box.x + 5,
      y = box.y + 5 + (i-1) * 30,
      width = box.width - 10,
      height = 25,
      label = unit_type.name,
      cost = unit_type.cost
    }
  end

  box.height = 5 + utils.count(unit_types) * 30
  box.children = children

  return box
end


return { callbacks = callbacks, create = create }
