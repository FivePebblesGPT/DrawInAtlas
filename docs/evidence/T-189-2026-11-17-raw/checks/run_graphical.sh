#!/bin/bash
cd /mnt/data/DrawInAtlas-sprint-2026-11-17
set +e
timeout 190 make test-graphical TOOLCHAIN=bundle BUNDLE=/mnt/data/drawing-toolchain-linux-x86_64-2026-11-17.tar.zst > .build/evidence/T-189/checks/make-test-graphical-final.log 2>&1
printf 'EXIT:%s\n' "$?" > .build/evidence/T-189/checks/make-test-graphical-final.exit
