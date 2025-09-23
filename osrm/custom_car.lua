-- custom_car.lua (API v4)
local profile = dofile('/opt/car.lua')

-- resolve CSV path relative to this script
local script_dir = (debug.getinfo(1, 'S').source:match("@(.*/)")) or "./"
local csv_path = script_dir .. "addis_speeds.csv"

local csv_speeds = {}
local function read_csv(path)
  local f = io.open(path, "r")
  if not f then
    io.stderr:write("[warn] cannot open CSV: " .. tostring(path) .. "\n")
    return
  end
  local line_no = 0
  for line in f:lines() do
    line_no = line_no + 1
    if not (line_no == 1 and line:match("^%s*osmid%s*,")) then
      local id, sp = line:match("^%s*(%d+)%s*,%s*([%d%.]+)")
      if id and sp then csv_speeds[tonumber(id)] = tonumber(sp) end
    end
  end
  f:close()
  local n=0; for _ in pairs(csv_speeds) do n=n+1 end
  io.stderr:write("[info] CSV speeds loaded: " .. n .. " from " .. path .. "\n")
end

read_csv(csv_path)

local orig_process_way = profile.process_way
profile.process_way = function(self, way, result)
  orig_process_way(self, way, result)
  local spd = csv_speeds[way:id()]
  if spd then
    if result.forward_mode ~= 0 then result.forward_speed = spd end
    if result.backward_mode ~= 0 then result.backward_speed = spd end
  end
end

return profile
