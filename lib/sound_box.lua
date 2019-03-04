local Soundbox = {
  _sources = {}
}


function Soundbox.register_sound(name, path)
  Soundbox._sources[name] = love.audio.newSource(path, "static")
end


function Soundbox.play_sound(name, volume)
  local clone = Soundbox._sources[name]:clone()
  clone:setVolume(volume or 1.0)
  love.audio.play(clone)
end


function Soundbox.play_music(name, volume)
  local source = Soundbox._sources[name]
  source:setVolume(volume or 1.0)
  source:setLooping(true)
  love.audio.play(source)
end


function Soundbox.stop()
  for name, source in pairs(Soundbox._sources) do
    source:stop()
  end
end


return Soundbox
