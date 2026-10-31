extends Node
## MAYHEM design tokens — autoload as "Tokens".
## Source of truth: DESIGN_BRIEF / SPEC-STYLEGUIDE-HUD.md. Do not hardcode these values elsewhere.

# ---------------------------------------------------------------- Colour: neutral ramp
const VOID   := Color("#07080B")  ## letterbox, deepest shadow
const BASE   := Color("#14161C")  ## panel fill (use with PANEL_ALPHA)
const RAISED := Color("#1E212B")  ## cards, empty bar track
const LINE   := Color("#2C3140")  ## dividers, inactive slot borders
const DIM    := Color("#454C60")  ## disabled text, cooldown fill
const MUTED  := Color("#8A90A3")  ## labels, secondary text
const TEXT   := Color("#E6E8EF")  ## primary text, crosshair

# ---------------------------------------------------------------- Colour: accents
const PLAYER := Color("#35E0D4")  ## yours: health, ammo, grapple. Shape: square
const ENEMY  := Color("#FF3B54")  ## threat, damage in, hitmarkers. Shape: diamond/chevron
const REWARD := Color("#FFB020")  ## currency, pickups, Host voice. Shape: circle
## Lava orange, not the acid green this shipped with - the pool material is meant to
## read as molten rock, and this is the one colour every hazard, the elite-wave
## stripe and the elite archetype itself are keyed to. Distinct from ENEMY's
## crimson-pink on purpose: one is "this attacks you", the other is "this burns you".
const HAZARD := Color("#FC3A00")  ## traps, elite waves, power-ups. Shape: triangle
const HEAL   := Color("#8AF0C4")  ## healing VFX only, never UI

const GLOW_PLAYER := Color("#12706A")
const GLOW_ENEMY  := Color("#7A1425")
const GLOW_REWARD := Color("#7A5000")
const GLOW_HAZARD := Color("#7A1B00")

const PANEL_ALPHA    := 0.82  ## BASE fill over gameplay
const SUBTITLE_ALPHA := 0.72  ## VOID fill behind subtitles

# ---------------------------------------------------------------- Layout (base 1920x1080, 8px grid)
const GRID           := 8
const SCREEN_MARGIN  := 48
const PANEL_PADDING  := 24
const CLUSTER_GAP    := 16
const ROW_GAP        := 14
const CHAMFER        := 12   ## bottom-right 45 degree cut on panels and slots
const NO_UI_ZONE     := Vector2(900, 500)
const SUBTITLE_Y     := -210 ## from bottom
const ANNOUNCE_Y     := 180  ## from top
const SUBTITLE_MAX_W := 1100
const ULTRAWIDE_CLAMP_X := 1000

# ---------------------------------------------------------------- Type sizes
const FONT_DISPLAY   := "res://ui/fonts/Archivo-Variable.woff2"    # wdth 125 / wght 800
## Deviation from the handoff: Google Fonts ships the Archivo variable face as woff2,
## not ttf. Godot 4 loads woff2 natively, so only the extension changes.
const FONT_UI        := "res://ui/fonts/IBMPlexSans-Regular.ttf"
const FONT_UI_SEMI   := "res://ui/fonts/IBMPlexSans-SemiBold.ttf"
const FONT_MONO      := "res://ui/fonts/IBMPlexMono-SemiBold.ttf"

const SIZE_ANNOUNCE     := 64
const SIZE_DISPLAY_SM   := 20
const SIZE_NUM_PRIMARY  := 56   ## health, ammo magazine
const SIZE_NUM_CLUSTER  := 40   ## wave number, currency
const SIZE_NUM_SECOND   := 28   ## reserve, timer, enemies left
const SIZE_SUBTITLE     := 30
const SIZE_LABEL        := 15   ## uppercase, tracking 0.16em
const SIZE_KEYBIND      := 13
const TRACKING_LABEL    := 0.16
const SUBTITLE_MAX_LINES := 2

# ---------------------------------------------------------------- Component sizes
const HEALTH_SEGMENTS   := 10
const HEALTH_SEG_SIZE   := Vector2(41, 14)
const HEALTH_SEG_GAP    := 3
const AMMO_PIP_SIZE     := Vector2(8, 12)
const AMMO_PIP_GAP      := 3
const AMMO_PIP_MAX      := 40   ## above this, one pip per 2 rounds
const SLOT_SIZE         := Vector2(72, 72)
const SLOT_ICON         := 28
## Ancho de cada columna de la barra de habilidades: lo que ocupa la etiqueta mas
## larga ("C · SLOW", "E GRAPPLE"). Fijo, para que las ranuras queden a la misma
## distancia entre si sin importar cuanto mida cada etiqueta.
const SLOT_COLUMN_W     := 96
const PAR_BAR_SIZE      := Vector2(360, 4)
const POWERUP_BAR_W     := 230
const ICON_GRID         := 64
const ICON_STROKE       := 4

# ---------------------------------------------------------------- Thresholds
const LOW_HEALTH_PCT := 0.30
const LOW_AMMO_PCT   := 0.25

# ---------------------------------------------------------------- Motion (seconds)
const TWEEN_VALUE        := 0.12  ## bar catches up to a snapped number
const GHOST_DRAIN        := 0.30  ## ENEMY ghost segment behind health loss
const HITMARKER_LIFE     := 0.12
const KILL_CONFIRM_LIFE  := 0.20
const KILL_CONFIRM_SCALE := 1.35
const DAMAGE_PULSE       := 0.35
const DAMAGE_CHEVRON_LIFE := 1.20
const DAMAGE_CHEVRON_RADIUS := 260.0
const SUBTITLE_FADE_IN   := 0.12
const SUBTITLE_HOLD_MIN  := 1.20
const SUBTITLE_FADE_OUT  := 0.20
const ANNOUNCE_LIFE      := 3.00
## Gadgets: how many pickups of each per run get the full "what it does" callout,
## and how long the slot shows the gadget's name after a pickup.
const GADGET_CALLOUT_REPEATS := 2
const GADGET_NAME_LIFE       := 2.5
const LOW_HEALTH_PULSE   := 1.10  ## continuous, ease-in-out
const LOW_AMMO_BLINK     := 0.90  ## continuous, step (on/off)
const HAZARD_WARNING     := 0.60  ## telegraph before a hazard can damage
const HAZARD_EVAPORATE   := 0.40  ## a temporary pool drying up after it stops damaging
const STATE_SETTLE_MAX   := 0.40  ## nothing else may animate longer than this

## UI punch (UiMotion). Every one-shot stays under STATE_SETTLE_MAX: the motion
## answers an action, it never makes the player wait for it.
const UI_PUNCH_TIME      := 0.22  ## a number that just changed swells and settles
const UI_PUNCH_SCALE     := 1.18  ## how far it swells; small numbers read as jitter
const UI_FLASH_TIME      := 0.30  ## tint of a gain/loss fading back to the base colour
const UI_ENTER_TIME      := 0.26  ## a panel arriving: ease out, back overshoot
const UI_ENTER_OFFSET    := 28.0  ## px it travels to get there
const UI_EXIT_TIME       := 0.14  ## leaving is faster than arriving
const UI_STAGGER         := 0.06  ## between cards dealt in a row
const UI_SHAKE_TIME      := 0.24  ## "no": a refused purchase
const UI_SHAKE_PX        := 9.0
const ANNOUNCE_POP_SCALE := 1.35  ## the wave banner lands from bigger
const RARE_REVEAL_DELAY  := 0.18  ## a rare card lands a beat after the rest
const RARE_REVEAL_SCALE  := 1.16
const RARE_GLOW_PERIOD   := 1.40  ## continuous, like LOW_HEALTH_PULSE
const RARE_SHEEN_TIME    := 0.40  ## one light sweep across the card
const RARE_SHEEN_EVERY   := 2.60

# ---------------------------------------------------------------- Crosshair
const RETICLE_BASE      := 40
const RETICLE_EXPANDED  := 56  ## grapple-anchor-available
const RETICLE_TICK      := Vector2(2, 11)
const RETICLE_GAP       := 8
const RETICLE_DOT       := 2
const RETICLE_OUTLINE   := 1   ## VOID outline for bright backgrounds

## Accent -> companion shape. Colour is never the only signal.
const SHAPE_FOR := {
	"player": "square",
	"enemy": "diamond",
	"reward": "circle",
	"hazard": "triangle",
}

# ================================================================ World / part 2
## Player body (NOT the HUD colour — nothing in the world glows HUD cyan except traversal)
const ARM_BRAND      := Color("#B45CFF")  ## arcane binding on the player's arms
const ARM_PLATE      := Color("#2C3140")
const ARM_SLEEVE     := Color("#1E212B")

## Enemy dominant colours. Silhouette is the primary read; colour confirms.
const ENEMY_RUSHER   := Color("#FF3B54")
const ENEMY_RANGER   := Color("#FF7A1F")
## Silhouette outline on every enemy model, in its body_color. The default width;
## the player picks their own in options (`video/enemy_outline_px`), between
## the two limits. Thinner than the 2 px it was: with the bloom on top it read
## as a neon tube rather than an edge.
const ENEMY_OUTLINE_PX     := 1.25
const ENEMY_OUTLINE_PX_MIN := 0.5
const ENEMY_OUTLINE_PX_MAX := 3.0
const ENEMY_OUTLINE_ENERGY := 1.3
## Visual styles (`video/visual_style`, VisualStyle).
##
## Neon broadcast: a thin edge of light on world silhouettes. A cool off-white and
## not a law colour: cyan would say "yours" about every wall in the arena.
const NEON_EDGE        := Color("#C9D6FF")
const NEON_EDGE_ALPHA  := 0.45
const NEON_EDGE_ENERGY := 1.6
const NEON_EDGE_PX     := 1.5
## Where the shadows lean in the broadcast grade.
const BROADCAST_SHADOW := Color("#1A2A6C")
##
## Toon: the dark ink line drawn wherever
## depth or surface direction breaks. VOID, not black: the same deepest shade the
## UI uses, so the world and the HUD share one ink.
const TOON_LINE        := Color("#07080B")
## The default width; the player picks their own in options
## (`video/toon_line_px`). 1 px vanished against the dark arena, and 2 still
## read as a hairline at 1440p.
const TOON_LINE_PX     := 3.0
const TOON_LINE_PX_MIN := 1.0
const TOON_LINE_PX_MAX := 4.0
## How an enemy goes when it dies: a burst of shards in its body_color, a puff of
## smoke and a short flash of light. Before this it vanished between two frames,
## and a kill was a number with nothing in the world to show for it.
const DEATH_BURST_LIFE   := 1.0
const DEATH_FLASH_TIME   := 0.18
const DEATH_FLASH_ENERGY := 4.0
## A body this tall gets the burst at scale 1; taller and shorter scale with it.
const DEATH_BURST_HEIGHT := 1.8
const ENEMY_ELITE    := Color("#FC3A00")
const ENEMY_HEALER   := Color("#B45CFF")
const ENEMY_SUMMONER := Color("#FF3BC1")
## Warning yellow, and the only enemy outside the warm red-to-magenta family. The
## Bomber is the one archetype the player is supposed to look at and think about
## position rather than threat, so it does not read as "another one of those" -
## and yellow is the colour every player already knows means "this is about to go
## off". Cold enough not to be confused with REWARD's amber, which is the only
## other bright warm thing in the arena.
const ENEMY_BOMBER   := Color("#F5E000")
## Verde tóxico: es el único arquetipo cuyo peligro no está en su cuerpo sino en
## lo que deja en el piso, y el verde es lo que ya significa "químico" sin que
## nadie lo explique. Lejos del mint de HEAL (que es pálido y desaturado a
## propósito, y además nunca aparece en el mundo salvo como VFX de curación).
const ENEMY_ENVIRONMENTAL := Color("#5FD93A")
## Violeta frío: el único que no pisa el piso, y el único color del elenco que no
## aparece en ninguna otra parte del mundo. Estaba escrito a mano en el `.tres`,
## que es exactamente lo que esta lista existe para impedir - y de paso lo dejaba
## afuera de las pruebas de conformidad, que iteran ENEMY_HEIGHT.
const ENEMY_FLYER    := Color("#9966F2")

const ENEMY_HEIGHT := {
	"rusher": 1.2,
	"ranger": 1.9,
	"elite": 2.8,
	"healer": 2.0,
	"summoner": 2.2,
	"bomber": 1.0,
	# Era 2.5 y no pasaba bajo una plataforma de nivel 1: entre el piso y la
	# plataforma quedan 2.25 m. Mas ancho para no compartir silueta con el Summoner.
	"environmental": 2.0,
	# Mas bajo que el Bomber, que es la otra esfera del elenco: comparten forma, y
	# en el aire la silueta es lo unico que queda para distinguirlos de un vistazo.
	"flyer": 0.8,
}

const CHASSIS       := Color("#2C3140")
const JOINT         := Color("#1E212B")
const EMISSIVE_MAX_AREA := 0.08  ## fraction of an enemy's surface that may be emissive

## Enemy telegraph durations (seconds)
const TELL_RUSHER_CROUCH  := 0.40
const TELL_RANGER_CHARGE  := 0.80
const TELL_RANGER_AIMLINE := 0.20  ## line is visible this long before the shot
const TELL_ELITE_WINDUP   := 1.20
const TELL_SUMMON_PLATE   := 1.50
## The Bomber's fuse blink, accelerating from the first step to the second as the
## count runs out. Same language as the vanishing platform (PLATFORM_BLINK_STEP /
## _FAST) on purpose: the player has already been taught that a blink getting
## faster means a deadline, so the fuse needs no new vocabulary.
##
## Unlike every other tell in this block, this one keeps running while the enemy
## walks - it is a countdown, not a wind-up, and it does not stop for anything.
const TELL_BOMBER_FUSE_SLOW := 0.28
const TELL_BOMBER_FUSE_FAST := 0.07

## Arena interactive colour law
const WORLD_TRAVERSAL := PLAYER  ## "you can use this"  — square/bracket shape
const WORLD_HAZARD    := HAZARD  ## "this will hurt you" — 45 degree stripes
const WORLD_PICKUP    := REWARD  ## "take this"          — circle
const SPAWN           := Color("#FF3BC1")  ## "enemies come from here" — doors and summon plates only
## "you can hook onto this" — grapple anchors only. Its own hue and not traversal
## cyan: the anchor is the one thing the grapple takes, and among the cyan of every
## pad and platform it was hard to pick out. Violet, clear of the SPAWN magenta and
## of the enemies' crimson.
const WORLD_GRAPPLE   := Color("#A855FF")

## Gadgets: the colour each one reads in, on the floor (the core inside the amber
## pickup halo), in the HUD, on its effect and on the enemies it touches. All cool,
## so the core stands out against the amber halo, and clear of the law colours:
## the stun grenade was traversal cyan and the slow field grapple violet, which is
## half of why players could not tell what a gadget was doing. The shape
## (MayhemIcon and the pickup mesh) carries the rest.
const GADGET_STUN    := Color("#F2F6FF")  ## electric white — lightning
const GADGET_SLOW    := Color("#5B6CFF")  ## indigo — hourglass
const GADGET_BARRIER := Color("#8FD3FF")  ## sky blue — shield
const GADGET_MEDKIT  := HEAL
## The ring over a stunned enemy: how far above its head, and how fast it turns.
const STATUS_RING_LIFT  := 0.35
const STATUS_RING_SPEED := 4.0
## How long the area ring of a gadget takes to open to its full radius and fade.
const GADGET_AREA_FLASH := 0.45
## Seconds before a barrier or slow field ends that it starts blinking.
const GADGET_ENDING_BLINK := 1.5

## Arena telegraph timings (seconds)
const PLATFORM_WARNING       := 1.50
const PLATFORM_BLINK_STEP    := 0.25
const PLATFORM_BLINK_FAST    := 0.10  ## final 0.4s
const DOOR_TELEGRAPH         := 3.00
const ANCHOR_PULSE           := 2.00
const BOUNCE_CHEVRON_LOOP    := 1.00
const PICKUP_BOB             := 1.00

## Lighting: brightness multiplier per arena height level
const LEVEL_BRIGHTNESS := [1.00, 1.15, 1.30]

## ADS zoom per weapon
const ADS_ZOOM := {
	"rifle": 1.30,
	"shotgun": 1.00,
	"smg": 1.15,
	"pistol": 1.20,
}

# ================================================================ Economy screens / part 3
const SHOP_TIMER          := 30.0  ## seconds between waves
const SHOP_TIMER_URGENT   := 5.0   ## below this the number turns ENEMY
const SHOP_CARD_SIZE      := Vector2(428, 290)
const SHOP_ITEM_ROW_SIZE  := Vector2(428, 150)
const SHOP_GRID_GAP       := 24
const SHOP_MARGIN         := 64
const STACK_MAX           := 5     ## hard cap: more stops being glanceable
const FOCUS_RING_WIDTH    := 2
const FOCUS_RING_OFFSET   := 4

## Upgrade category -> frame shape + accent (frame states category, glyph states subject)
const CATEGORY_FRAME := {
	"mobility": "square",
	"weapon": "diamond",
	"survivability": "circle",
}
const CATEGORY_COLOR := {
	"mobility": PLAYER,
	"weapon": ENEMY,
	"survivability": REWARD,
}

## Wave-complete reveal timeline (seconds from screen open)
const REVEAL_TITLE      := 0.00
const REVEAL_KILLS      := 0.60
const REVEAL_SPEED      := 1.40
const REVEAL_NODAMAGE   := 2.10
const REVEAL_TOTAL      := 2.70
const REVEAL_FOOTER     := 3.40
const REVEAL_COUNT_ROW  := 0.50  ## per-row number count-up
const REVEAL_COUNT_TOTAL := 0.60
const REVEAL_TITLE_SLAM := 0.18

## Income source -> row accent (each row carries its source's colour; this is how the economy is taught)
const INCOME_COLOR := {
	"kills": ENEMY,
	"speed": PLAYER,
	"no_damage": PLAYER,
	"lost": DIM,
}

# ================================================================ Menus / Host / part 4
const MENU_MARGIN_X      := 110
const MENU_RAIL_WIDTH    := 4     ## selection rail — same idea as equipped weapon in the HUD
const MENU_WASH_ALPHA    := 0.14  ## PLAYER gradient behind the selected row
const PAUSE_DIM          := 0.78  ## arena stays visible: the show goes on without you
const SETTINGS_NAV_WIDTH := 300
const BINDINGS_PER_ACTION := 2    ## primary + alternate

## Ranges
const FOV_RANGE       := Vector2(80, 120)
const FOV_DEFAULT     := 104
const SENS_RANGE      := Vector2(0.1, 10.0)
const SENS_DEFAULT    := 2.40
const ADS_MULT_DEFAULT := 0.72
const HUD_SCALES      := [0.8, 1.0, 1.2]
const CROSSHAIR_GAP_RANGE   := Vector2(0, 20)
const CROSSHAIR_THICK_RANGE := Vector2(1, 6)
## Third preset used to be the old hazard green (#C6FF3D), stale since HAZARD
## moved to lava orange - swapped to HAZARD itself so a future crosshair-preset
## picker can't offer a color the rest of the game's color law abandoned.
const CROSSHAIR_COLORS      := [Color("#E6E8EF"), Color("#35E0D4"), HAZARD, Color("#FF3BC1")]
const LEADERBOARD_ENTRIES   := 10
const LEADERBOARD_PATH      := "user://leaderboard.json"

## Host / broadcast
const HOST_MARK_STROKE   := 5     ## crossed ring: circle + cross, two primitives
const BUG_EDGE_HEIGHT    := 4     ## persistent amber top edge
const BUG_MARK_ALPHA     := 0.60
const LOWER_THIRD_WIPE   := 0.24
const LOWER_THIRD_HOLD   := 2.50
const HOST_LINE_COOLDOWN := 20.0  ## min seconds between combat lines
const HOST_PUNCHLINE_PER_WAVE := 1

## Subtitle tier -> rail colour. Tier 3 drops the tag and sets the line in display type.
const HOST_TIER_COLOR := {
	1: REWARD,   ## standard taunt
	2: HAZARD,   ## warning the player must act on
	3: REWARD,   ## punchline: Archivo, no tag, 10% wash
}
