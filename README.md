# Grow

A simple growing/farming game built with Godot Engine.

## Description

Grow is a minimal farming game where you play as a character who can plant seeds and watch them grow. Move around the world and plant your seeds to see them develop through different growth stages.

## Features

- Player character with smooth movement (WASD or Arrow Keys)
- Planting system - plant seeds with the Space bar
- Automatic plant growth system with visual feedback
- Seed inventory tracking
- Simple, clean UI

## How to Run

### Prerequisites
- [Godot Engine 4.3+](https://godotengine.org/download) installed on your system

### Running the Game

1. Clone this repository:
   ```bash
   git clone https://github.com/loyalistagenda-crypto/Grow.git
   cd Grow
   ```

2. Open the project in Godot:
   - Launch Godot Engine
   - Click "Import"
   - Navigate to the cloned directory and select `project.godot`
   - Click "Import & Edit"

3. Run the game:
   - Press F5 or click the "Play" button in the top-right corner of the Godot editor
   - Alternatively, use the "Run Project" option from the Project menu

## Controls

- **WASD** or **Arrow Keys**: Move the player character
- **Space**: Plant a seed at your current location

## Game Structure

```
Grow/
├── scenes/          # Godot scene files
│   ├── main.tscn   # Main game scene
│   ├── player.tscn # Player character scene
│   └── plant.tscn  # Plant object scene
├── scripts/         # GDScript files
│   ├── game.gd     # Main game logic
│   ├── player.gd   # Player movement and controls
│   └── plant.gd    # Plant growth logic
├── assets/          # Game assets (sprites, sounds, etc.)
├── project.godot    # Godot project configuration
└── icon.svg        # Project icon
```

## Development

This project uses Godot 4.3+ and GDScript. To modify or extend the game:

1. Open the project in Godot Editor
2. Navigate to the `scenes/` or `scripts/` directories
3. Edit the scenes or scripts as needed
4. Test your changes by running the project (F5)

## License

This project is open source and available for use and modification.
