#!/bin/sh
# Rebuilds BreakBoss.swiftpm/KnobTaperTables.swift (run after changing any FX DSP in ModeProcessor.swift
# or TIGHTEN's tail). Needs swiftc (SWIFTC=... to pick one) and, on Linux, an `os` module stub (-I).
set -e
cd "$(dirname "$0")/../.."
SRC=BreakBoss.swiftpm
OUT=$(mktemp -d)
FILES=""
for f in $SRC/*.swift; do
  case "$f" in */Package.swift|*/KnockSelfTest*|*/KnobTaperTables.swift) continue;; esac
  if grep -q "import SwiftUI\|import UIKit\|import AVFoundation\|import CoreMotion\|import CoreMIDI\|import GameController\|extension KnockController" "$f"; then continue; fi
  FILES="$FILES $f"
done
STUBS=""
[ "$(uname)" = "Linux" ] && STUBS="tools/knob_taper/linux_stubs.swift"
# the table maker must not read the tables it is about to replace: an empty table file first
cp tools/knob_taper/make_tables.swift "$OUT/main.swift"
printf 'import Foundation\nenum KnobTaperTables { static func table(_ p: KParam, _ c: KnobContext) -> [Float]? { nil } }\n' > "$OUT/empty.swift"
FILES=$(echo $FILES | tr ' ' '\n' | grep -v KnobTaperTables.swift | tr '\n' ' ')
${SWIFTC:-swiftc} -O -swift-version 5 $SWIFT_FLAGS -o "$OUT/make" $FILES "$OUT/empty.swift" $STUBS "$OUT/main.swift"
"$OUT/make" $SRC/KnobTaperTables.swift tools/knob_taper/report.txt
echo "wrote $SRC/KnobTaperTables.swift and tools/knob_taper/report.txt"
