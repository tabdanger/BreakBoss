// Copyright © 2026 Tyrone Dangerfield. All rights reserved.
// Made by tools/build_kits.py from the sorted stock sounds (tools/stock_sounds.json): edit that, not this.
import Foundation

extension KitLibrary {
    /// The A/B kits of the research genres, then the named kits that give every mode bank
    /// at least 20 kits under each genre tab (tools/kit_catalog.py).
    static let factory: [KitDefinition] = table(factoryTable)

    /// One kit a line: id | name | synth voice | groove style | tempo | seed | 808 Hz | mode bank | genre tab | genre.
    /// Text, not Swift calls, so the Release build stays quick with hundreds of kits.
    private static let factoryTable = """
trap-a|TRAP A|modernTrap|trapAtlanta|140|601|43.65|modern|TRAP|TRAP
trap-b|TRAP B|modernTrap|trapAtlanta|140|602|41.2|modern|TRAP|TRAP
alt-trap-a|ALT TRAP A|modernTrap|trapAtlanta|155|603|41.2|modern|TRAP|ALT TRAP
alt-trap-b|ALT TRAP B|modernTrap|trapAtlanta|155|604|43.65|modern|TRAP|ALT TRAP
drill-a|DRILL A|drumMastery|trapMemphis|140|605|41.2|modern|TRAP|DRILL
drill-b|DRILL B|drumMastery|trapMemphis|140|606|43.65|modern|TRAP|DRILL
uk-drill-a|UK DRILL A|drumMastery|trapMemphis|142|607|36.71|modern|TRAP|UK DRILL
uk-drill-b|UK DRILL B|drumMastery|trapMemphis|142|608|41.2|modern|TRAP|UK DRILL
ny-drill-a|NY DRILL A|modernTrap|trapMemphis|144|609|43.65|modern|TRAP|NY DRILL
ny-drill-b|NY DRILL B|modernTrap|trapMemphis|144|610|43.65|modern|TRAP|NY DRILL
detroit-2026-a|DETROIT 2026 A|modernTrap|trapAtlanta|96|611|41.2|modern|TRAP|DETROIT 2026
detroit-2026-b|DETROIT 2026 B|modernTrap|trapAtlanta|96|612|41.2|modern|TRAP|DETROIT 2026
bay-area-2026-a|BAY AREA 2026 A|baySlap|baySlap|100|613|51.91|modern|WEST COAST|BAY AREA 2026
bay-area-2026-b|BAY AREA 2026 B|baySlap|baySlap|100|614|49.0|modern|WEST COAST|BAY AREA 2026
rnb-a|RNB A|westBounce|rnb|76|615|38.89|modern|SOUL & R&B|RNB
rnb-b|RNB B|westBounce|rnb|76|616|36.71|modern|SOUL & R&B|RNB
uk-rnb-a|UK RNB A|westBounce|rnb|100|617|43.65|modern|SOUL & R&B|UK RNB
uk-rnb-b|UK RNB B|westBounce|rnb|100|618|49.0|modern|SOUL & R&B|UK RNB
neo-soul-a|NEO SOUL A|neoSoul|neoSoul|86|619|43.65|vintage|SOUL & R&B|NEO SOUL
neo-soul-b|NEO SOUL B|neoSoul|neoSoul|86|620|41.2|vintage|SOUL & R&B|NEO SOUL
dilla-time-a|DILLA TIME A|neoSoul|neoSoul|90|621|43.65|vintage|SOUL & R&B|DILLA TIME
dilla-time-b|DILLA TIME B|neoSoul|neoSoul|90|622|41.2|vintage|SOUL & R&B|DILLA TIME
boom-bap-a|BOOM BAP A|funkBreak|boomBap|92|623|49.0|vintage|BREAKS|BOOM BAP
boom-bap-b|BOOM BAP B|funkBreak|boomBap|92|624|41.2|vintage|BREAKS|BOOM BAP
90s-rap-a|90S RAP A|funkBreak|boomBap|94|625|36.71|vintage|BREAKS|90S RAP
90s-rap-b|90S RAP B|funkBreak|boomBap|94|626|36.71|vintage|BREAKS|90S RAP
70s-soul-a|70S SOUL A|gospelChops|funkBreak|100|627|41.2|vintage|SOUL & R&B|70S SOUL
70s-soul-b|70S SOUL B|gospelChops|funkBreak|100|628|41.2|vintage|SOUL & R&B|70S SOUL
80s-breaks-a|80S BREAKS A|heavyBreak|heavyBreak|100|629|49.0|vintage|BREAKS|80S BREAKS
80s-breaks-b|80S BREAKS B|heavyBreak|heavyBreak|100|630|41.2|vintage|BREAKS|80S BREAKS
90s-rnb-a|90S RNB A|west90s|pop90s|104|631|43.65|vintage|SOUL & R&B|90S RNB
90s-rnb-b|90S RNB B|west90s|pop90s|104|632|43.65|vintage|SOUL & R&B|90S RNB
rock-a|ROCK A|heavyBreak|heavyBreak|120|633|41.2|vintage|POP|ROCK
rock-b|ROCK B|heavyBreak|heavyBreak|120|634|41.2|vintage|POP|ROCK
afrobeats-a|AFROBEATS A|baySlap|afrobeats|106|635|46.25|texture|WORLD|AFROBEATS
afrobeats-b|AFROBEATS B|baySlap|afrobeats|106|636|41.2|texture|WORLD|AFROBEATS
amapiano-a|AMAPIANO A|modernTrap|amapiano|112|637|49.0|texture|WORLD|AMAPIANO
amapiano-b|AMAPIANO B|modernTrap|amapiano|112|638|49.0|texture|WORLD|AMAPIANO
world-perc-a|WORLD PERC A|neoSoul|latin|112|639|41.2|texture|WORLD|WORLD PERC
world-perc-b|WORLD PERC B|neoSoul|latin|112|640|36.71|texture|WORLD|WORLD PERC
fx-lab-a|FX LAB A|looseBreak|experimental|100|641|49.0|texture|FX|FX LAB
fx-lab-b|FX LAB B|looseBreak|experimental|100|642|49.0|texture|FX|FX LAB
zone-6|ZONE 6|modernTrap|trapAtlanta|142|1001|43.65|modern|TRAP|ATL TRAP
bankhead-bounce|BANKHEAD BOUNCE|modernTrap|trapAtlanta|142|1002|41.2|modern|TRAP|ATL TRAP
motion-808|MOTION 808|modernTrap|trapAtlanta|142|1003|41.2|modern|TRAP|ATL TRAP
synth-riot|SYNTH RIOT|modernTrap|trapAtlanta|160|1004|41.2|modern|TRAP|RAGE
mosh-pit|MOSH PIT|modernTrap|trapAtlanta|160|1005|41.2|modern|TRAP|RAGE
northside-fog|NORTHSIDE FOG|drumMastery|trapToronto|138|1006|41.2|modern|TRAP|TORONTO TRAP
yorkville|YORKVILLE|drumMastery|trapToronto|138|1007|43.65|modern|TRAP|TORONTO TRAP
houston-candy|HOUSTON CANDY|modernTrap|trapAtlanta|72|1008|41.2|modern|TRAP|HOUSTON TRAP
crenshaw-clap|CRENSHAW CLAP|westBounce|westBounce|98|1009|46.25|modern|WEST COAST|RATCHET
slauson-slide|SLAUSON SLIDE|westBounce|westBounce|98|1010|55.0|modern|WEST COAST|RATCHET
inglewood-heat|INGLEWOOD HEAT|westBounce|westBounce|98|1011|49.0|modern|WEST COAST|RATCHET
carson-hops|CARSON HOPS|westBounce|westBounce|98|1012|41.2|modern|WEST COAST|RATCHET
sideshow|SIDESHOW|baySlap|baySlap|100|1013|46.25|modern|WEST COAST|HYPHY
ghost-ride|GHOST RIDE|baySlap|baySlap|100|1014|49.0|modern|WEST COAST|HYPHY
yay-area-slap|YAY AREA SLAP|baySlap|baySlap|100|1015|43.65|modern|WEST COAST|HYPHY
vallejo-knock|VALLEJO KNOCK|baySlap|baySlap|100|1016|49.0|modern|WEST COAST|HYPHY
jerk-circle|JERK CIRCLE|westBounce|westBounce|100|1017|49.0|modern|WEST COAST|LA JERK
pop-lock|POP LOCK|westBounce|westBounce|100|1018|43.65|modern|WEST COAST|LA JERK
dougie-step|DOUGIE STEP|westBounce|westBounce|100|1019|36.71|modern|WEST COAST|LA JERK
palmdale-nights|PALMDALE NIGHTS|modernTrap|trapAtlanta|96|1020|43.65|modern|WEST COAST|WEST TRAP
818-valley|818 VALLEY|modernTrap|trapAtlanta|96|1021|51.91|modern|WEST COAST|WEST TRAP
pomona-dust|POMONA DUST|modernTrap|trapAtlanta|96|1022|49.0|modern|WEST COAST|WEST TRAP
pch-cruise|PCH CRUISE|west90s|westBounce|94|1023|36.71|modern|WEST COAST|NEW G-FUNK
sunset-hydraulics|SUNSET HYDRAULICS|west90s|westBounce|94|1024|55.0|modern|WEST COAST|NEW G-FUNK
chrome-spokes|CHROME SPOKES|west90s|westBounce|94|1025|55.0|modern|WEST COAST|NEW G-FUNK
lowrider-lawn|LOWRIDER LAWN|west90s|westBounce|94|1026|55.0|modern|WEST COAST|NEW G-FUNK
velvet-hours|VELVET HOURS|westBounce|rnb|70|1027|38.89|modern|SOUL & R&B|ALT R&B
after-party|AFTER PARTY|westBounce|rnb|70|1028|36.71|modern|SOUL & R&B|ALT R&B
night-drive|NIGHT DRIVE|westBounce|rnb|70|1029|36.71|modern|SOUL & R&B|ALT R&B
city-lights|CITY LIGHTS|westBounce|rnb|70|1030|43.65|modern|SOUL & R&B|ALT R&B
slow-burn|SLOW BURN|westBounce|trapSoul|68|1031|43.65|modern|SOUL & R&B|TRAP SOUL
pillow-talk|PILLOW TALK|westBounce|trapSoul|68|1032|43.65|modern|SOUL & R&B|TRAP SOUL
text-me-back|TEXT ME BACK|westBounce|trapSoul|68|1033|36.71|modern|SOUL & R&B|TRAP SOUL
sunday-service|SUNDAY SERVICE|gospelChops|gospel|104|1034|43.65|modern|SOUL & R&B|MODERN GOSPEL
choir-stand|CHOIR STAND|gospelChops|gospel|104|1035|43.65|modern|SOUL & R&B|MODERN GOSPEL
praise-break|PRAISE BREAK|gospelChops|gospel|104|1036|36.71|modern|SOUL & R&B|MODERN GOSPEL
silk-sheets|SILK SHEETS|westBounce|rnb|80|1037|43.65|modern|SOUL & R&B|BEDROOM R&B
candlelight|CANDLELIGHT|westBounce|rnb|80|1038|43.65|modern|SOUL & R&B|BEDROOM R&B
late-checkout|LATE CHECKOUT|westBounce|rnb|80|1039|36.71|modern|SOUL & R&B|BEDROOM R&B
golden-hour|GOLDEN HOUR|neoSoul|neoSoul|84|1040|36.71|modern|SOUL & R&B|NEO R&B
honey-glaze|HONEY GLAZE|neoSoul|neoSoul|84|1041|36.71|modern|SOUL & R&B|NEO R&B
soft-focus|SOFT FOCUS|neoSoul|neoSoul|84|1042|49.0|modern|SOUL & R&B|NEO R&B
liquid-roller|LIQUID ROLLER|looseBreak|looseBreak|174|1043|36.71|modern|BREAKS|DRUM & BASS
break-rush|BREAK RUSH|looseBreak|looseBreak|174|1044|36.71|modern|BREAKS|DRUM & BASS
darkside-step|DARKSIDE STEP|looseBreak|looseBreak|174|1045|43.65|modern|BREAKS|DRUM & BASS
halftime-pressure|HALFTIME PRESSURE|looseBreak|looseBreak|174|1046|43.65|modern|BREAKS|DRUM & BASS
rude-boy-jungle|RUDE BOY JUNGLE|looseBreak|looseBreak|165|1047|41.2|modern|BREAKS|JUNGLE
sound-system|SOUND SYSTEM|looseBreak|looseBreak|165|1048|41.2|modern|BREAKS|JUNGLE
dubplate|DUBPLATE|looseBreak|looseBreak|165|1049|36.71|modern|BREAKS|JUNGLE
big-beat-smash|BIG BEAT SMASH|heavyBreak|heavyBreak|128|1050|49.0|modern|BREAKS|BIG BEAT
acid-breaks|ACID BREAKS|heavyBreak|heavyBreak|128|1051|36.71|modern|BREAKS|BIG BEAT
two-step|TWO STEP|looseBreak|looseBreak|132|1052|36.71|modern|BREAKS|UK GARAGE
garage-skank|GARAGE SKANK|looseBreak|looseBreak|132|1053|36.71|modern|BREAKS|UK GARAGE
bassline-bounce|BASSLINE BOUNCE|looseBreak|looseBreak|132|1054|43.65|modern|BREAKS|UK GARAGE
concrete-boom|CONCRETE BOOM|funkBreak|boomBap|90|1055|36.71|modern|BREAKS|MODERN BOOM BAP
brick-city|BRICK CITY|funkBreak|boomBap|90|1056|36.71|modern|BREAKS|MODERN BOOM BAP
cypher-circle|CYPHER CIRCLE|funkBreak|boomBap|90|1057|41.2|modern|BREAKS|MODERN BOOM BAP
b-boy-battle|B-BOY BATTLE|funkBreak|funkBreak|112|1058|49.0|modern|BREAKS|B-BOY BREAKS
headspin|HEADSPIN|funkBreak|funkBreak|112|1059|41.2|modern|BREAKS|B-BOY BREAKS
cardboard-floor|CARDBOARD FLOOR|funkBreak|funkBreak|112|1060|36.71|modern|BREAKS|B-BOY BREAKS
footwork-juke|FOOTWORK JUKE|drumMastery|trap|160|1061|41.2|modern|BREAKS|FOOTWORK
chi-tracks|CHI TRACKS|drumMastery|trap|160|1062|41.2|modern|BREAKS|FOOTWORK
neon-club|NEON CLUB|west90s|pop|124|1063|43.65|modern|POP|DANCE POP
peak-hour|PEAK HOUR|west90s|pop|124|1064|41.2|modern|POP|DANCE POP
glitter-ball|GLITTER BALL|west90s|pop|124|1065|36.71|modern|POP|DANCE POP
radio-single|RADIO SINGLE|west90s|pop|100|1066|43.65|modern|POP|POP
chart-topper|CHART TOPPER|west90s|pop|100|1067|41.2|modern|POP|POP
hook-first|HOOK FIRST|west90s|pop|100|1068|43.65|modern|POP|POP
stadium-clap|STADIUM CLAP|west90s|pop|100|1069|41.2|modern|POP|POP
bubblegum-glitch|BUBBLEGUM GLITCH|modernTrap|pop|160|1070|51.91|modern|POP|HYPERPOP
sugar-crash|SUGAR CRASH|modernTrap|pop|160|1071|41.2|modern|POP|HYPERPOP
chrome-heart|CHROME HEART|west90s|pop80s|118|1072|41.2|modern|POP|ELECTROPOP
laser-glow|LASER GLOW|west90s|pop80s|118|1073|36.71|modern|POP|ELECTROPOP
diamond-hook|DIAMOND HOOK|modernTrap|trap|140|1074|43.65|modern|POP|POP TRAP
viral-bounce|VIRAL BOUNCE|modernTrap|trap|140|1075|43.65|modern|POP|POP TRAP
arena-anthem|ARENA ANTHEM|heavyBreak|heavyBreak|120|1076|41.2|modern|POP|POP ROCK
tailgate|TAILGATE|heavyBreak|heavyBreak|120|1077|46.25|modern|POP|POP ROCK
idol-stage|IDOL STAGE|modernTrap|pop|120|1078|49.0|modern|POP|K-POP
comeback-show|COMEBACK SHOW|modernTrap|pop|120|1079|49.0|modern|POP|K-POP
mirror-disco|MIRROR DISCO|west90s|pop|116|1080|41.2|modern|POP|DISCO POP
roller-rink|ROLLER RINK|west90s|pop|116|1081|41.2|modern|POP|DISCO POP
velvet-rope|VELVET ROPE|west90s|pop|116|1082|46.25|modern|POP|DISCO POP
lagos-lights|LAGOS LIGHTS|baySlap|afrobeats|104|1083|41.2|modern|WORLD|AFROBEATS
lekki-nights|LEKKI NIGHTS|baySlap|afrobeats|104|1084|41.2|modern|WORLD|AFROBEATS
owambe|OWAMBE|baySlap|afrobeats|104|1085|49.0|modern|WORLD|AFROBEATS
log-drum-sunday|LOG DRUM SUNDAY|modernTrap|amapiano|113|1086|46.25|modern|WORLD|AMAPIANO
soweto-shuffle|SOWETO SHUFFLE|modernTrap|amapiano|113|1087|41.2|modern|WORLD|AMAPIANO
pretoria-groove|PRETORIA GROOVE|modernTrap|amapiano|113|1088|46.25|modern|WORLD|AMAPIANO
joburg-deep|JOBURG DEEP|modernTrap|amapiano|122|1089|49.0|modern|WORLD|AFRO HOUSE
desert-house|DESERT HOUSE|modernTrap|amapiano|122|1090|41.2|modern|WORLD|AFRO HOUSE
durban-gqom|DURBAN GQOM|drumMastery|amapiano|126|1091|36.71|modern|WORLD|GQOM
taxi-rank|TAXI RANK|drumMastery|amapiano|126|1092|36.71|modern|WORLD|GQOM
perreo|PERREO|baySlap|latin|92|1093|46.25|modern|WORLD|REGGAETON
dembow-heat|DEMBOW HEAT|baySlap|latin|92|1094|41.2|modern|WORLD|REGGAETON
san-juan-nights|SAN JUAN NIGHTS|baySlap|latin|92|1095|41.2|modern|WORLD|REGGAETON
kingston-yard|KINGSTON YARD|baySlap|afrobeats|98|1096|46.25|modern|WORLD|DANCEHALL
riddim-clash|RIDDIM CLASH|baySlap|afrobeats|98|1097|41.2|modern|WORLD|DANCEHALL
favela-funk|FAVELA FUNK|modernTrap|latin|130|1098|49.0|modern|WORLD|BAILE FUNK
rio-tambor|RIO TAMBOR|modernTrap|latin|130|1099|41.2|modern|WORLD|BAILE FUNK
calle-trap|CALLE TRAP|modernTrap|trap|140|1100|43.65|modern|WORLD|LATIN TRAP
afroswing-ldn|AFROSWING LDN|westBounce|afrobeats|102|1101|36.71|modern|WORLD|AFROSWING
peckham|PECKHAM|westBounce|afrobeats|102|1102|36.71|modern|WORLD|AFROSWING
orange-mound|ORANGE MOUND|drumMastery|trapMemphis|140|1103|43.65|vintage|TRAP|MEMPHIS TAPE
north-memphis-tape|NORTH MEMPHIS TAPE|drumMastery|trapMemphis|140|1104|41.2|vintage|TRAP|MEMPHIS TAPE
basement-cassette|BASEMENT CASSETTE|drumMastery|trapMemphis|140|1105|36.71|vintage|TRAP|MEMPHIS TAPE
crunk-stomp|CRUNK STOMP|modernTrap|trapAtlanta|78|1106|43.65|vintage|TRAP|CRUNK
bleacher-rattle|BLEACHER RATTLE|modernTrap|trapAtlanta|78|1107|36.71|vintage|TRAP|CRUNK
snap-music|SNAP MUSIC|westBounce|trapAtlanta|76|1108|41.2|vintage|TRAP|SNAP
down-south-snap|DOWN SOUTH SNAP|westBounce|trapAtlanta|76|1109|41.2|vintage|TRAP|SNAP
east-atlanta-05|EAST ATLANTA 05|modernTrap|trapAtlanta|140|1110|43.65|vintage|TRAP|EARLY TRAP
flip-phone-era|FLIP PHONE ERA|modernTrap|trapAtlanta|140|1111|41.2|vintage|TRAP|EARLY TRAP
traphouse-tapes|TRAPHOUSE TAPES|modernTrap|trapAtlanta|140|1112|36.71|vintage|TRAP|EARLY TRAP
screwed-tape|SCREWED TAPE|modernTrap|trapAtlanta|66|1113|43.65|vintage|TRAP|CHOPPED & SCREWED
third-coast-crawl|THIRD COAST CRAWL|modernTrap|trapAtlanta|66|1114|43.65|vintage|TRAP|CHOPPED & SCREWED
slab-crawl|SLAB CRAWL|modernTrap|trapAtlanta|66|1115|41.2|vintage|TRAP|CHOPPED & SCREWED
opa-locka-boom|OPA-LOCKA BOOM|westBounce|westBounce|130|1116|49.0|vintage|TRAP|MIAMI BASS
liberty-city-808|LIBERTY CITY 808|westBounce|westBounce|130|1117|43.65|vintage|TRAP|MIAMI BASS
blog-era-808|BLOG ERA 808|modernTrap|trapAtlanta|145|1118|51.91|vintage|TRAP|MIXTAPE TRAP
mixtape-monday|MIXTAPE MONDAY|modernTrap|trapAtlanta|145|1119|41.2|vintage|TRAP|MIXTAPE TRAP
h-town-tippin|H-TOWN TIPPIN|baySlap|trapAtlanta|72|1120|43.65|vintage|TRAP|HOUSTON
fifth-ward|FIFTH WARD|baySlap|trapAtlanta|72|1121|51.91|vintage|TRAP|HOUSTON
peach-state-99|PEACH STATE 99|modernTrap|trapAtlanta|90|1122|49.0|vintage|TRAP|DIRTY SOUTH
g-funk-sunday|G-FUNK SUNDAY|west90s|west90s|95|1123|49.0|vintage|WEST COAST|G-FUNK
six-four-impala|SIX FOUR IMPALA|west90s|west90s|95|1124|55.0|vintage|WEST COAST|G-FUNK
talkbox-summer|TALKBOX SUMMER|west90s|west90s|95|1125|49.0|vintage|WEST COAST|G-FUNK
long-beach-93|LONG BEACH 93|west90s|west90s|95|1126|46.25|vintage|WEST COAST|G-FUNK
electro-wave-84|ELECTRO WAVE 84|westBounce|westBounce|120|1127|49.0|vintage|WEST COAST|LA ELECTRO
venice-electro|VENICE ELECTRO|westBounce|westBounce|120|1128|36.71|vintage|WEST COAST|LA ELECTRO
roller-jam-85|ROLLER JAM 85|westBounce|westBounce|120|1129|36.71|vintage|WEST COAST|LA ELECTRO
mob-music|MOB MUSIC|baySlap|baySlap|92|1130|49.0|vintage|WEST COAST|MOB MUSIC
east-oakland-95|EAST OAKLAND 95|baySlap|baySlap|92|1131|51.91|vintage|WEST COAST|MOB MUSIC
richmond-mob|RICHMOND MOB|baySlap|baySlap|92|1132|49.0|vintage|WEST COAST|MOB MUSIC
compton-88|COMPTON 88|west90s|west90s|90|1133|49.0|vintage|WEST COAST|WEST GANGSTA RAP
south-central-92|SOUTH CENTRAL 92|west90s|west90s|90|1134|43.65|vintage|WEST COAST|WEST GANGSTA RAP
watts-summer|WATTS SUMMER|west90s|west90s|90|1135|36.71|vintage|WEST COAST|WEST GANGSTA RAP
lowrider-funk|LOWRIDER FUNK|funkBreak|funkBreak|105|1136|36.71|vintage|WEST COAST|WEST FUNK
hydraulic-funk|HYDRAULIC FUNK|funkBreak|funkBreak|105|1137|49.0|vintage|WEST COAST|WEST FUNK
sunset-slow-jam|SUNSET SLOW JAM|west90s|pop90s|84|1138|43.65|vintage|WEST COAST|WEST SLOW JAM
cruise-night|CRUISE NIGHT|west90s|pop90s|84|1139|55.0|vintage|WEST COAST|WEST SLOW JAM
piano-west-2000|PIANO WEST 2000|westBounce|westBounce|96|1140|49.0|vintage|WEST COAST|WEST 2000S
club-west-03|CLUB WEST 03|westBounce|westBounce|96|1141|43.65|vintage|WEST COAST|WEST 2000S
hyphy-06|HYPHY 06|westBounce|westBounce|96|1142|46.25|vintage|WEST COAST|WEST 2000S
detroit-1965|DETROIT 1965|gospelChops|funkBreak|120|1143|43.65|vintage|SOUL & R&B|60S SOUL
tambourine-soul|TAMBOURINE SOUL|gospelChops|funkBreak|120|1144|36.71|vintage|SOUL & R&B|60S SOUL
mclemore-ave|MCLEMORE AVE|gospelChops|funkBreak|96|1145|36.71|vintage|SOUL & R&B|SOUTHERN SOUL
muscle-shoals|MUSCLE SHOALS|gospelChops|funkBreak|96|1146|36.71|vintage|SOUL & R&B|SOUTHERN SOUL
broad-street-soul|BROAD STREET SOUL|gospelChops|pop|112|1147|41.2|vintage|SOUL & R&B|PHILLY SOUL
new-jack-89|NEW JACK 89|west90s|pop90s|108|1148|55.0|vintage|SOUL & R&B|NEW JACK SWING
swingbeat-91|SWINGBEAT 91|west90s|pop90s|108|1149|41.2|vintage|SOUL & R&B|NEW JACK SWING
quiet-storm|QUIET STORM|neoSoul|rnb|72|1150|43.65|vintage|SOUL & R&B|QUIET STORM
slow-dance-84|SLOW DANCE 84|neoSoul|rnb|72|1151|36.71|vintage|SOUL & R&B|QUIET STORM
tent-revival|TENT REVIVAL|gospelChops|gospel|100|1152|43.65|vintage|SOUL & R&B|GOSPEL
mass-choir-78|MASS CHOIR 78|gospelChops|gospel|100|1153|36.71|vintage|SOUL & R&B|GOSPEL
y2k-rnb|Y2K RNB|westBounce|rnb|92|1154|43.65|vintage|SOUL & R&B|2000S R&B
dusty-45|DUSTY 45|funkBreak|funkBreak|102|1155|49.0|vintage|BREAKS|FUNK BREAKS
crate-digger|CRATE DIGGER|funkBreak|funkBreak|102|1156|41.2|vintage|BREAKS|FUNK BREAKS
b-side-break|B-SIDE BREAK|funkBreak|funkBreak|102|1157|36.71|vintage|BREAKS|FUNK BREAKS
queensbridge-94|QUEENSBRIDGE 94|funkBreak|boomBap|94|1158|43.65|vintage|BREAKS|GOLDEN ERA
brooklyn-96|BROOKLYN 96|funkBreak|boomBap|94|1159|41.2|vintage|BREAKS|GOLDEN ERA
boogie-down-88|BOOGIE DOWN 88|funkBreak|boomBap|94|1160|36.71|vintage|BREAKS|GOLDEN ERA
jazz-cellar|JAZZ CELLAR|neoSoul|neoSoul|92|1161|49.0|vintage|BREAKS|JAZZ BREAKS
bebop-break|BEBOP BREAK|neoSoul|neoSoul|92|1162|49.0|vintage|BREAKS|JAZZ BREAKS
block-party-79|BLOCK PARTY 79|heavyBreak|heavyBreak|110|1163|49.0|vintage|BREAKS|OLD SCHOOL
park-jam-81|PARK JAM 81|heavyBreak|heavyBreak|110|1164|43.65|vintage|BREAKS|OLD SCHOOL
pirate-radio-93|PIRATE RADIO 93|looseBreak|looseBreak|160|1165|36.71|vintage|BREAKS|EARLY JUNGLE
rave-tape-92|RAVE TAPE 92|looseBreak|looseBreak|160|1166|36.71|vintage|BREAKS|EARLY JUNGLE
stairwell-break|STAIRWELL BREAK|heavyBreak|heavyBreak|88|1167|41.2|vintage|BREAKS|HEAVY BREAKS
warehouse-break|WAREHOUSE BREAK|heavyBreak|heavyBreak|88|1168|41.2|vintage|BREAKS|HEAVY BREAKS
gated-85|GATED 85|west90s|pop80s|118|1169|43.65|vintage|POP|80S POP
synth-anthem-84|SYNTH ANTHEM 84|west90s|pop80s|118|1170|43.65|vintage|POP|80S POP
mall-music-86|MALL MUSIC 86|west90s|pop80s|118|1171|36.71|vintage|POP|80S POP
boy-band-98|BOY BAND 98|west90s|pop90s|104|1172|55.0|vintage|POP|90S POP
cassingle-96|CASSINGLE 96|west90s|pop90s|104|1173|41.2|vintage|POP|90S POP
mirrorball-78|MIRRORBALL 78|gospelChops|pop|120|1174|41.2|vintage|POP|DISCO
hustle-76|HUSTLE 76|gospelChops|pop|120|1175|41.2|vintage|POP|DISCO
roller-disco-79|ROLLER DISCO 79|gospelChops|pop|120|1176|36.71|vintage|POP|DISCO
girl-group-64|GIRL GROUP 64|gospelChops|funkBreak|128|1177|49.0|vintage|POP|60S POP
jukebox-62|JUKEBOX 62|gospelChops|funkBreak|128|1178|36.71|vintage|POP|60S POP
yacht-club|YACHT CLUB|heavyBreak|pop|96|1179|36.71|vintage|POP|SOFT ROCK
soft-rock-78|SOFT ROCK 78|heavyBreak|pop|96|1180|36.71|vintage|POP|SOFT ROCK
power-ballad-87|POWER BALLAD 87|heavyBreak|heavyBreak|124|1181|41.2|vintage|POP|ARENA ROCK
arena-86|ARENA 86|heavyBreak|heavyBreak|124|1182|41.2|vintage|POP|ARENA ROCK
new-wave-82|NEW WAVE 82|west90s|pop80s|128|1183|41.2|vintage|POP|NEW WAVE
drum-machine-83|DRUM MACHINE 83|west90s|pop80s|128|1184|41.2|vintage|POP|NEW WAVE
millennium-pop|MILLENNIUM POP|west90s|pop|100|1185|43.65|vintage|POP|2000S POP
ringtone-2007|RINGTONE 2007|west90s|pop|100|1186|36.71|vintage|POP|2000S POP
lagos-1975|LAGOS 1975|funkBreak|afrobeats|110|1187|41.2|vintage|WORLD|AFROBEAT
shrine-nights|SHRINE NIGHTS|funkBreak|afrobeats|110|1188|46.25|vintage|WORLD|AFROBEAT
highlife-band|HIGHLIFE BAND|funkBreak|afrobeats|110|1189|41.2|vintage|WORLD|AFROBEAT
accra-highlife|ACCRA HIGHLIFE|neoSoul|afrobeats|120|1190|49.0|vintage|WORLD|HIGHLIFE
palm-wine|PALM WINE|neoSoul|afrobeats|120|1191|49.0|vintage|WORLD|HIGHLIFE
one-drop|ONE DROP|neoSoul|afrobeats|76|1192|41.2|vintage|WORLD|ROOTS REGGAE
trenchtown-roots|TRENCHTOWN ROOTS|neoSoul|afrobeats|76|1193|36.71|vintage|WORLD|ROOTS REGGAE
steppers-dub|STEPPERS DUB|neoSoul|afrobeats|76|1194|43.65|vintage|WORLD|ROOTS REGGAE
nuyorican|NUYORICAN|neoSoul|latin|100|1195|49.0|vintage|WORLD|SALSA
havana-58|HAVANA 58|neoSoul|latin|100|1196|36.71|vintage|WORLD|SALSA
mambo-nights|MAMBO NIGHTS|neoSoul|latin|100|1197|43.65|vintage|WORLD|SALSA
bossa-63|BOSSA 63|neoSoul|latin|132|1198|49.0|vintage|WORLD|BOSSA NOVA
rio-samba-64|RIO SAMBA 64|neoSoul|latin|132|1199|49.0|vintage|WORLD|BOSSA NOVA
cumbia-vieja|CUMBIA VIEJA|neoSoul|latin|92|1200|46.25|vintage|WORLD|CUMBIA
barranquilla|BARRANQUILLA|neoSoul|latin|92|1201|41.2|vintage|WORLD|CUMBIA
digital-riddim-85|DIGITAL RIDDIM 85|baySlap|afrobeats|96|1202|36.71|vintage|WORLD|DIGITAL DANCEHALL
kinshasa-rumba|KINSHASA RUMBA|neoSoul|afrobeats|130|1203|49.0|vintage|WORLD|RUMBA
kwaito-99|KWAITO 99|modernTrap|amapiano|110|1204|46.25|vintage|WORLD|KWAITO
calypso-62|CALYPSO 62|neoSoul|latin|110|1205|36.71|vintage|WORLD|CALYPSO
zouk-86|ZOUK 86|baySlap|afrobeats|120|1206|36.71|vintage|WORLD|ZOUK
cloud-nine|CLOUD NINE|modernTrap|trap|70|1207|43.65|texture|TRAP|CLOUD RAP
haze-chamber|HAZE CHAMBER|modernTrap|trap|70|1208|36.71|texture|TRAP|CLOUD RAP
vapor-trail|VAPOR TRAIL|modernTrap|trap|70|1209|43.65|texture|TRAP|CLOUD RAP
plugg-bells|PLUGG BELLS|modernTrap|trap|150|1210|51.91|texture|TRAP|PLUGG
pluggnb-dreams|PLUGGNB DREAMS|modernTrap|trap|150|1211|41.2|texture|TRAP|PLUGG
midnight-plugg|MIDNIGHT PLUGG|modernTrap|trap|150|1212|41.2|texture|TRAP|PLUGG
drift-phonk|DRIFT PHONK|drumMastery|trapMemphis|130|1213|36.71|texture|TRAP|PHONK
chrome-drift|CHROME DRIFT|drumMastery|trapMemphis|130|1214|36.71|texture|TRAP|PHONK
basement-phonk|BASEMENT PHONK|drumMastery|trapMemphis|130|1215|41.2|texture|TRAP|PHONK
haunted-house|HAUNTED HOUSE|drumMastery|trapMemphis|140|1216|36.71|texture|TRAP|DARK TRAP
black-candle|BLACK CANDLE|drumMastery|trapMemphis|140|1217|36.71|texture|TRAP|DARK TRAP
digicore|DIGICORE|modernTrap|trap|160|1218|49.0|texture|TRAP|DIGICORE
glitch-rage|GLITCH RAGE|modernTrap|trap|160|1219|41.2|texture|TRAP|DIGICORE
bitcrush-riot|BITCRUSH RIOT|modernTrap|trap|160|1220|51.91|texture|TRAP|DIGICORE
aurora-808|AURORA 808|drumMastery|trapToronto|130|1221|38.89|texture|TRAP|AMBIENT TRAP
night-sky|NIGHT SKY|drumMastery|trapToronto|130|1222|36.71|texture|TRAP|AMBIENT TRAP
ice-palace|ICE PALACE|drumMastery|trapToronto|130|1223|43.65|texture|TRAP|AMBIENT TRAP
witch-house|WITCH HOUSE|looseBreak|experimental|70|1224|36.71|texture|TRAP|WITCH HOUSE
occult-tape|OCCULT TAPE|looseBreak|experimental|70|1225|36.71|texture|TRAP|WITCH HOUSE
tape-warp-trap|TAPE WARP TRAP|modernTrap|trap|140|1226|41.2|texture|TRAP|LO-FI TRAP
vhs-lowrider|VHS LOWRIDER|west90s|west90s|90|1227|55.0|texture|WEST COAST|LO-FI G-FUNK
faded-sunset|FADED SUNSET|west90s|west90s|90|1228|55.0|texture|WEST COAST|LO-FI G-FUNK
smog-check|SMOG CHECK|west90s|west90s|90|1229|43.65|texture|WEST COAST|LO-FI G-FUNK
beat-scene-la|BEAT SCENE LA|looseBreak|experimental|88|1230|49.0|texture|WEST COAST|LA BEAT SCENE
echo-park|ECHO PARK|looseBreak|experimental|88|1231|43.65|texture|WEST COAST|LA BEAT SCENE
highland-park-beats|HIGHLAND PARK BEATS|looseBreak|experimental|88|1232|43.65|texture|WEST COAST|LA BEAT SCENE
fog-city|FOG CITY|baySlap|baySlap|85|1233|49.0|texture|WEST COAST|BAY HAZE
golden-gate-haze|GOLDEN GATE HAZE|baySlap|baySlap|85|1234|46.25|texture|WEST COAST|BAY HAZE
treasure-island|TREASURE ISLAND|baySlap|baySlap|85|1235|51.91|texture|WEST COAST|BAY HAZE
mojave-mirage|MOJAVE MIRAGE|westBounce|westBounce|84|1236|49.0|texture|WEST COAST|DESERT WEST
joshua-tree|JOSHUA TREE|westBounce|westBounce|84|1237|49.0|texture|WEST COAST|DESERT WEST
salton-sea|SALTON SEA|westBounce|westBounce|84|1238|55.0|texture|WEST COAST|DESERT WEST
santa-ana-winds|SANTA ANA WINDS|westBounce|westBounce|84|1239|49.0|texture|WEST COAST|DESERT WEST
slow-cruise|SLOW CRUISE|west90s|westBounce|75|1240|43.65|texture|WEST COAST|SLOW CRUISE
midnight-405|MIDNIGHT 405|west90s|westBounce|75|1241|55.0|texture|WEST COAST|SLOW CRUISE
palm-shadows|PALM SHADOWS|west90s|westBounce|75|1242|41.2|texture|WEST COAST|SLOW CRUISE
broken-hydraulics|BROKEN HYDRAULICS|looseBreak|experimental|100|1243|49.0|texture|WEST COAST|WEST GLITCH
static-signal|STATIC SIGNAL|looseBreak|experimental|100|1244|43.65|texture|WEST COAST|WEST GLITCH
tape-mob|TAPE MOB|baySlap|baySlap|92|1245|46.25|texture|WEST COAST|LO-FI MOB
oakland-overcast|OAKLAND OVERCAST|baySlap|baySlap|92|1246|49.0|texture|WEST COAST|LO-FI MOB
rainy-window|RAINY WINDOW|neoSoul|loFi|82|1247|43.65|texture|SOUL & R&B|LO-FI SOUL
vinyl-skip|VINYL SKIP|neoSoul|loFi|82|1248|36.71|texture|SOUL & R&B|LO-FI SOUL
coffee-stain|COFFEE STAIN|neoSoul|loFi|82|1249|43.65|texture|SOUL & R&B|LO-FI SOUL
underwater-rnb|UNDERWATER RNB|westBounce|rnb|68|1250|36.71|texture|SOUL & R&B|R&B HAZE
neon-smear|NEON SMEAR|westBounce|rnb|68|1251|38.89|texture|SOUL & R&B|R&B HAZE
daydream-soul|DAYDREAM SOUL|neoSoul|neoSoul|78|1252|43.65|texture|SOUL & R&B|DREAM SOUL
silk-cloud|SILK CLOUD|neoSoul|neoSoul|78|1253|36.71|texture|SOUL & R&B|DREAM SOUL
lavender|LAVENDER|neoSoul|neoSoul|78|1254|36.71|texture|SOUL & R&B|DREAM SOUL
ghost-choir|GHOST CHOIR|gospelChops|gospel|90|1255|43.65|texture|SOUL & R&B|WARPED GOSPEL
church-tape|CHURCH TAPE|gospelChops|gospel|90|1256|36.71|texture|SOUL & R&B|WARPED GOSPEL
late-night-jazz-hop|LATE NIGHT JAZZ HOP|neoSoul|loFi|86|1257|49.0|texture|SOUL & R&B|JAZZ HOP
brushes-and-dust|BRUSHES & DUST|neoSoul|loFi|86|1258|43.65|texture|SOUL & R&B|JAZZ HOP
chopped-soul|CHOPPED SOUL|funkBreak|neoSoul|88|1259|41.2|texture|SOUL & R&B|CHOPPED SOUL
warped-45|WARPED 45|funkBreak|neoSoul|88|1260|43.65|texture|SOUL & R&B|CHOPPED SOUL
glass-heart|GLASS HEART|westBounce|rnb|76|1261|36.71|texture|SOUL & R&B|FUTURE R&B
satellite-love|SATELLITE LOVE|westBounce|rnb|76|1262|43.65|texture|SOUL & R&B|FUTURE R&B
moonlit|MOONLIT|neoSoul|neoSoul|70|1263|49.0|texture|SOUL & R&B|AMBIENT SOUL
afterglow|AFTERGLOW|neoSoul|neoSoul|70|1264|43.65|texture|SOUL & R&B|AMBIENT SOUL
bedroom-tapes|BEDROOM TAPES|neoSoul|rnb|74|1265|43.65|texture|SOUL & R&B|BEDROOM SOUL
cassette-love|CASSETTE LOVE|neoSoul|rnb|74|1266|36.71|texture|SOUL & R&B|BEDROOM SOUL
dust-break|DUST BREAK|funkBreak|loFi|84|1267|36.71|texture|BREAKS|LO-FI BREAKS
worn-vinyl|WORN VINYL|funkBreak|loFi|84|1268|41.2|texture|BREAKS|LO-FI BREAKS
tape-hiss-break|TAPE HISS BREAK|funkBreak|loFi|84|1269|36.71|texture|BREAKS|LO-FI BREAKS
glitch-break|GLITCH BREAK|looseBreak|experimental|140|1270|41.2|texture|BREAKS|GLITCH BREAKS
stutter-edit|STUTTER EDIT|looseBreak|experimental|140|1271|43.65|texture|BREAKS|GLITCH BREAKS
data-mosh|DATA MOSH|looseBreak|experimental|140|1272|41.2|texture|BREAKS|GLITCH BREAKS
trip-hop-noir|TRIP HOP NOIR|heavyBreak|heavyBreak|82|1273|36.71|texture|BREAKS|TRIP HOP
bristol-rain|BRISTOL RAIN|heavyBreak|heavyBreak|82|1274|36.71|texture|BREAKS|TRIP HOP
atmospheric-dnb|ATMOSPHERIC DNB|looseBreak|looseBreak|172|1275|43.65|texture|BREAKS|ATMOSPHERIC DNB
deep-space-roller|DEEP SPACE ROLLER|looseBreak|looseBreak|172|1276|36.71|texture|BREAKS|ATMOSPHERIC DNB
basement-sp|BASEMENT SP|funkBreak|boomBap|88|1277|49.0|texture|BREAKS|DUSTY BOOM BAP
crushed-12-bit|CRUSHED 12 BIT|funkBreak|boomBap|88|1278|36.71|texture|BREAKS|DUSTY BOOM BAP
breakcore-chaos|BREAKCORE CHAOS|looseBreak|experimental|180|1279|49.0|texture|BREAKS|BREAKCORE
break-shred|BREAK SHRED|looseBreak|experimental|180|1280|49.0|texture|BREAKS|BREAKCORE
idm-circuit|IDM CIRCUIT|looseBreak|experimental|120|1281|36.71|texture|BREAKS|IDM
broken-clock|BROKEN CLOCK|looseBreak|experimental|120|1282|36.71|texture|BREAKS|IDM
wonky-beat-tape|WONKY BEAT TAPE|neoSoul|boomBap|88|1283|41.2|texture|BREAKS|BEAT TAPE
drunk-swing|DRUNK SWING|neoSoul|boomBap|88|1284|41.2|texture|BREAKS|BEAT TAPE
dub-echo-break|DUB ECHO BREAK|heavyBreak|heavyBreak|80|1285|36.71|texture|BREAKS|DUB BREAKS
rockers-dub|ROCKERS DUB|heavyBreak|heavyBreak|80|1286|41.2|texture|BREAKS|DUB BREAKS
bedroom-pop|BEDROOM POP|west90s|pop|96|1287|43.65|texture|POP|BEDROOM POP
polaroid|POLAROID|west90s|pop|96|1288|41.2|texture|POP|BEDROOM POP
diary-tapes|DIARY TAPES|west90s|pop|96|1289|43.65|texture|POP|BEDROOM POP
dream-pop|DREAM POP|west90s|pop|100|1290|36.71|texture|POP|DREAM POP
shoegaze-haze|SHOEGAZE HAZE|west90s|pop|100|1291|41.2|texture|POP|DREAM POP
reverb-castle|REVERB CASTLE|west90s|pop|100|1292|41.2|texture|POP|DREAM POP
vaporwave-mall|VAPORWAVE MALL|west90s|pop80s|90|1293|43.65|texture|POP|VAPORWAVE
plaza-1989|PLAZA 1989|west90s|pop80s|90|1294|41.2|texture|POP|VAPORWAVE
marble-bust|MARBLE BUST|west90s|pop80s|90|1295|41.2|texture|POP|VAPORWAVE
outrun|OUTRUN|west90s|pop80s|108|1296|41.2|texture|POP|SYNTHWAVE
neon-grid|NEON GRID|west90s|pop80s|108|1297|41.2|texture|POP|SYNTHWAVE
sunset-grid|SUNSET GRID|west90s|pop80s|108|1298|49.0|texture|POP|SYNTHWAVE
glitter-glitch|GLITTER GLITCH|modernTrap|pop|155|1299|41.2|texture|POP|GLITCH POP
pixel-heart|PIXEL HEART|modernTrap|pop|155|1300|36.71|texture|POP|GLITCH POP
chillwave|CHILLWAVE|west90s|pop|92|1301|55.0|texture|POP|CHILLWAVE
beach-daze|BEACH DAZE|west90s|pop|92|1302|46.25|texture|POP|CHILLWAVE
art-pop|ART POP|looseBreak|experimental|100|1303|43.65|texture|POP|ART POP
glass-sculpture|GLASS SCULPTURE|looseBreak|experimental|100|1304|36.71|texture|POP|ART POP
zine-pop|ZINE POP|heavyBreak|pop|112|1305|41.2|texture|POP|INDIE POP
tokyo-city-pop|TOKYO CITY POP|west90s|pop80s|110|1306|41.2|texture|POP|CITY POP
organic-house|ORGANIC HOUSE|neoSoul|amapiano|120|1307|49.0|texture|WORLD|ORGANIC HOUSE
sahara-deep|SAHARA DEEP|neoSoul|amapiano|120|1308|46.25|texture|WORLD|ORGANIC HOUSE
private-school|PRIVATE SCHOOL|modernTrap|amapiano|112|1309|46.25|texture|WORLD|DEEP AMAPIANO
log-drum-dub|LOG DRUM DUB|modernTrap|amapiano|112|1310|49.0|texture|WORLD|DEEP AMAPIANO
dub-chamber|DUB CHAMBER|neoSoul|latin|72|1311|41.2|texture|WORLD|DUB
echo-yard|ECHO YARD|neoSoul|latin|72|1312|41.2|texture|WORLD|DUB
digital-cumbia|DIGITAL CUMBIA|neoSoul|latin|100|1313|41.2|texture|WORLD|DIGITAL CUMBIA
tropical-haze|TROPICAL HAZE|neoSoul|latin|100|1314|46.25|texture|WORLD|DIGITAL CUMBIA
afro-glitch|AFRO GLITCH|baySlap|afrobeats|104|1315|43.65|texture|WORLD|AFRO GLITCH
lagos-static|LAGOS STATIC|baySlap|afrobeats|104|1316|41.2|texture|WORLD|AFRO GLITCH
dark-gqom|DARK GQOM|drumMastery|amapiano|126|1317|46.25|texture|WORLD|DARK GQOM
bossa-lo-fi|BOSSA LO-FI|neoSoul|latin|90|1318|49.0|texture|WORLD|LATIN LO-FI
havana-tape|HAVANA TAPE|neoSoul|latin|90|1319|49.0|texture|WORLD|LATIN LO-FI
desert-ritual|DESERT RITUAL|looseBreak|experimental|90|1320|43.65|texture|WORLD|ETHNO AMBIENT
soul-session|SOUL SESSION|neoSoul|neoSoul|88|1321|43.65|vintage|SOUL & R&B|LIVE SOUL
break-room|BREAK ROOM|funkBreak|funkBreak|96|1322|41.2|vintage|BREAKS|LIVE BREAKS
studio-a|STUDIO A|heavyBreak|heavyBreak|118|1323|41.2|modern|POP|LIVE ROCK
bk-drum-kit|BK DRUM KIT|modernTrap|trapAtlanta|140|1324|43.65|modern|TRAP|BK
bk-editions-kit|BK EDITIONS KIT|modernTrap|trapAtlanta|130|1325|41.2|modern|TRAP|BK
"""

    /// The kits before Oct 17: saved projects and your kits that used one open the nearest new kit.
    static let retired: [String: String] = [
        "2000s-rnb": "rnb-a",
        "80s-pop": "90s-rnb-a",
        "90s-pop": "90s-rnb-a",
        "afrobeats": "afrobeats-a",
        "amapiano": "amapiano-a",
        "analog-funk": "70s-soul-a",
        "atl-trap": "trap-a",
        "bay-slap": "bay-area-2026-a",
        "boom-bap": "boom-bap-a",
        "cole-world": "neo-soul-a",
        "danger-drums": "trap-a",
        "danger-drums-2": "trap-a",
        "dark-experimental": "fx-lab-a",
        "detroit": "detroit-2026-a",
        "dirty-soul": "neo-soul-a",
        "drill-nights": "drill-a",
        "drum-mastery": "trap-a",
        "funk-break": "70s-soul-a",
        "g-80s-funk-a": "70s-soul-a",
        "g-80s-funk-b": "70s-soul-a",
        "g-80s-pop-a": "90s-rnb-a",
        "g-80s-pop-b": "90s-rnb-a",
        "g-80s-rnb-a": "90s-rnb-a",
        "g-80s-rnb-b": "90s-rnb-a",
        "g-90s-rnb-a": "90s-rnb-a",
        "g-90s-rnb-b": "90s-rnb-a",
        "g-amapiano-a": "amapiano-a",
        "g-amapiano-b": "amapiano-a",
        "g-boom-bap-a": "boom-bap-a",
        "g-boom-bap-b": "boom-bap-a",
        "g-dark-trap-a": "trap-a",
        "g-dark-trap-b": "trap-a",
        "g-detroit-a": "detroit-2026-a",
        "g-detroit-b": "detroit-2026-a",
        "g-drill-a": "drill-a",
        "g-drill-b": "drill-a",
        "g-edm-a": "fx-lab-a",
        "g-edm-b": "fx-lab-a",
        "g-house-a": "afrobeats-a",
        "g-house-b": "afrobeats-a",
        "g-jazz-a": "dilla-time-a",
        "g-jazz-b": "dilla-time-a",
        "g-neo-soul-a": "neo-soul-a",
        "g-neo-soul-b": "neo-soul-a",
        "g-rnb-a": "rnb-a",
        "g-rnb-b": "rnb-a",
        "g-soul-rnb-a": "neo-soul-a",
        "g-soul-rnb-b": "neo-soul-a",
        "g-south-african-rnb-a": "amapiano-a",
        "g-south-african-rnb-b": "amapiano-a",
        "g-techno-a": "fx-lab-a",
        "g-techno-b": "fx-lab-a",
        "g-trap-a": "trap-a",
        "g-trap-b": "trap-a",
        "g-west-coast-a": "bay-area-2026-a",
        "g-west-coast-b": "bay-area-2026-a",
        "gospel-chops": "neo-soul-a",
        "heavy-break": "70s-soul-a",
        "knock-gang": "trap-a",
        "live-pop": "90s-rnb-a",
        "live-soul": "neo-soul-a",
        "lo-fi": "neo-soul-a",
        "loose-break": "boom-bap-a",
        "memphis-trap": "trap-a",
        "modern-rnb": "rnb-a",
        "modern-trap": "trap-a",
        "neo-soul": "neo-soul-a",
        "perc-loops": "afrobeats-a",
        "rage": "alt-trap-a",
        "resampled-textures": "fx-lab-a",
        "s-atl-wave-a": "trap-a",
        "s-atl-wave-b": "trap-a",
        "s-carolina-soul-a": "boom-bap-a",
        "s-carolina-soul-b": "boom-bap-a",
        "s-houston-queen-a": "rnb-a",
        "s-houston-queen-b": "rnb-a",
        "s-la-lyricist-a": "bay-area-2026-a",
        "s-la-lyricist-b": "bay-area-2026-a",
        "s-late-night-rnb-a": "rnb-a",
        "s-late-night-rnb-b": "rnb-a",
        "s-rockstar-bounce-a": "alt-trap-a",
        "s-rockstar-bounce-b": "alt-trap-a",
        "s-soft-soul-a": "rnb-a",
        "s-soft-soul-b": "rnb-a",
        "s-toronto-nights-a": "trap-a",
        "s-toronto-nights-b": "trap-a",
        "s-vamp-rage-a": "alt-trap-a",
        "s-vamp-rage-b": "alt-trap-a",
        "shakers": "afrobeats-a",
        "six-side": "trap-a",
        "sky-textures": "fx-lab-a",
        "toronto-weird": "trap-a",
        "trap-soul": "rnb-a",
        "vintage-rnb": "neo-soul-a",
        "west-90s": "bay-area-2026-a",
        "west-bounce": "bay-area-2026-a",
        "west-end": "bay-area-2026-a",
        "world-latin": "afrobeats-a"
    ]
}
