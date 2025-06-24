-- balanced-car.lua
-- A realistic routing profile: avoids shortest-time bias, encourages human-like routes

function setup()
    return {
      properties = {
        max_speed_for_map_matching    = 130 / 3.6,
        weight_name                   = 'duration',
        weight_precision              = 1,
        max_turn_weight               = 1000,
        turn_penalty                  = 15.0,
        turn_bias                     = 1.3,
        u_turn_penalty                = 100,
      },
  
      default_mode = mode.driving,
      default_speed = 10,
  
      use_turn_restrictions = true,
      continue_straight_at_waypoint = true,
  
      -- Road speeds for Ethiopia context
      speeds = {
        motorway        = 60,  -- Ring roads / bypasses
        motorway_link   = 50,
        trunk           = 50,  -- e.g., Africa Ave, Airport Rd
        trunk_link      = 40,
        primary         = 40,  -- e.g., Bole Rd, Churchill Ave
        primary_link    = 35,
        secondary       = 30,
        secondary_link  = 25,
        tertiary        = 25,
        tertiary_link   = 20,
        residential     = 20,
        living_street   = 15,
        service         = 10,
        unclassified    = 15,
        road            = 15,
        track           = 10,
      },
  
      -- Penalty for slow/marginal options
      ferry_speed = 5,
      ferry_weight = 300,
  
      -- Speed modifiers based on surface
      surface_speeds = {
        asphalt  = 1.0,
        paved    = 0.9,
        concrete = 0.8,
        gravel   = 0.7,
        dirt     = 0.5,
        mud      = 0.4,
      }
    }
  end
  
  function process_way(profile, way, result)
    local highway = way:get_value_by_key("highway")
    local base_speed = profile.speeds[highway]
  
    if not base_speed then
      return
    end
  
    result.forward_mode = profile.default_mode
    result.backward_mode = profile.default_mode
    result.forward_speed = base_speed
    result.backward_speed = base_speed
  
    local surface = way:get_value_by_key("surface")
    local modifier = profile.surface_speeds[surface]
  
    if modifier then
      result.forward_speed = result.forward_speed * modifier
      result.backward_speed = result.backward_speed * modifier
    end
  end
  
  function process_turn(profile, turn)
    local angle = math.abs(turn.angle or 0)
    local duration = profile.properties.turn_penalty * (angle / 90.0)
  
    if turn.has_traffic_light then
      duration = duration + 3
    end
  
    if turn.is_u_turn then
      duration = duration + profile.properties.u_turn_penalty
    end
  
    turn.duration = duration
  end
  
