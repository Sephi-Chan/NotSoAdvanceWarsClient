local lua_star = require("lib/lua_star")

local Board = {
  tile_side = 16 * scale,

  sprite = lg.newImage("assets/sprites.png"),

  -- Terrains
  forest         = lg.newQuad(0, 128, 16, 16, 800, 600),
  mountains      = lg.newQuad(16, 112, 16, 32, 800, 600),
  hills          = lg.newQuad(32, 128, 16, 16, 800, 600),
  plain_shadowed = lg.newQuad(48, 128, 16, 16, 800, 600),
  plain          = lg.newQuad(64, 128, 16, 16, 800, 600),

  -- Units
  player_1_recon       = { lg.newQuad(0, 0, 16, 16, 800, 600),  lg.newQuad(16, 0, 16, 16, 800, 600),  lg.newQuad(32, 0, 16, 16, 800, 600) },
  player_1_tank        = { lg.newQuad(0, 16, 16, 16, 800, 600), lg.newQuad(16, 16, 16, 16, 800, 600), lg.newQuad(32, 16, 16, 16, 800, 600) },
  player_1_medium_tank = { lg.newQuad(0, 32, 16, 16, 800, 600), lg.newQuad(16, 32, 16, 16, 800, 600), lg.newQuad(32, 32, 16, 16, 800, 600) },
  player_1_refiller    = { lg.newQuad(0, 48, 16, 16, 800, 600), lg.newQuad(16, 48, 16, 16, 800, 600), lg.newQuad(32, 48, 16, 16, 800, 600) },
  player_1_artillery   = { lg.newQuad(0, 64, 16, 16, 800, 600), lg.newQuad(16, 64, 16, 16, 800, 600), lg.newQuad(32, 64, 16, 16, 800, 600) },

  player_2_recon       = { lg.newQuad(48, 0, 16, 16, 800, 600),  lg.newQuad(64, 0, 16, 16, 800, 600),  lg.newQuad(80, 0, 16, 16, 800, 600) },
  player_2_tank        = { lg.newQuad(48, 16, 16, 16, 800, 600), lg.newQuad(64, 16, 16, 16, 800, 600), lg.newQuad(80, 16, 16, 16, 800, 600) },
  player_2_medium_tank = { lg.newQuad(48, 32, 16, 16, 800, 600), lg.newQuad(64, 32, 16, 16, 800, 600), lg.newQuad(80, 32, 16, 16, 800, 600) },
  player_2_refiller    = { lg.newQuad(48, 48, 16, 16, 800, 600), lg.newQuad(64, 48, 16, 16, 800, 600), lg.newQuad(80, 48, 16, 16, 800, 600) },
  player_2_artillery   = { lg.newQuad(48, 64, 16, 16, 800, 600), lg.newQuad(64, 64, 16, 16, 800, 600), lg.newQuad(80, 64, 16, 16, 800, 600) },

  -- Buildings
  player_1_headquarter = { lg.newQuad( 0, 80, 16, 32, 800, 600), lg.newQuad(16, 80, 16, 32, 800, 600) },
  player_2_headquarter = { lg.newQuad(32, 80, 16, 32, 800, 600), lg.newQuad(48, 80, 16, 32, 800, 600) }
}


function Board.tile_at(map, x, y)
  local i = math.ceil(x / Board.tile_side)
  local j = math.ceil(y / Board.tile_side)
  return { i, j }
end


function Board.coords_of(i, j)
  local x = (i - 1) * Board.tile_side
  local y = (j - 1) * Board.tile_side
  return x, y
end


function Board.is_two_tiles_high(terrain)
  return terrain == "player_1_headquarter" or
         terrain == "player_2_headquarter" or
         terrain == "mountains"
end


function Board.is_building(terrain)
  return terrain == "player_1_headquarter" or
         terrain == "player_2_headquarter"
end


function Board.is_building_mine(terrain, player)
  return player == "player_1" and terrain == "player_1_headquarter" or
         player == "player_2" and terrain == "player_2_headquarter"
end


function Board.headquarter_tile(map, player)
  for coords, building in pairs(map.buildings) do
    if building == player .. "_headquarter" then
      return utils.split_coords(coords)
    end
  end
end


function Board.available_tiles_around(game, tile, radius)
  local radius = radius or 1
  local x, y = tile[1], tile[2]
  local candidate_tiles = {}

  for i = x - radius, x + radius do
    for j = y - radius, y + radius do
      table.insert(candidate_tiles, { i, j })
    end
  end

  local onboard_tiles = Board.filter_offboard_tiles(game.map, candidate_tiles)
  return Board.filter_units_and_buildings_tiles(game, onboard_tiles)
end


function Board.attackable_tiles_around(game, attacking_player, unit)
  local radius = unit_types[unit.unit_type_id].range
  local x, y = unit.x, unit.y
  local candidate_tiles = {}

  for i = x - radius, x + radius do
    for j = y - radius, y + radius do
      local unit = game.units[i .. "_" .. j]
      if unit and unit.owner ~= attacking_player then
        table.insert(candidate_tiles, { i, j })
      end
    end
  end

  return Board.filter_offboard_tiles(game.map, candidate_tiles)
end


function Board.tiles_in_range(map, unit)
  local radius = unit_types[unit.unit_type_id].range
  local x, y = unit.x, unit.y
  local tiles = {}

  for i = x - radius, x + radius do
    for j = y - radius, y + radius do
      table.insert(tiles, { i, j })
    end
  end

  return Board.filter_offboard_tiles(map, tiles)
end


function Board.filter_offboard_tiles(map, tiles)
  local filtered_tiles = {}
  for i, tile in ipairs(tiles) do
    local x, y = tile[1], tile[2]
    if 1 <= x and x <= map.columns and
       1 <= y and y <= map.rows then
      table.insert(filtered_tiles, tile)
    end
  end
  return filtered_tiles
end


function Board.filter_units_and_buildings_tiles(game, tiles)
  local filtered_tiles = {}
  for i, tile in ipairs(tiles) do
    local x, y = tile[1], tile[2]
    if game.units[x .. "_" .. y] == nil and game.map.buildings[x .. "_" .. y] == nil then
      table.insert(filtered_tiles, tile)
    end
  end
  return filtered_tiles
end


function Board.path(game, unit, tile)
  local to          = { x = tile[1], y = tile[2] }
  local from        = unit -- Unit has x and y keys so it can be used as is.
  local is_walkable = function(x, y)
    return game.units[x .. "_" .. y] == nil and game.map.buildings[x .. "_" .. y] == nil
  end

  return lua_star:find(game.map.columns, game.map.rows, from, to, is_walkable)
end


return Board
