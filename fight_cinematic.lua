local callbacks = {}

function create(attacking_unit, target_unit, result, callback)
  return lua_fsm.create({
    initial = "fading",
    events = {
      { name = "startup",                  from = "none",      to = "fading" },
      { name = "keep_fading",              from = "fading",    to = "fading" },
      { name = "start",                    from = "fading",    to = "playing" },
      { name = "keep_playing",             from = "playing",   to = "playing" },
      { name = "update",                   from = "*",         to = "*" },
      { name = "draw",                     from = "*",         to = "*" },
      { name = "sub_animation_ended",      from = "*",         to = "*" },
      { name = "all_sub_animations_ended", from = "*",         to = "finishing" },
      { name = "keep_finishing",           from = "finishing", to = "finishing" },
      { name = "stop",                     from = "finishing", to = "finished" }
    },
    callbacks = {
      on_startup = function(self, event, from, to)
        local is_scrolling     = attacking_unit.unit_type_id ~= "artillery"
        self.result            = result
        self.callback          = callback
        self.tx                = 0
        self.ty                = 150
        self.attackers         = {}
        self.targets           = {}
        self.background        = spawn_background(self, self.tx, self.tx, animations.sprites.plain_large, is_scrolling)
        self.waiting_countdown = 0.2
        self.opacity           = 1

        for i = 1, math.ceil(attacking_unit.count/2) do

          local attacker = spawn_attacking_unit(self, "attacker " .. i, i, attacking_unit)
          table.insert(self.attackers, attacker)
        end

        local targets_animations = animations[target_unit.owner][target_unit.unit_type_id] or animations[target_unit.owner].recon
        local count_to_display   = math.ceil(5 * result.target_unit.count/10) -- varies between 0 and 5
        for i = 1, math.ceil(target_unit.count/2) do -- varies between 1 and 5
          local position     = targets_animations.target_positions[i]
          local is_destroyed = count_to_display == 0 or i <= count_to_display
          local target       = spawn_target_unit(self, "target " .. i, position.x, position.y, targets_animations, is_destroyed)
          table.insert(self.targets, target)
        end
      end,


      on_update = function(self, event, from, to, delta)
        self.current = from
        if     self.current == "fading"    then self.keep_fading(delta)
        elseif self.current == "playing"   then self.keep_playing(delta)
        elseif self.current == "finishing" then self.keep_finishing(delta)
        end
      end,


      on_keep_fading = function(self, event, from, to, delta)
        self.waiting_countdown = self.waiting_countdown - delta
        if self.waiting_countdown < 0 then self.start(delta) end
        self.opacity = self.opacity - 0.8 * delta
      end,


      on_keep_playing = function(self, event, from, to, delta)
        self.background.update(delta)
        for i, attacker in ipairs(self.attackers) do attacker.update(delta) end
        for i, target in ipairs(self.targets) do target.update(delta) end
        self.opacity = self.opacity - 0.8 * delta
      end,


      on_draw = function(self, event, from, to)
        self.current = from
        self.background.draw()
        for i, attacker in ipairs(self.attackers) do attacker.draw() end
        for i, target in ipairs(self.targets) do target.draw() end

        lg.setColor(0, 0, 0, self.opacity)
        lg.rectangle("fill", 0, 0, 800, 600)

        lg.setColor(0, 0, 0)
        lg.rectangle("fill", 398, 0, 4, 600)
      end,


      on_sub_animation_ended = function(self, event, from, to, id)
        self.current = from

        local all_sub_animations_ended = true

        if self.background.current ~= "finished" then
          all_sub_animations_ended = false
        end

        for i, attacker in ipairs(self.attackers) do
          if attacker.current ~= "finished" then
            all_sub_animations_ended = false
          end
        end

        for i, target in ipairs(self.targets) do
          if target.current ~= "finished" then
            all_sub_animations_ended = false
          end
        end

        if all_sub_animations_ended then
          self.all_sub_animations_ended()
        end
      end,


      on_all_sub_animations_ended = function(self)
        self.outro_countdown = 1.5
        self.opacity = 0
      end,


      on_keep_finishing = function(self, event, from, to, delta)
        self.outro_countdown = self.outro_countdown - delta
        if self.outro_countdown < 0 then self.stop() end
        self.opacity = self.opacity + 0.8 * delta
      end,


      on_stop = function(self)
        self.callback()
      end
    }
  })
end


function spawn_attacking_unit(cinematic, id, index, attacking_unit)
  return lua_fsm.create({
    initial = "moving",
    events = {
      { name = "startup",      from = "none",    to = "moving" },
      { name = "keep_moving",  from = "moving",  to = "moving" },
      { name = "brake",        from = "moving",  to = "braking" },
      { name = "keep_braking", from = "braking", to = "braking" },
      { name = "idle",         from = "braking", to = "idling" },
      { name = "keep_idling",  from = "idling",  to = "idling" },
      { name = "fire",         from = "idling",  to = "firing" },
      { name = "keep_firing",  from = "firing",  to = "firing" },
      { name = "cease_fire",   from = "firing",  to = "idling" },
      { name = "stop",         from = "idling",  to = "finished" },
      { name = "update",       from = "*",       to = "*" },
      { name = "draw",         from = "*",       to = "*" }
    },
    callbacks = {
      on_startup = function(self)
        self.weapon           = attacking_unit.unit_type_id == "recon" and "submachine_gun" or (0 < attacking_unit.ammo and "cannon" or "submachine_gun")
        self.moving           = attacking_unit.unit_type_id ~= "artillery"
        self.id               = id
        self.cinematic        = cinematic
        self.frame_duration   = 0.1
        self.frame_countdown  = self.frame_duration
        self.animations       = animations[attacking_unit.owner][attacking_unit.unit_type_id] or animations[attacking_unit.owner].recon
        self.animation        = "moving"
        self.frame            = 1
        self.x                = self.animations.attacking_positions[index].x
        self.y                = self.animations.attacking_positions[index].y
        self.ammo             = self.weapon == "cannon" and 1 or 2
        self.moving_countdown = self.animations.attacking_positions[index].moving_countdown
      end,


      on_update = function(self, event, from, to, delta)
        self.current = from
        if     self.current == "moving"  then self.keep_moving(delta)
        elseif self.current == "braking" then self.keep_braking(delta)
        elseif self.current == "idling"  then self.keep_idling(delta)
        elseif self.current == "firing"  then self.keep_firing(delta)
        end
      end,


      on_keep_moving = function(self, event, from, to, delta)
        animate_unit(self, delta)
        self.x = self.moving and self.x + 50 * delta or self.x
        self.moving_countdown = self.moving_countdown - delta
        if self.moving_countdown < 0 then self.brake() end
      end,


      on_brake = function(self)
        self.x                 = math.ceil(self.x)
        self.animation         = "braking"
        self.frame             = 1
        self.braking_countdown = 0.45
      end,


      on_keep_braking = function(self, event, from, to, delta)
        animate_unit(self, delta)
        self.braking_countdown = self.braking_countdown - delta
        if self.braking_countdown < 0 then self.idle(delta) end
      end,


      on_idle = function(self)
        self.animation        = "idling"
        self.frame            = 1
        self.idling_countdown = 0.8
      end,


      on_keep_idling = function(self, event, from, to, delta)
        self.idling_countdown = self.idling_countdown - delta
        if self.idling_countdown < 0 and 0 < self.ammo then
          self.fire(delta)
        elseif self.ammo == 0 then
          self.stop()
        end
      end,


      on_fire = function(self)
        self.animation        = self.weapon == "cannon" and "cannoning" or "firing"
        self.frame            = 1
        self.firing_countdown = 1

        sound_box.play_sound(self.weapon, 0.4)
      end,


      on_keep_firing = function(self, event, from, to, delta)
        animate_unit(self, delta)
        self.firing_countdown = self.firing_countdown - delta
        if self.firing_countdown < 0 then self.cease_fire(delta) end
      end,


      on_cease_fire = function(self)
        self.animation        = "idling"
        self.frame            = 1
        self.ammo             = self.ammo - 1
        self.idling_countdown = 0.5
      end,


      on_stop = function(self)
        self.cinematic.sub_animation_ended(self.id)
      end,


      on_draw = function(self, event, from, to)
        self.current = from
        lg.setColor(1, 1, 1)
        lg.draw(self.animations.sprite, self.animations[self.animation][self.frame], self.x, self.y, 0, 2, 2)
      end
    }
  })
end


function spawn_target_unit(cinematic, id, x, y, animations, is_destroyed)
  return lua_fsm.create({
    initial = "moving",
    events = {
      { name = "startup",         from = "none",       to = "idling" },
      { name = "keep_idling",     from = "idling",     to = "idling" },
      { name = "suffer",          from = "idling",     to = "suffering" },
      { name = "keep_suffering",  from = "suffering",  to = "suffering" },
      { name = "explode",         from = "suffering",  to = "finished" },
      { name = "recover",         from = "suffering",  to = "finished" },
      { name = "update" ,         from = "*",          to = "*" },
      { name = "draw",            from = "*",          to = "*" }
    },
    callbacks = {
      on_startup = function(self)
        self.id               = id
        self.cinematic        = cinematic
        self.is_destroyed     = is_destroyed
        self.frame_duration   = 0.1
        self.frame_countdown  = self.frame_duration
        self.animations       = animations
        self.animation        = "idling"
        self.frame            = 1
        self.x                = x
        self.y                = y
        self.idling_countdown = 2.2
        self.exploded         = false
      end,


      on_keep_idling = function(self, event, from, to, delta)
        self.idling_countdown = self.idling_countdown - delta
        if self.idling_countdown < 0 then self.suffer(delta) end
      end,


      on_suffer = function(self, event, from, to, delta)
        self.suffering_countdown = 3

        self.flash_countdown     = 0
        self.delay_between_flashes = function() return (math.random() + 0.8) end
        self.flashing_duration   = 0.02
        self.flashing_countdown  = self.flashing_duration
        self.flashing            = false
      end,


      on_keep_suffering = function(self, event, from, to, delta)
        self.suffering_countdown = self.suffering_countdown - delta
        if self.suffering_countdown < 0 then
          if self.is_destroyed then self.explode(delta)
          else self.recover(delta) end
        end

        self.flash_countdown = self.flash_countdown - delta
        if self.flash_countdown < 0 then
          self.flashing = true
          self.x = self.x + math.random(50, 100) * delta
        end

        if self.flashing then
          self.flashing_countdown = self.flashing_countdown - delta
          if self.flashing_countdown < 0 then
            self.flashing = false
            self.flashing_countdown = self.flashing_duration
            self.flash_countdown = self.delay_between_flashes()
          end
        end
      end,


      on_explode = function(self, event, from, to, delta)
        self.flashing = false
        self.exploded = true
        self.cinematic.sub_animation_ended(self.id)
      end,


      on_recover = function(self, event, from, to, delta)
        self.flashing = false
        self.cinematic.sub_animation_ended(self.id)
      end,


      on_update = function(self, event, from, to, delta)
        self.current = from

        if     self.current == "idling"    then self.keep_idling(delta)
        elseif self.current == "suffering" then self.keep_suffering(delta)
        end
      end,


      on_draw = function(self, event, from, to)
        self.current = from

        if not self.exploded then
          lg.setColor(1, 1, 1)
          lg.draw(self.animations.sprite, self.animations[self.animation][self.frame], self.x, self.y, 0, -2, 2)
        end

        if self.flashing then
          lg.setColor(1, 1, 1)
          lg.rectangle("fill", 400, 100, 400, 336)
        end
      end
    }
  })
end


function animate_unit(fsm, delta)
  fsm.frame_countdown = fsm.frame_countdown - delta
  if fsm.frame_countdown < 0 then
    fsm.frame_countdown = 0
    fsm.frame           = fsm.frame + 1
    fsm.frame_countdown = fsm.frame_duration
    if fsm.frame > #fsm.animations[fsm.animation] then
      fsm.frame = 1
    end
  end
end


function spawn_background(cinematic, x, y, sprite, is_scrolling)
  return lua_fsm.create({
    initial = "scrolling",
    events = {
      { name = "startup",        from = "none",      to = "scrolling" },
      { name = "keep_scrolling", from = "scrolling", to = "scrolling" },
      { name = "stop",           from = "scrolling", to = "finished" },
      { name = "update",         from = "*",         to = "*" },
      { name = "draw",           from = "*",         to = "*" }
    },
    callbacks = {
      on_startup = function(self)
        self.cinematic           = cinematic
        self.sprite              = sprite
        self.x                   = x
        self.y                   = y
        self.scrolling_countdown = 1
      end,


      on_update = function(self, event, from, to, delta)
        self.current = from
        if self.current == "scrolling" then self.keep_scrolling(delta) end
      end,


      on_keep_scrolling = function(self, event, from, to, delta)
        self.x = is_scrolling and self.x - 100 * delta or self.x
        self.scrolling_countdown = self.scrolling_countdown - delta
        if self.scrolling_countdown < 0 then self.stop() end
      end,


      on_stop = function(self, event, from, to)
        self.cinematic.sub_animation_ended("background")
      end,


      on_draw = function(self, event, from, to)
        self.current = from
        lg.setColor(1, 1, 1)
        lg.draw(self.sprite, self.x, self.y + 100, 0, 2, 2)
        lg.draw(self.sprite, 400, 100, 0, 2, 2)
      end,
    }
  })
end


function callbacks.update(fsm, delta)
  fsm.update(delta)
end


function callbacks.draw(fsm)
  fsm.draw()
end


function callbacks.event_received(fsm, event)
end


function callbacks.mousemoved(fsm, x, y)
end


function callbacks.mousepressed(fsm, x, y, button)
end


function callbacks.keypressed(fsm, key)
  if key == "escape" then
    love.event.quit()
  end
end


return { callbacks = callbacks, create = create }
