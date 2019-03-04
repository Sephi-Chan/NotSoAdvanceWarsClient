local utils = {}

function utils.is_within_box(x, y, box)
  if x < box.x then return false end
  if y < box.y then return false end
  if y > box.y + box.height then return false end
  if x > box.x + box.width then return false end
  return true
end


function utils.count(table)
  local count = 0
  for _ in pairs(table) do count = count + 1 end
  return count
end


function utils.split(str, separator)
  local array = {}
  local regexp = string.format("([^%s]+)", separator)
  for mem in string.gmatch(str, regexp) do
      table.insert(array, mem)
  end
  return array
end


-- Turns "42_3" into { 42, 3 }
function utils.split_coords(joined_coords)
  coords = utils.split(joined_coords, "_")
  return { tonumber(coords[1]), tonumber(coords[2]) }
end


function utils.take_n(list, n)
  local selection = {}
  for i = 1, n + 1 do
    table.insert(selection, list[i])
  end
  return selection
end


function utils.trim(string)
  return string:match("^%s*(.-)%s*$")
end


return utils
