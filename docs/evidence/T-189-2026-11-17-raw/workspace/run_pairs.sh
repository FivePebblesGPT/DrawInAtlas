#!/usr/bin/env bash
set -uo pipefail
cd /mnt/data/DrawInAtlas-sprint-2026-11-17
GODOT="$PWD/.build/toolchains/3196a30246b27be598eb010c207897045d59d87c65eac967c603baa4b0f135c2/bin/godot"
for pair in 1 2; do
  if [[ $pair == 1 ]]; then modes=(optimized reference); else modes=(reference optimized); fi
  for mode in "${modes[@]}"; do
    echo "START round=$pair mode=$mode $(date -u +%FT%TZ)"
    if [[ $mode == reference ]]; then export DRAWING_T189_SOURCE_PER_PIXEL_COUNTERFACTUAL=1; else unset DRAWING_T189_SOURCE_PER_PIXEL_COUNTERFACTUAL; fi
    export DRAWING_T185_PROFILE=1
    python3 tools/run_t185_profile.py --godot "$GODOT" \
      --output "$PWD/.build/evidence/T-189/workspace/round${pair}/${mode}" \
      --trials 1 --timeout 85
    rc=$?
    echo "END round=$pair mode=$mode rc=$rc $(date -u +%FT%TZ)"
  done
done
