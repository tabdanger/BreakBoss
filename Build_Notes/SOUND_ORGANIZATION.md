# BreaKing sound organization (for DAW Breaker's sequencer)

Tyrone's rules as of 2026-11-08, BreakBoss main after PR #146 and #147. If you're building DAW Breaker's sequencer,
follow these so its kits and patterns match BreaKing.

## 1. Acoustic drums belong to Vintage only
- "Acoustic" means the Virtuosity CC0 drums (`ac_*.wav`, 12 sounds) and Tyrone's own acoustic pack (`va_*.wav`,
  42 sounds: Yamaha kick, Custom Works snare, Sabian hats, ride, splash, Star Classic toms).
- Vintage kits use only acoustic sounds. Their clap, 808 and perc pads stay EMPTY because there are no acoustic ones yet.
- **No Modern (or Platinum) kit plays an acoustic sound.** The Modern rock kits (STUDIO A, ARENA ANTHEM, TAILGATE) use
  electronic stock sounds now.
- Texture's rock/soul kits (`kit_catalog.ACOUSTIC_GENRES` outside Modern) stay acoustic.

## 2. The 13 live-drummer styles are Vintage only
Neo Soul, Dilla Time, Boom Bap, 90s Rap, 70s Soul, 80s Breaks, Rock, Vintage R&B, Live Soul, East Coast, Lo-fi,
Live Pop, World & Latin (`PatternBank.vintageStyles`).
- Vintage: the PATTERNS menu, arrows and GENRE list show only these 13 styles. The KITS menu shows only Vintage's
  acoustic kits.
- Modern/Platinum: those 13 styles are hidden from PATTERNS, arrows and GENRE. KITS hides the Vintage bank and the
  live-drummer genre kits (ROCK, POP ROCK, LIVE ROCK, SOFT ROCK, ARENA ROCK, LIVE SOUL).
- Texture shows every style and every bank.
- Nothing is deleted. Hidden items stay in the tables, so preset numbers never move and old saves still open.

## 3. Bay Area and West Coast kits use only @prod.by.iiinfinite sounds
- Every WEST COAST-tab kit outside Vintage follows this: Bay Area 50, West Coast 20, Hyphy, Ratchet, LA Jerk,
  New G-Funk, West Trap, Bay Area 2026, BK Danger, and Texture's West Coast genres. These kits play only stock sounds
  whose source file is from the `@prod.by.iiinfinite` folders (224 files, `KitLibrary.iiinfiniteFiles`).
- Exception: the Go2Spinz 808 ("BK NO 5 C1 808") stays on every Bay Area kit's 808 pad.
- EMPTY pads stay EMPTY. A kit made from a loop holds only that loop's sounds.

## 4. Kit rules that still hold
- Rack order, top to bottom: 808, kick, clap, snare, hi hat, open hat, rim, low tom, high tom, perc 1, perc 2, crash.
- 12 pads, MIDI notes 36-47 (MPK pad N = pad N). Pads and sequencer channels are 1:1.
- One sound is never on two pads. Every pitched sound is in C.
- Kits change only sounds; presets change only patterns.
- New PATTERNS styles are appended at the end so AUv3 preset numbers never shift.
- Menus are collapsible folders by genre/style (KITS folders "TAB · BANK", tabs TRAP, WEST COAST, SOUL & R&B, BREAKS,
  POP, WORLD, plus a DRUM MACHINE ERA folder outside Vintage).
- Sound names follow "BK NO n KIND". The last word is the kind.

## Where it lives in BreakBoss
- `tools/kit_catalog.py`: genres, ACOUSTIC_GENRES, Bay Area/West Coast kit lists.
- `tools/build_kits.py`: builds the kits. `west_coast_iiinfinite` applies rule 3, and Modern acoustic picks are
  swapped out there. It writes `Resources/StockSamples/manifest.json` and `FactoryKits.swift`.
- `KitLibrary.swift`: `browsedModes`, `kits(for:in:)`, `liveDrummerGenres`, `rackOrder`.
- `PatternBank.swift`: `vintageStyles`, `styles(for:)`, `browserOrder(for:)`.
- PRs: #146 (kits), #147 (menus).
