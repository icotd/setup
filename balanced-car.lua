local mode = { driving = 1 }

function setup()
  return {
    properties = {
      weight_name = 'duration'
    },
    default_mode = mode.driving,
    default_speed = 10,
    speeds = { residential = 30 },
  }
end

function process_way(profile, way, result)
  local highway = way:get_value_by_key("highway")
  if highway == "residential" then
    result.forward_mode = profile.default_mode
    result.backward_mode = profile.default_mode
    result.forward_speed = 30
    result.backward_speed = 30
    result.is_valid = true
  end
end

function process_turn(profile, turn) end
