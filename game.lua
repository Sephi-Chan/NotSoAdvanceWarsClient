local Game = {}


function Game.current_player_id(game)
  return game[game.current_player]
end


function Game.has_enough_gold(fsm, cost)
  return cost <= fsm.data.game.players[fsm.data.whoami].gold
end


function Game.reset_units(units, player)
  for _, unit in pairs(units) do
    if unit.owner == player then
      unit.moved = false
      unit.fired = false
    end
  end
end


function Game.apply_fight_result(fsm, result)
  local game = fsm.data.game
  local attacking_unit, target_unit = result.attacking_unit, result.target_unit
  local ax, ay = attacking_unit.x, attacking_unit.y
  local tx, ty = target_unit.x, target_unit.y

  if attacking_unit.count == 0 then
    game.units[ax .. "_" .. ay] = nil
  else
    game.units[ax .. "_" .. ay] = attacking_unit
  end

  if target_unit.count == 0 then
    game.units[tx .. "_" .. ty] = nil
  else
    game.units[tx .. "_" .. ty] = target_unit
  end
end

return Game
