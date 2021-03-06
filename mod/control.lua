local generated = require("generated")
local overrides = require("overrides")
local entities = require("entities")

-- All settings of the mod.
local params = {}

-- Read all settings and update the params var, incl. overrides.
function update_params(player)
  -- settings.player[xxx] does contain the value at the beginning of the game,
  -- while get_player_settings contains the current value.
  local s = settings.get_player_settings(player)
  for k, v in pairs(s) do
    params[k] = v.value
  end

  for k,v in pairs(game.json_to_table(overrides)) do
    params[k] = v
  end

  log("mapshot update_params:\n" .. serpent.block(params))
end

-- Generate a full map screenshot.
-- prefix: path where to save the shot.
-- name: a name for the shot, saved in mapshot.json.
function mapshot(player, prefix, name)
  player.print("Mapshot '" .. prefix .. "' ...")
  log("Mapshot target " .. prefix)

  local surface = game.surfaces["nauvis"]

  -- Determine map min & max world coordinates based on existing chunks.
  local world_min = { x = 2^30, y = 2^30 }
  local world_max = { x = -2^30, y = -2^30 }
  local chunk_count = 0
  for chunk in surface.get_chunks() do
    local c = surface.is_chunk_generated(chunk)
    if params.area == "entities" then
      c = c and surface.count_entities_filtered({ area = chunk.area, limit = 1, type = entities.includes}) > 0
    end
    if c then
      world_min.x = math.min(world_min.x, chunk.area.left_top.x)
      world_min.y = math.min(world_min.y, chunk.area.left_top.y)
      world_max.x = math.max(world_max.x, chunk.area.right_bottom.x)
      world_max.y = math.max(world_max.y, chunk.area.right_bottom.y)
      chunk_count = chunk_count + 1
    end
  end
  if chunk_count == 0 then
    log("no matching chunk")
    player.print("No matching chunk")
    return
  end
  player.print("Map: (" .. world_min.x .. ", " .. world_min.y .. ")-(" .. world_max.x .. ", " .. world_max.y .. ")")
  local area = {
    left_top = {world_min.x, world_min.y},
    right_bottom = {world_max.x, world_max.y},
  }

  -- Range of tiles to render, in power of 2.
  local tile_range_min = math.log(params.tilemin, 2)
  local tile_range_max = math.log(params.tilemax, 2)

  -- Size of a tile, in pixels.
  local render_size = params.resolution

  -- Find train stations
  local stations = {}
  for _, ent in ipairs(surface.find_entities_filtered({area=area, name="train-stop"})) do
    table.insert(stations, {
      backer_name = ent.backer_name,
      bounding_box = ent.bounding_box,
    })
  end

  -- Find all chart tags - aka, map labels.
  local tags = {}
  for _, force in pairs(game.forces) do
    for _, tag in ipairs(force.find_chart_tags(surface, area)) do
      table.insert(tags, {
        force_name = force.name,
        force_index = force.index,
        icon = tag.icon,
        tag_number = tag.tag_number,
        position = tag.position,
        text = tag.text,
      })
    end
  end

  -- Write metadata.
  game.write_file(prefix .. "mapshot.json", game.table_to_json({
    name = name,
    tick = game.tick,
    tile_size = math.pow(2, tile_range_max),
    render_size = render_size,
    world_min = world_min,
    world_max = world_max,
    player = player.position,
    zoom_min = 0,
    zoom_max = tile_range_max - tile_range_min,
    seed = game.default_map_gen_settings.seed,
    map_exchange = game.get_map_exchange_string(),
    stations = stations,
    tags = tags,
  }))

  -- Create the serving html.
  game.write_file(prefix .. "index.html", generated.html)

  -- Generate all the tiles.
  for tile_range = tile_range_max, tile_range_min, -1 do
    local tile_size = math.pow(2, tile_range)
    local render_zoom = tile_range_max - tile_range
    gen_layer(player, tile_size, render_size, world_min, world_max, prefix .. "zoom_" .. render_zoom .. "/")
  end

  player.print("Mapshot done at " .. prefix)
  log("Mapshot done at " .. prefix)
end

function gen_layer(player, tile_size, render_size, world_min, world_max, prefix)
  -- Zoom. We want to have render_size pixels represent tile_size world unit.
  -- A zoom of 1.0 means that 32 pixels represent 1 world unit. A zoom of 2.0 means 64 pixels per world unit.
  local zoom = render_size / 32 / tile_size

  local tile_min = { x = math.floor(world_min.x / tile_size), y = math.floor(world_min.y / tile_size) }
  local tile_max = { x = math.floor(world_max.x / tile_size), y = math.floor(world_max.y / tile_size) }

  local msg =  "Tile size " .. tile_size .. ": " .. (tile_max.x - tile_min.x + 1) * (tile_max.y - tile_min.y + 1) .. " tiles to generate"
  player.print(msg)
  log(msg)

  for tile_y = tile_min.y, tile_max.y do
    for tile_x = tile_min.x, tile_max.x do
      local top_left = { x = tile_x * tile_size, y = tile_y * tile_size }
      game.take_screenshot{
        position = {
          x = top_left.x + tile_size / 2,
          y = top_left.y + tile_size / 2,
        },
        resolution = {render_size, render_size},
        zoom = zoom,
        path = prefix .. "tile_" .. tile_x .. "_" .. tile_y .. ".jpg",
        show_gui = false,
        show_entity_info = true,
        quality = params.jpgquality,
        daytime = 0,
        water_tick = 0,
      }
    end
  end
end

-- Detects if an on-startup screenshot is requested.
script.on_event(defines.events.on_tick, function(evt)
  log("onstartup check @" .. evt.tick)
  -- Needs to run only once, so unregister immediately.
  script.on_event(defines.events.on_tick, nil)

  -- Assume player index 1 during startup.
  local player = game.get_player(1)
  update_params(player)
  if params.onstartup ~= "" then
    log("onstartup requested id=" .. params.onstartup)
    local name = params.shotname .. "-" .. evt.tick
    local prefix = params.prefix .. name .. "/"
    mapshot(player, prefix, params.shotname)

    -- Write the `done` marker on the next tick - that seems to be
    -- enough to guarantee ordering. Otherwise, the `done` file might
    -- be written before the screenshots, leading to killing Factorio
    -- too early. On Linux, using signal Interrupt helps a lot, but
    -- that does not guarantee it - and it is not available on Windows.
    script.on_event(defines.events.on_tick, function(evt)
      log("marking as done @" .. evt.tick)
      script.on_event(defines.events.on_tick, nil)
      game.write_file("mapshot-done-" .. params.onstartup, prefix)
    end)
  end
end)

-- Register the command.
-- It seems that on_init+on_load sometime don't trigger (neither of them) when
-- doing weird things with --mod-directory and list of active mods.
commands.add_command("mapshot", "screenshot the whole map", function(evt)
  local player = game.get_player(evt.player_index)
  update_params(player)

  -- Where to store the output.
  local name = "seed" .. game.default_map_gen_settings.seed .. "-" .. evt.tick
  if evt.parameter ~= nil and #evt.parameter > 0 then
    name = evt.parameter
  end
  local prefix = params.prefix .. name .. "/"
  mapshot(player, params.prefix .. name .. "/", name)
end)