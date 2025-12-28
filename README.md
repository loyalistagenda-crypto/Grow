# Grow - A Single Plant Care Game

A cozy tamagotchi-style plant growing game made with Godot 4.

## Features

- **Plant Care System**: Water, feed nutrients, prune, and repot your plant
- **Three Flower Variants**: Choose between purple, yellow, or red flowers
- **Day/Night Cycle**: 240-second cycle with smooth sky transitions, sun/moon arcs, and stars
- **Branching System**: Plant grows taller and develops branches as you repot
- **Dynamic Lighting**: Move your plant under the shed canopy to control sunlight exposure
- **Ambient Environment**: Moving clouds, shooting stars at night, and animated critters (birds, squirrels, butterflies)
- **Background Music**: Looping audio with toggle control (press M or use button)

## Controls

- **Mouse/Touch**: Click action buttons (Water, Feed, Prune, Repot), drag pot to move plant
- **Keyboard Shortcuts**:
  - `1` - Toggle UI visibility
  - `M` - Toggle music
  - `F` - Feed nutrients
  - `P` - Prune wilted leaves
  - `R` - Repot plant
  - `` ` `` (backtick) - Fast-forward time (10x speed)

## How to Play

1. **Choose Your Flower**: Select purple, yellow, or red at the start menu
2. **Care for Your Plant**: 
   - Keep moisture and nutrients balanced
   - Maintain ideal sunlight (55% ± 25%)
   - Prune wilted leaves when stressed
   - Repot when growth reaches pot capacity
3. **Watch It Bloom**: Plant progresses through bud → blooming → full bloom stages
4. **Environmental Control**: Drag the pot left/right to adjust sunlight under the shed canopy

## Project Structure

```
grow/
├── scripts/
│   ├── Main.gd       # Main game controller, day/night cycle, UI
│   ├── Plant.gd      # Plant simulation and rendering
│   └── Shed.gd       # Foreground shed/canopy rendering
├── assets/
│   └── audio/
│       └── bg_music.mp3  # Background music (add your own)
└── project.godot
```

## Running the Game

1. Open the project in Godot 4.x
2. Press F5 or click Run
3. Optionally add your own music file at `assets/audio/bg_music.mp3`

## License

MIT License - Feel free to use and modify for your own projects!
