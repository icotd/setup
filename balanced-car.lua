-- balanced-car.lua
-- A realistic routing profile for OSRM with safer defaults for Ethiopia

function setup()
  return {
    properties = {
      max_speed_for_map_matching = 130 / 3.6,
      weight_name = 'duration',
      weight_precision = 1,
      max_turn_weight = 1000,
      turn_penalty = 15.0,
      turn_bias = 1.3,
      u_turn_penalty = 100,
    },

    default_mode = mode.driving,
    default_speed = 10,

    use_turn_restrictions = true,
    continue_straight_at_waypoint = true,

    speeds = {
      motorway        = 60,
      motorway_link   = 50,
      trunk           = 50,
      trunk_link      = 40,
      primary         = 40,
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
      track           = 10
    },

    ferry_speed = 5,
    ferry_weight = 300,

    surface_speeds = {
      asphalt   = 1.0,
      paved     = 0.9,
      concrete  = 0.8,
      gravel    = 0.7,
      dirt      = 0.6,
      ground    = 0.5,
      mud       = 0.4
    }
  }
end

function process_way(profile, way, result)
  local highway = way:get_value_by_key("highway")
  if not highway or not profile.speeds[highway] then
    return
  end

  local speed = profile.speeds[highway]

  -- Modify speed by surface, if available
  local surface = way:get_value_by_key("surface")
  if surface and profile.surface_speeds[surface] then
    speed = speed * profile.surface_speeds[surface]
  end

  -- Ensure speed is not too low
  if speed < 1 then speed = 1 end

  result.forward_mode = profile.default_mode
  result.backward_mode = profile.default_mode
  result.forward_speed = speed
  result.backward_speed = speed
end

function process_turn(profile, turn)
  local angle = math.abs(turn.angle)
  turn.duration = profile.properties.turn_penalty * (angle / 90.0)

  if turn.has_traffic_light then
    turn.duration = turn.duration + 3
  end

  if turn.is_u_turn then
    turn.duration = turn.duration + profile.properties.u_turn_penalty
  end
end
