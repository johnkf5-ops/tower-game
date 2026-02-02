# Tower

A modern take on the classic vertical tower management simulation, inspired by SimTower and Yoot Tower.

## Overview

Build and manage a skyscraper. Place floors, install elevators, add offices and other tenants. Keep your population happy by optimizing elevator wait times and managing the flow of people through your building.

## Current Features (v0.1)

- [x] Basic floor construction
- [x] Elevator shaft placement
- [x] Office placement
- [x] Camera pan and zoom
- [x] Day/night time cycle
- [x] Basic economy (money, costs)

## Planned Features

- [ ] Elevator car AI and pathfinding
- [ ] People simulation (spawning, destinations, waiting)
- [ ] Tenant types (residential, retail, restaurant)
- [ ] Tenant satisfaction system
- [ ] Building star rating
- [ ] Events (VIP visitors, emergencies)
- [ ] Sound design

## Controls

- **Left Click**: Place building elements (when build mode active)
- **Right Click / Middle Mouse**: Pan camera
- **Scroll Wheel**: Zoom in/out
- **Arrow Keys**: Pan camera

## Development

Built with Godot 4.2+

### Setup

1. Clone the repository
2. Open project.godot in Godot Engine
3. Press F5 to run

### Project Structure

```
tower-game/
├── project.godot
├── scenes/
│   └── main.tscn
├── scripts/
│   ├── main.gd          # Game controller, time, economy
│   ├── building.gd      # Floor/elevator/tenant management
│   ├── ui.gd            # Interface updates
│   └── game_camera.gd   # Pan and zoom
└── assets/
    ├── sprites/
    └── audio/
```

## License

TBD
