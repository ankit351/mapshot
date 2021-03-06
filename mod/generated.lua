-- Automatically generated, do not modify
local data = {}
data.html = [==[
<html>

<head>
  <title>Mapshot</title>
  <style type="text/css">
    html,
    body {
      margin: 0;
    }
  </style>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.6.0/dist/leaflet.css"
    integrity="sha512-xwE/Az9zrjBIphAcBb3F6JVqxf46+CDLwfLMHloNu6KEQCAWi6HcDUbeOfBIptF7tcCzusKFjFw2yuvEpDL9wQ=="
    crossorigin="" />
  <script src="https://unpkg.com/leaflet@1.6.0/dist/leaflet.js"
    integrity="sha512-gZwIG9x3wUXg2hdXF6+rVkLF/0Vi9U8D2Ntg4Ga5I5BZpVkVxlJWbSQtXPSiUTtC0TjtGOmxa1AJPuV0CPthew=="
    crossorigin=""></script>
</head>

<body>
  <div id="map" style="height: 100%;"></div>
  <script>
    'use strict';
    const params = new URLSearchParams(window.location.search);
    let path = params.get("path") ?? "";
    if (!!path && path[path.length - 1] != "/") {
      path = path + "/";
    }
    console.log("Path", path);

    fetch(path + 'mapshot.json')
      .then(resp => resp.json())
      .then(info => {
        console.log("Map info", info);

        const worldToLatLng = function (x, y) {
          const ratio = info.render_size / info.tile_size;
          return L.latLng(
            -y * ratio,
            x * ratio
          );
        };

        const midPointToLatLng = function (bbox) {
          return worldToLatLng(
            (bbox.left_top.x + bbox.right_bottom.x) / 2,
            (bbox.left_top.y + bbox.right_bottom.y) / 2,
          );
        }

        const baseLayer = L.tileLayer(path + "zoom_{z}/tile_{x}_{y}.jpg", {
          tileSize: info.render_size,
          bounds: L.latLngBounds(
            worldToLatLng(info.world_min.x, info.world_min.y),
            worldToLatLng(info.world_max.x, info.world_max.y),
          ),
          noWrap: true,
          maxNativeZoom: info.zoom_max,
          minNativeZoom: info.zoom_min,
          minZoom: info.zoom_min - 4,
          maxZoom: info.zoom_max + 4,
        });

        const debugLayer = L.layerGroup([
          L.marker([0, 0], { title: "Start" }).bindPopup("Starting point"),
          L.marker(worldToLatLng(info.player.x, info.player.y), { title: "Player" }).bindPopup("Player"),
          L.marker(worldToLatLng(info.world_min.x, info.world_min.y), { title: `${info.world_min.x}, ${info.world_min.y}` }),
          L.marker(worldToLatLng(info.world_min.x, info.world_max.y), { title: `${info.world_min.x}, ${info.world_max.y}` }),
          L.marker(worldToLatLng(info.world_max.x, info.world_min.y), { title: `${info.world_max.x}, ${info.world_min.y}` }),
          L.marker(worldToLatLng(info.world_max.x, info.world_max.y), { title: `${info.world_max.x}, ${info.world_max.y}` }),
        ]);

        let stations = [];
        if (info.stations) {
          for (const station of info.stations) {
            stations.push(L.marker(
              midPointToLatLng(station.bounding_box),
              { title: station.backer_name },
            ).bindTooltip(station.backer_name, { permanent: true }))
          }
        }
        const stationsLayer = L.layerGroup(stations);

        let tags = [];
        if (info.tags) {
          for (const tag of info.tags) {
            tags.push(L.marker(
              worldToLatLng(tag.position.x, tag.position.y),
              { title: `${tag.force_name}: ${tag.text}` },
            ).bindTooltip(tag.text, { permanent: true }))
          }
        }
        const tagsLayer = L.layerGroup(tags);

        const mymap = L.map('map', {
          crs: L.CRS.Simple,
          layers: [baseLayer],
        });

        L.control.layers({/* Only one default base layer */ }, {
          "Train stations": stationsLayer,
          "Tags": tagsLayer,
          "Debug": debugLayer,
        }).addTo(mymap);

        mymap.setView([0, 0], 0);
      });
  </script>
</body>

</html>]==]
return data
