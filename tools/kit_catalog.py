"""The KITS browser's genre tabs, and the named kits that fill each mode bank under each tab (Oct 17).

Tyrone asked for at least 20 kits under every genre tab in every mode bank. tools/build_kits.py keeps the
42 A/B kits exactly as they were and adds these. Each kit is built from the stock sounds the app already
has; its genre (the line on its card) decides which sounds it reaches for, and its mode bank leans the
picks the way that mode sounds:

  MODERN   clean, bright and punchy: today's records.
  VINTAGE  dusty, roomy and warm: the genre the way it sounded when it began.
  TEXTURE  dark, wide and worn: lo-fi, ambient, warped and glitched takes.

Each entry: (genre on the card, groove style, tempo, synth voice, tags, likes, [kit names]).
Tags and likes mean what they mean in build_kits.py GENRES. Kits that share a genre never share a sound.
"""

# The browser's genre tabs, in order (BrowserView chips, KitLibrary.families).
FAMILIES = ["TRAP", "WEST COAST", "SOUL & R&B", "BREAKS", "POP", "WORLD"]

# Which tab each of the 21 A/B genres sits under. FX LAB is under ALL only.
OLD_FAMILY = {
    "TRAP": "TRAP", "ALT TRAP": "TRAP", "DRILL": "TRAP", "UK DRILL": "TRAP", "NY DRILL": "TRAP", "DETROIT 2026": "TRAP",
    "BAY AREA 2026": "WEST COAST",
    "RNB": "SOUL & R&B", "UK RNB": "SOUL & R&B", "NEO SOUL": "SOUL & R&B", "DILLA TIME": "SOUL & R&B",
    "70S SOUL": "SOUL & R&B", "90S RNB": "SOUL & R&B",
    "BOOM BAP": "BREAKS", "90S RAP": "BREAKS", "80S BREAKS": "BREAKS",
    "ROCK": "POP",
    "AFROBEATS": "WORLD", "AMAPIANO": "WORLD", "WORLD PERC": "WORLD",
    "FX LAB": "FX",
}

# How each mode bank leans every pick (added to the genre's own likes).
MODE_LIKES = {
    "modern": {"bright": 0.4, "punch": 0.4, "dusty": -0.3},
    "vintage": {"dusty": 0.6, "room": 0.4},
    "texture": {"dusty": 0.4, "dark": 0.5, "wide": 0.5},
}

# The perc pads each tab leans to when a genre doesn't say.
FAMILY_PERC = {
    "TRAP": ["HIT", "METAL", "CLICK"], "WEST COAST": ["SHAKER", "WOOD", "HIT"], "SOUL & R&B": ["SHAKER", "TAMB", "WOOD"],
    "BREAKS": ["TAMB", "SHAKER", "WOOD"], "POP": ["SHAKER", "TAMB", "HIT"], "WORLD": ["WOOD", "SHAKER", "CLAVE", "BEADS", "TAMB"],
}

KITS = {
    # ---------------------------------------------------------------- MODERN
    ("modern", "TRAP"): [
        ("ATL TRAP", "trapAtlanta", 142, "modernTrap", ["trap", "dark"], {"long808": 0.8}, ["ZONE 6", "BANKHEAD BOUNCE", "MOTION 808"]),
        ("RAGE", "trapAtlanta", 160, "modernTrap", ["rage", "electronic", "trap"], {"long808": 1.0, "perc": ["METAL", "HIT"]}, ["SYNTH RIOT", "MOSH PIT"]),
        ("TORONTO TRAP", "trapToronto", 138, "drumMastery", ["trap", "dark", "rnb"], {"dark": 0.5, "long808": 0.6}, ["NORTHSIDE FOG", "YORKVILLE"]),
        ("HOUSTON TRAP", "trapAtlanta", 72, "modernTrap", ["trap", "west", "dark"], {"long808": 1.0, "wide": 0.4}, ["HOUSTON CANDY"]),
    ],
    ("modern", "WEST COAST"): [
        ("RATCHET", "westBounce", 98, "westBounce", ["west", "trap"], {"wide": 0.8, "punch": 0.4, "perc": ["SHAKER", "HIT"]},
         ["CRENSHAW CLAP", "SLAUSON SLIDE", "INGLEWOOD HEAT", "CARSON HOPS"]),
        ("HYPHY", "baySlap", 100, "baySlap", ["west", "trap", "detroit"], {"wide": 0.6, "punch": 0.6}, ["SIDESHOW", "GHOST RIDE", "YAY AREA SLAP", "VALLEJO KNOCK"]),
        ("LA JERK", "westBounce", 100, "westBounce", ["west", "electronic", "trap"], {"bright": 0.6, "perc": ["CLICK", "HIT", "WOOD"]}, ["JERK CIRCLE", "POP LOCK", "DOUGIE STEP"]),
        ("WEST TRAP", "trapAtlanta", 96, "modernTrap", ["west", "trap", "detroit"], {"long808": 0.6}, ["PALMDALE NIGHTS", "818 VALLEY", "POMONA DUST"]),
        ("NEW G-FUNK", "westBounce", 94, "west90s", ["west", "funk", "90srnb"], {"wide": 0.4}, ["PCH CRUISE", "SUNSET HYDRAULICS", "CHROME SPOKES", "LOWRIDER LAWN"]),
    ],
    ("modern", "SOUL & R&B"): [
        ("ALT R&B", "rnb", 70, "westBounce", ["rnb", "dark"], {"dark": 0.6, "long808": 0.8}, ["VELVET HOURS", "AFTER PARTY", "NIGHT DRIVE", "CITY LIGHTS"]),
        ("TRAP SOUL", "trapSoul", 68, "westBounce", ["rnb", "trap", "dark"], {"long808": 0.8}, ["SLOW BURN", "PILLOW TALK", "TEXT ME BACK"]),
        ("MODERN GOSPEL", "gospel", 104, "gospelChops", ["soul", "rnb"], {"room": 0.5, "perc": ["TAMB", "SHAKER"]}, ["SUNDAY SERVICE", "CHOIR STAND", "PRAISE BREAK"]),
        ("BEDROOM R&B", "rnb", 80, "westBounce", ["rnb", "soul"], {"dark": 0.3}, ["SILK SHEETS", "CANDLELIGHT", "LATE CHECKOUT"]),
        ("NEO R&B", "neoSoul", 84, "neoSoul", ["soul", "rnb", "jazz"], {"cym": "RIDE"}, ["GOLDEN HOUR", "HONEY GLAZE", "SOFT FOCUS"]),
    ],
    ("modern", "BREAKS"): [
        ("DRUM & BASS", "looseBreak", 174, "looseBreak", ["electronic", "funk"], {"bright": 0.6}, ["LIQUID ROLLER", "BREAK RUSH", "DARKSIDE STEP", "HALFTIME PRESSURE"]),
        ("JUNGLE", "looseBreak", 165, "looseBreak", ["funk", "electronic", "boombap"], {"room": 0.4}, ["RUDE BOY JUNGLE", "SOUND SYSTEM", "DUBPLATE"]),
        ("BIG BEAT", "heavyBreak", 128, "heavyBreak", ["funk", "electronic"], {"room": 0.6, "punch": 0.4}, ["BIG BEAT SMASH", "ACID BREAKS"]),
        ("UK GARAGE", "looseBreak", 132, "looseBreak", ["electronic", "rnb"], {"bright": 0.5, "perc": ["SHAKER", "CLICK", "WOOD"]}, ["TWO STEP", "GARAGE SKANK", "BASSLINE BOUNCE"]),
        ("MODERN BOOM BAP", "boomBap", 90, "funkBreak", ["boombap", "trap", "funk"], {"punch": 0.4}, ["CONCRETE BOOM", "BRICK CITY", "CYPHER CIRCLE"]),
        ("B-BOY BREAKS", "funkBreak", 112, "funkBreak", ["funk", "boombap", "electronic"], {"room": 0.3}, ["B-BOY BATTLE", "HEADSPIN", "CARDBOARD FLOOR"]),
        ("FOOTWORK", "trap", 160, "drumMastery", ["electronic", "trap"], {"perc": ["CLICK", "HIT"]}, ["FOOTWORK JUKE", "CHI TRACKS"]),
    ],
    ("modern", "POP"): [
        ("DANCE POP", "pop", 124, "west90s", ["pop80", "electronic", "rnb"], {"bright": 0.6}, ["NEON CLUB", "PEAK HOUR", "GLITTER BALL"]),
        ("POP", "pop", 100, "west90s", ["pop80", "rnb", "90srnb"], {"wide": 0.6}, ["RADIO SINGLE", "CHART TOPPER", "HOOK FIRST", "STADIUM CLAP"]),
        ("HYPERPOP", "pop", 160, "modernTrap", ["electronic", "rage"], {"bright": 0.8, "perc": ["METAL", "CLICK"]}, ["BUBBLEGUM GLITCH", "SUGAR CRASH"]),
        ("ELECTROPOP", "pop80s", 118, "west90s", ["pop80", "electronic"], {"bright": 0.4}, ["CHROME HEART", "LASER GLOW"]),
        ("POP TRAP", "trap", 140, "modernTrap", ["trap", "pop80", "rnb"], {"wide": 0.5}, ["DIAMOND HOOK", "VIRAL BOUNCE"]),
        ("POP ROCK", "heavyBreak", 120, "heavyBreak", ["pop80", "funk"], {"room": 0.8}, ["ARENA ANTHEM", "TAILGATE"]),
        ("K-POP", "pop", 120, "modernTrap", ["pop80", "electronic", "rage"], {"bright": 0.5, "wide": 0.4}, ["IDOL STAGE", "COMEBACK SHOW"]),
        ("DISCO POP", "pop", 116, "west90s", ["funk", "pop80", "soul"], {"perc": ["TAMB", "SHAKER"]}, ["MIRROR DISCO", "ROLLER RINK", "VELVET ROPE"]),
    ],
    ("modern", "WORLD"): [
        ("AFROBEATS", "afrobeats", 104, "baySlap", ["world", "amapiano"], {"perc": ["WOOD", "SHAKER", "CLAVE"]}, ["LAGOS LIGHTS", "LEKKI NIGHTS", "OWAMBE"]),
        ("AMAPIANO", "amapiano", 113, "modernTrap", ["amapiano", "world"], {"perc": ["WOOD", "SHAKER", "CLICK"]}, ["LOG DRUM SUNDAY", "SOWETO SHUFFLE", "PRETORIA GROOVE"]),
        ("AFRO HOUSE", "amapiano", 122, "modernTrap", ["amapiano", "world", "electronic"], {"perc": ["SHAKER", "WOOD"]}, ["JOBURG DEEP", "DESERT HOUSE"]),
        ("GQOM", "amapiano", 126, "drumMastery", ["amapiano", "dark", "world"], {"dark": 0.5}, ["DURBAN GQOM", "TAXI RANK"]),
        ("REGGAETON", "latin", 92, "baySlap", ["world", "trap"], {"punch": 0.4, "perc": ["CLAVE", "WOOD", "SHAKER"]}, ["PERREO", "DEMBOW HEAT", "SAN JUAN NIGHTS"]),
        ("DANCEHALL", "afrobeats", 98, "baySlap", ["world", "trap"], {"perc": ["WOOD", "HIT"]}, ["KINGSTON YARD", "RIDDIM CLASH"]),
        ("BAILE FUNK", "latin", 130, "modernTrap", ["world", "trap", "electronic"], {"punch": 0.5}, ["FAVELA FUNK", "RIO TAMBOR"]),
        ("LATIN TRAP", "trap", 140, "modernTrap", ["trap", "world"], {"long808": 0.6}, ["CALLE TRAP"]),
        ("AFROSWING", "afrobeats", 102, "westBounce", ["world", "rnb", "drill"], {"perc": ["SHAKER", "WOOD"]}, ["AFROSWING LDN", "PECKHAM"]),
    ],
    # ---------------------------------------------------------------- VINTAGE
    ("vintage", "TRAP"): [
        ("MEMPHIS TAPE", "trapMemphis", 140, "drumMastery", ["trap", "dark", "west"], {"dusty": 0.6, "perc": ["METAL", "METAL"]}, ["ORANGE MOUND", "NORTH MEMPHIS TAPE", "BASEMENT CASSETTE"]),
        ("CRUNK", "trapAtlanta", 78, "modernTrap", ["trap", "dark", "west"], {"punch": 0.3, "wide": 0.5}, ["CRUNK STOMP", "BLEACHER RATTLE"]),
        ("SNAP", "trapAtlanta", 76, "westBounce", ["trap", "west", "detroit"], {"perc": ["CLICK", "WOOD"]}, ["SNAP MUSIC", "DOWN SOUTH SNAP"]),
        ("EARLY TRAP", "trapAtlanta", 140, "modernTrap", ["trap", "dark"], {"long808": 0.6}, ["EAST ATLANTA 05", "FLIP PHONE ERA", "TRAPHOUSE TAPES"]),
        ("CHOPPED & SCREWED", "trapAtlanta", 66, "modernTrap", ["trap", "dark", "west"], {"dark": 0.6, "long808": 0.8}, ["SCREWED TAPE", "THIRD COAST CRAWL", "SLAB CRAWL"]),
        ("MIAMI BASS", "westBounce", 130, "westBounce", ["west", "electronic", "pop80"], {"long808": 1.0, "bright": 0.3}, ["OPA-LOCKA BOOM", "LIBERTY CITY 808"]),
        ("MIXTAPE TRAP", "trapAtlanta", 145, "modernTrap", ["trap", "rage", "dark"], {"long808": 0.8}, ["BLOG ERA 808", "MIXTAPE MONDAY"]),
        ("HOUSTON", "trapAtlanta", 72, "baySlap", ["trap", "west"], {"wide": 0.4}, ["H-TOWN TIPPIN", "FIFTH WARD"]),
        ("DIRTY SOUTH", "trapAtlanta", 90, "modernTrap", ["trap", "west", "funk"], {"punch": 0.3}, ["PEACH STATE 99"]),
    ],
    ("vintage", "WEST COAST"): [
        ("G-FUNK", "west90s", 95, "west90s", ["west", "funk", "90srnb"], {"wide": 0.4}, ["G-FUNK SUNDAY", "SIX FOUR IMPALA", "TALKBOX SUMMER", "LONG BEACH 93"]),
        ("LA ELECTRO", "westBounce", 120, "westBounce", ["west", "electronic", "pop80"], {"bright": 0.4}, ["ELECTRO WAVE 84", "VENICE ELECTRO", "ROLLER JAM 85"]),
        ("MOB MUSIC", "baySlap", 92, "baySlap", ["west", "funk"], {"punch": 0.4}, ["MOB MUSIC", "EAST OAKLAND 95", "RICHMOND MOB"]),
        ("WEST GANGSTA RAP", "west90s", 90, "west90s", ["west", "boombap", "funk"], {"punch": 0.3}, ["COMPTON 88", "SOUTH CENTRAL 92", "WATTS SUMMER"]),
        ("WEST FUNK", "funkBreak", 105, "funkBreak", ["funk", "west", "soul"], {"room": 0.3, "perc": ["TAMB", "SHAKER"]}, ["LOWRIDER FUNK", "HYDRAULIC FUNK"]),
        ("WEST SLOW JAM", "pop90s", 84, "west90s", ["90srnb", "west", "rnb"], {"wide": 0.4}, ["SUNSET SLOW JAM", "CRUISE NIGHT"]),
        ("WEST 2000S", "westBounce", 96, "westBounce", ["west", "pop80", "trap"], {"punch": 0.4}, ["PIANO WEST 2000", "CLUB WEST 03", "HYPHY 06"]),
    ],
    ("vintage", "SOUL & R&B"): [
        ("60S SOUL", "funkBreak", 120, "gospelChops", ["soul", "funk", "pop80"], {"room": 0.6, "perc": ["TAMB", "SHAKER"]}, ["DETROIT 1965", "TAMBOURINE SOUL"]),
        ("SOUTHERN SOUL", "funkBreak", 96, "gospelChops", ["soul", "funk"], {"room": 0.6}, ["MCLEMORE AVE", "MUSCLE SHOALS"]),
        ("PHILLY SOUL", "pop", 112, "gospelChops", ["soul", "funk", "90srnb"], {"room": 0.4, "perc": ["TAMB", "SHAKER"]}, ["BROAD STREET SOUL"]),
        ("NEW JACK SWING", "pop90s", 108, "west90s", ["90srnb", "pop80", "rnb"], {"punch": 0.4, "wide": 0.4}, ["NEW JACK 89", "SWINGBEAT 91"]),
        ("QUIET STORM", "rnb", 72, "neoSoul", ["rnb", "soul", "90srnb"], {"dark": 0.4}, ["QUIET STORM", "SLOW DANCE 84"]),
        ("GOSPEL", "gospel", 100, "gospelChops", ["soul", "rnb", "funk"], {"room": 0.6, "perc": ["TAMB"]}, ["TENT REVIVAL", "MASS CHOIR 78"]),
        ("2000S R&B", "rnb", 92, "westBounce", ["rnb", "90srnb"], {"wide": 0.3}, ["Y2K RNB"]),
    ],
    ("vintage", "BREAKS"): [
        ("FUNK BREAKS", "funkBreak", 102, "funkBreak", ["funk", "boombap", "soul"], {"room": 0.5}, ["DUSTY 45", "CRATE DIGGER", "B-SIDE BREAK"]),
        ("GOLDEN ERA", "boomBap", 94, "funkBreak", ["boombap", "funk", "soul"], {"dusty": 0.4}, ["QUEENSBRIDGE 94", "BROOKLYN 96", "BOOGIE DOWN 88"]),
        ("JAZZ BREAKS", "neoSoul", 92, "neoSoul", ["jazz", "soul", "boombap"], {"cym": "RIDE"}, ["JAZZ CELLAR", "BEBOP BREAK"]),
        ("OLD SCHOOL", "heavyBreak", 110, "heavyBreak", ["funk", "electronic", "pop80"], {"room": 0.4}, ["BLOCK PARTY 79", "PARK JAM 81"]),
        ("EARLY JUNGLE", "looseBreak", 160, "looseBreak", ["funk", "electronic", "boombap"], {"room": 0.3}, ["PIRATE RADIO 93", "RAVE TAPE 92"]),
        ("HEAVY BREAKS", "heavyBreak", 88, "heavyBreak", ["funk", "boombap", "pop80"], {"room": 1.0}, ["STAIRWELL BREAK", "WAREHOUSE BREAK"]),
    ],
    ("vintage", "POP"): [
        ("80S POP", "pop80s", 118, "west90s", ["pop80", "electronic"], {"room": 0.6}, ["GATED 85", "SYNTH ANTHEM 84", "MALL MUSIC 86"]),
        ("90S POP", "pop90s", 104, "west90s", ["90srnb", "pop80"], {"wide": 0.3}, ["BOY BAND 98", "CASSINGLE 96"]),
        ("DISCO", "pop", 120, "gospelChops", ["funk", "pop80", "soul"], {"perc": ["TAMB", "SHAKER"]}, ["MIRRORBALL 78", "HUSTLE 76", "ROLLER DISCO 79"]),
        ("60S POP", "funkBreak", 128, "gospelChops", ["soul", "pop80"], {"room": 0.6, "perc": ["TAMB"]}, ["GIRL GROUP 64", "JUKEBOX 62"]),
        ("SOFT ROCK", "pop", 96, "heavyBreak", ["pop80", "soul", "funk"], {"dark": 0.3}, ["YACHT CLUB", "SOFT ROCK 78"]),
        ("ARENA ROCK", "heavyBreak", 124, "heavyBreak", ["pop80", "funk"], {"room": 1.2}, ["POWER BALLAD 87", "ARENA 86"]),
        ("NEW WAVE", "pop80s", 128, "west90s", ["pop80", "electronic"], {"bright": 0.4}, ["NEW WAVE 82", "DRUM MACHINE 83"]),
        ("2000S POP", "pop", 100, "west90s", ["pop80", "rnb", "90srnb"], {"bright": 0.3}, ["MILLENNIUM POP", "RINGTONE 2007"]),
    ],
    ("vintage", "WORLD"): [
        ("AFROBEAT", "afrobeats", 110, "funkBreak", ["world", "funk", "soul"], {"room": 0.4, "perc": ["WOOD", "SHAKER", "METAL"]}, ["LAGOS 1975", "SHRINE NIGHTS", "HIGHLIFE BAND"]),
        ("HIGHLIFE", "afrobeats", 120, "neoSoul", ["world", "soul"], {"perc": ["METAL", "WOOD", "SHAKER"]}, ["ACCRA HIGHLIFE", "PALM WINE"]),
        ("ROOTS REGGAE", "afrobeats", 76, "neoSoul", ["world", "soul", "funk"], {"room": 0.4, "perc": ["WOOD", "CLICK"]}, ["ONE DROP", "TRENCHTOWN ROOTS", "STEPPERS DUB"]),
        ("SALSA", "latin", 100, "neoSoul", ["world", "soul", "jazz"], {"perc": ["CLAVE", "METAL", "WOOD"]}, ["NUYORICAN", "HAVANA 58", "MAMBO NIGHTS"]),
        ("BOSSA NOVA", "latin", 132, "neoSoul", ["world", "jazz", "soul"], {"cym": "RIDE", "perc": ["SHAKER", "CLAVE"]}, ["BOSSA 63", "RIO SAMBA 64"]),
        ("CUMBIA", "latin", 92, "neoSoul", ["world"], {"perc": ["SHAKER", "WOOD", "CLAVE"]}, ["CUMBIA VIEJA", "BARRANQUILLA"]),
        ("DIGITAL DANCEHALL", "afrobeats", 96, "baySlap", ["world", "electronic", "trap"], {"perc": ["WOOD", "HIT"]}, ["DIGITAL RIDDIM 85"]),
        ("RUMBA", "afrobeats", 130, "neoSoul", ["world", "amapiano"], {"perc": ["WOOD", "SHAKER"]}, ["KINSHASA RUMBA"]),
        ("KWAITO", "amapiano", 110, "modernTrap", ["amapiano", "world"], {"perc": ["SHAKER", "WOOD"]}, ["KWAITO 99"]),
        ("CALYPSO", "latin", 110, "neoSoul", ["world", "soul"], {"perc": ["METAL", "SHAKER", "TAMB"]}, ["CALYPSO 62"]),
        ("ZOUK", "afrobeats", 120, "baySlap", ["world", "pop80"], {"perc": ["SHAKER", "WOOD"]}, ["ZOUK 86"]),
    ],
    # ---------------------------------------------------------------- TEXTURE
    ("texture", "TRAP"): [
        ("CLOUD RAP", "trap", 70, "modernTrap", ["trap", "dark", "electronic"], {"dark": 0.4, "long808": 0.6}, ["CLOUD NINE", "HAZE CHAMBER", "VAPOR TRAIL"]),
        ("PLUGG", "trap", 150, "modernTrap", ["trap", "rage", "electronic"], {"perc": ["METAL", "CLICK"]}, ["PLUGG BELLS", "PLUGGNB DREAMS", "MIDNIGHT PLUGG"]),
        ("PHONK", "trapMemphis", 130, "drumMastery", ["dark", "trap", "west"], {"dusty": 0.5, "perc": ["METAL", "METAL"]}, ["DRIFT PHONK", "CHROME DRIFT", "BASEMENT PHONK"]),
        ("DARK TRAP", "trapMemphis", 140, "drumMastery", ["dark", "trap"], {"dark": 0.6}, ["HAUNTED HOUSE", "BLACK CANDLE"]),
        ("DIGICORE", "trap", 160, "modernTrap", ["rage", "electronic"], {"fx": True, "perc": ["METAL", "HIT"]}, ["DIGICORE", "GLITCH RAGE", "BITCRUSH RIOT"]),
        ("AMBIENT TRAP", "trapToronto", 130, "drumMastery", ["dark", "trap", "rnb"], {"long808": 0.8}, ["AURORA 808", "NIGHT SKY", "ICE PALACE"]),
        ("WITCH HOUSE", "experimental", 70, "looseBreak", ["dark", "electronic"], {"fx": True, "perc": ["METAL"]}, ["WITCH HOUSE", "OCCULT TAPE"]),
        ("LO-FI TRAP", "trap", 140, "modernTrap", ["trap", "dark", "soul"], {"dusty": 0.8}, ["TAPE WARP TRAP"]),
    ],
    ("texture", "WEST COAST"): [
        ("LO-FI G-FUNK", "west90s", 90, "west90s", ["west", "funk", "90srnb"], {"dusty": 0.6}, ["VHS LOWRIDER", "FADED SUNSET", "SMOG CHECK"]),
        ("LA BEAT SCENE", "experimental", 88, "looseBreak", ["electronic", "jazz", "boombap"], {"fx": True, "perc": ["HIT", "CLICK"]}, ["BEAT SCENE LA", "ECHO PARK", "HIGHLAND PARK BEATS"]),
        ("BAY HAZE", "baySlap", 85, "baySlap", ["west", "dark"], {"dark": 0.4}, ["FOG CITY", "GOLDEN GATE HAZE", "TREASURE ISLAND"]),
        ("DESERT WEST", "westBounce", 84, "westBounce", ["west", "electronic"], {"wide": 0.4}, ["MOJAVE MIRAGE", "JOSHUA TREE", "SALTON SEA", "SANTA ANA WINDS"]),
        ("SLOW CRUISE", "westBounce", 75, "west90s", ["west", "dark", "90srnb"], {"long808": 0.6}, ["SLOW CRUISE", "MIDNIGHT 405", "PALM SHADOWS"]),
        ("WEST GLITCH", "experimental", 100, "looseBreak", ["west", "electronic", "rage"], {"fx": True}, ["BROKEN HYDRAULICS", "STATIC SIGNAL"]),
        ("LO-FI MOB", "baySlap", 92, "baySlap", ["west", "funk", "dark"], {"dusty": 0.8}, ["TAPE MOB", "OAKLAND OVERCAST"]),
    ],
    ("texture", "SOUL & R&B"): [
        ("LO-FI SOUL", "loFi", 82, "neoSoul", ["soul", "jazz", "boombap"], {"dusty": 0.8}, ["RAINY WINDOW", "VINYL SKIP", "COFFEE STAIN"]),
        ("R&B HAZE", "rnb", 68, "westBounce", ["rnb", "dark", "electronic"], {"long808": 0.6}, ["UNDERWATER RNB", "NEON SMEAR"]),
        ("DREAM SOUL", "neoSoul", 78, "neoSoul", ["soul", "rnb"], {"cym": "RIDE"}, ["DAYDREAM SOUL", "SILK CLOUD", "LAVENDER"]),
        ("WARPED GOSPEL", "gospel", 90, "gospelChops", ["soul", "rnb"], {"room": 0.6, "perc": ["TAMB"]}, ["GHOST CHOIR", "CHURCH TAPE"]),
        ("JAZZ HOP", "loFi", 86, "neoSoul", ["jazz", "soul", "boombap"], {"dusty": 0.6, "cym": "RIDE"}, ["LATE NIGHT JAZZ HOP", "BRUSHES & DUST"]),
        ("CHOPPED SOUL", "neoSoul", 88, "funkBreak", ["soul", "boombap", "funk"], {"dusty": 0.6}, ["CHOPPED SOUL", "WARPED 45"]),
        ("FUTURE R&B", "rnb", 76, "westBounce", ["rnb", "electronic"], {"wide": 0.4}, ["GLASS HEART", "SATELLITE LOVE"]),
        ("AMBIENT SOUL", "neoSoul", 70, "neoSoul", ["soul", "rnb", "dark"], {"room": 0.4}, ["MOONLIT", "AFTERGLOW"]),
        ("BEDROOM SOUL", "rnb", 74, "neoSoul", ["rnb", "soul", "90srnb"], {"dusty": 0.5}, ["BEDROOM TAPES", "CASSETTE LOVE"]),
    ],
    ("texture", "BREAKS"): [
        ("LO-FI BREAKS", "loFi", 84, "funkBreak", ["boombap", "soul", "funk"], {"dusty": 0.8}, ["DUST BREAK", "WORN VINYL", "TAPE HISS BREAK"]),
        ("GLITCH BREAKS", "experimental", 140, "looseBreak", ["electronic", "rage"], {"fx": True}, ["GLITCH BREAK", "STUTTER EDIT", "DATA MOSH"]),
        ("TRIP HOP", "heavyBreak", 82, "heavyBreak", ["dark", "funk", "boombap"], {"room": 0.8}, ["TRIP HOP NOIR", "BRISTOL RAIN"]),
        ("ATMOSPHERIC DNB", "looseBreak", 172, "looseBreak", ["electronic", "dark"], {"room": 0.4}, ["ATMOSPHERIC DNB", "DEEP SPACE ROLLER"]),
        ("DUSTY BOOM BAP", "boomBap", 88, "funkBreak", ["boombap", "soul", "funk"], {"dusty": 1.0}, ["BASEMENT SP", "CRUSHED 12 BIT"]),
        ("BREAKCORE", "experimental", 180, "looseBreak", ["electronic", "rage", "dark"], {"fx": True}, ["BREAKCORE CHAOS", "BREAK SHRED"]),
        ("IDM", "experimental", 120, "looseBreak", ["electronic"], {"fx": True, "perc": ["CLICK", "METAL"]}, ["IDM CIRCUIT", "BROKEN CLOCK"]),
        ("BEAT TAPE", "boomBap", 88, "neoSoul", ["boombap", "jazz", "electronic"], {"dusty": 0.6}, ["WONKY BEAT TAPE", "DRUNK SWING"]),
        ("DUB BREAKS", "heavyBreak", 80, "heavyBreak", ["dark", "world", "funk"], {"room": 1.0}, ["DUB ECHO BREAK", "ROCKERS DUB"]),
    ],
    ("texture", "POP"): [
        ("BEDROOM POP", "pop", 96, "west90s", ["pop80", "rnb", "electronic"], {"dusty": 0.5}, ["BEDROOM POP", "POLAROID", "DIARY TAPES"]),
        ("DREAM POP", "pop", 100, "west90s", ["pop80", "electronic"], {"room": 0.8}, ["DREAM POP", "SHOEGAZE HAZE", "REVERB CASTLE"]),
        ("VAPORWAVE", "pop80s", 90, "west90s", ["pop80", "electronic"], {"room": 0.6}, ["VAPORWAVE MALL", "PLAZA 1989", "MARBLE BUST"]),
        ("SYNTHWAVE", "pop80s", 108, "west90s", ["pop80", "electronic"], {"room": 0.6, "bright": 0.3}, ["OUTRUN", "NEON GRID", "SUNSET GRID"]),
        ("GLITCH POP", "pop", 155, "modernTrap", ["electronic", "rage"], {"fx": True, "perc": ["METAL", "CLICK"]}, ["GLITTER GLITCH", "PIXEL HEART"]),
        ("CHILLWAVE", "pop", 92, "west90s", ["pop80", "electronic"], {"wide": 0.3}, ["CHILLWAVE", "BEACH DAZE"]),
        ("ART POP", "experimental", 100, "looseBreak", ["electronic", "pop80", "dark"], {"fx": True}, ["ART POP", "GLASS SCULPTURE"]),
        ("INDIE POP", "pop", 112, "heavyBreak", ["pop80", "funk"], {"room": 0.5}, ["ZINE POP"]),
        ("CITY POP", "pop80s", 110, "west90s", ["pop80", "funk", "soul"], {"perc": ["SHAKER", "TAMB"]}, ["TOKYO CITY POP"]),
    ],
    ("texture", "WORLD"): [
        ("ORGANIC HOUSE", "amapiano", 120, "neoSoul", ["amapiano", "world", "electronic"], {"perc": ["SHAKER", "WOOD", "BEADS"]}, ["ORGANIC HOUSE", "SAHARA DEEP"]),
        ("DEEP AMAPIANO", "amapiano", 112, "modernTrap", ["amapiano", "world"], {"dark": 0.3}, ["PRIVATE SCHOOL", "LOG DRUM DUB"]),
        ("DUB", "latin", 72, "neoSoul", ["world", "dark"], {"room": 1.0}, ["DUB CHAMBER", "ECHO YARD"]),
        ("DIGITAL CUMBIA", "latin", 100, "neoSoul", ["world", "electronic"], {"perc": ["SHAKER", "CLAVE", "WOOD"]}, ["DIGITAL CUMBIA", "TROPICAL HAZE"]),
        ("AFRO GLITCH", "afrobeats", 104, "baySlap", ["world", "electronic"], {"fx": True, "perc": ["WOOD", "CLICK"]}, ["AFRO GLITCH", "LAGOS STATIC"]),
        ("DARK GQOM", "amapiano", 126, "drumMastery", ["amapiano", "dark"], {"dark": 0.4}, ["DARK GQOM"]),
        ("LATIN LO-FI", "latin", 90, "neoSoul", ["world", "jazz", "soul"], {"dusty": 0.8}, ["BOSSA LO-FI", "HAVANA TAPE"]),
        ("ETHNO AMBIENT", "experimental", 90, "looseBreak", ["world", "electronic"], {"fx": True, "perc": ["BEADS", "WOOD", "SHAKER"]}, ["DESERT RITUAL"]),
    ],
}

# Live acoustic kits (Oct 18): Virtuosity Drums, multisampled with velocity layers and round robins
# (tools/build_acoustic_sounds.py). The pads named here play the acoustic drums; the clap, 808 and
# perc pads are picked from the stock sounds like every other kit.
# Each entry: (kit name, mode bank, genre tab, genre, groove style, tempo, synth voice, tags, likes, {pad: acoustic sound}).
ACOUSTIC_KITS = [
    ("SOUL SESSION", "vintage", "SOUL & R&B", "LIVE SOUL", "neoSoul", 88, "neoSoul", ["soul", "jazz", "boombap"],
     {"dusty": 0.4, "perc": ["SHAKER", "TAMB", "WOOD"]},
     {0: "VIRTUOSITY KICK", 1: "VIRTUOSITY SNARE", 3: "VIRTUOSITY CROSS STICK RIM", 4: "VIRTUOSITY HIHAT",
      5: "VIRTUOSITY HALF OPEN HIHAT", 9: "VIRTUOSITY LOW TOM", 10: "VIRTUOSITY HIGH TOM", 11: "VIRTUOSITY RIDE"}),
    ("BREAK ROOM", "vintage", "BREAKS", "LIVE BREAKS", "funkBreak", 96, "funkBreak", ["funk", "boombap", "soul"],
     {"room": 0.6, "perc": ["TAMB", "SHAKER", "CONGA"]},
     {0: "VIRTUOSITY KICK", 1: "VIRTUOSITY RIMSHOT SNARE", 3: "VIRTUOSITY OFF CENTER SNARE", 4: "VIRTUOSITY HIHAT",
      5: "VIRTUOSITY OPEN HIHAT", 9: "VIRTUOSITY LOW TOM", 10: "VIRTUOSITY HIGH TOM", 11: "VIRTUOSITY CRASH"}),
    ("STUDIO A", "modern", "POP", "LIVE ROCK", "heavyBreak", 118, "heavyBreak", ["funk", "pop80", "boombap"],
     {"bright": 0.4, "perc": ["TAMB", "SHAKER", "HIT"]},
     {0: "VIRTUOSITY KICK", 1: "VIRTUOSITY SNARE", 3: "VIRTUOSITY RIMSHOT SNARE", 4: "VIRTUOSITY HIHAT",
      5: "VIRTUOSITY OPEN HIHAT", 9: "VIRTUOSITY LOW TOM", 10: "VIRTUOSITY HIGH TOM", 11: "VIRTUOSITY CRASH"}),
]

# Tyrone's own Drum Kit as BK sounds (Oct 20, tools/build_bk_sounds.py): the first of each kind on its pad;
# the kit has no 808 and one tom, so the 808 and high tom pads are picked from the library like any kit.
EMPTY = None                                   # a pick of EMPTY: the pad plays nothing (manifest "emptyPads")
EMPTY_REST = {pad: EMPTY for pad in range(6, 12)}   # the 808, perc, tom and cymbal pads a kick-to-open-hat loop never plays
BK_KITS = [
    ("BK DRUM KIT", "modern", "TRAP", "BK", "trapAtlanta", 140, "modernTrap", ["trap", "rage", "dark"],
     {"bright": 0.4, "long808": 0.8},
     {0: "BK NO 1 KICK", 1: "BK NO 1 SNARE", 2: "BK NO 1 CLAP", 3: "BK NO 1 RIM", 4: "BK NO 1 HIHAT",
      5: "BK NO 1 OPEN HAT", 7: "BK NO 1 PERC", 8: "BK NO 2 PERC", 9: "BK NO 1 TOM", 11: "BK NO 1 CYMBAL"}),
    # Oct 20: the sounds of Tyrone's one-shot packs nearest the hits in his Drum Loops (tools/match_loop_sounds.py --bk),
    # for BK Editions Vol 3; kick and clap from his Drum Kit (the packs have none). Pads its loops don't play are EMPTY
# (None): Tyrone, Oct 20, "if a kit doesnt have 12 sounds only use the amount in that loop".
    ("BK EDITIONS KIT", "modern", "TRAP", "BK", "trapAtlanta", 130, "modernTrap", ["trap", "bounce", "dark"],
     {"bright": 0.5, "long808": 0.7},
     {0: "BK NO 7 KICK", 1: "BK NO 23 SNARE", 2: "BK NO 7 CLAP", 3: "BK NO 14 RIM", 4: "BK NO 19 HIHAT",
      5: "BK NO 14 OPEN HAT", **EMPTY_REST}),
    # Oct 20: the library and BK sounds nearest the hits in Tyrone's danger drum loops (match_loop_sounds.py, with and
    # without --bk, the nearer one per pad), for BK Editions Vol 4
    ("BK DANGER KIT", "modern", "WEST COAST", "BK", "westBounce", 94, "westBounce", ["west", "rnb", "bounce"],
     {"punch": 0.3},
     {0: "FUNK KICK", 1: "BK NO 12 SNARE", 2: "BK NO 5 CLAP", 3: "NEW LAND RIM", 4: "BK NO 20 HIHAT",
      5: "DEMON 7 OPEN HAT", **EMPTY_REST}),
]

# West Coast (Oct 20): a kit for each of the 20 West Coast presets, from the same loop of Tyrone's West Coast
# pack (tools/learn_west_coast.py: "sounds" in tools/learned_westcoast.json, the library sounds nearest to what
# the loop plays on each pad, nearest first). A pad takes the nearest sound no kit before it in this list
# has; pads the loop doesn't play are picked like any kit. The kick comes from the loop the preset takes its
# kick from when the loop has none. Each entry: (kit name, loop, the loop its kick comes from or None).
WEST_COAST_KITS = [
    ("HAWTHORNE", "BABYSTONEGORRILAS DRUMS", None),
    ("GARDENA", "BABYSTONEGORRILAS DRUMS", None),
    ("LYNWOOD", "BIGSAD1900 DRUM LOOP", None),
    ("LEIMERT PARK", "WEST COAST X LA DRUMS", None),
    ("BALDWIN HILLS", "BIGSAD1900 DRUMS", None),
    ("HYDE PARK", "BIGSAD1900 DRUMS", None),
    ("ANTIOCH", "EBK X NORCAL DRUMS", None),
    ("PARAMOUNT", "CALI DRUMS (FAVS)", None),
    ("BELLFLOWER", "CALI DRUMS (FAVS)", None),
    ("SAN PEDRO", "CALI DRUMS (FAVS)", None),
    ("EAST PALO ALTO", "EBK X NORCAL DRUMS", None),
    ("HUNTERS POINT", "EBK X NORCAL DRUMS", None),
    ("VENICE BEACH", "FILTERED LA DRUMS", "BIGSAD1900 DRUMS"),
    ("ATHENS PARK", "HIP HOP DRUMS", None),
    ("WESTMONT", "LA BLUEBUCKSCLAN DRUMS", "LA DRUMS (FAVS)"),
    ("MANCHESTER AVE", "LA DRUMS (FAVS)", None),
    ("FLORENCE AVE", "LA DRUMS (FAVS)", None),
    ("HUNTINGTON PARK", "MODERN WEST COAST DRUMS", "BIGSAD1900 DRUM LOOP"),
    ("NORWALK", "WEST COAST DRUMS (FAVS)", "WEST COAST X LA DRUMS"),
    ("RIALTO", "WEST COAST X LA DRUMS", None),
]
WEST_COAST_LOOK = ("WEST COAST", "westBounce", "westBounce", ["west", "trap", "detroit"],
                   {"wide": 0.6, "punch": 0.4, "perc": ["SHAKER", "HIT", "WOOD"]})
