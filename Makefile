# GNU Make otherwise uses /bin/sh, which may not support pipefail. Our
# logged native test recipes need Bash to preserve Godot failure through tee.
SHELL := /bin/bash

# Toolchain setup: CLI assignments override local.mk, which overrides these defaults.
PYTHON ?= python3
TOOLCHAIN ?= auto
BUNDLE ?=
GODOT ?= godot
CARGO ?= cargo
UV ?= uv
RUST_BIN ?=
GODOT_ARCHIVE ?=
UV_ARCHIVE ?=
GODOT_ARGS ?=
BUNDLE_OUT ?= .build/bundles/drawing-toolchain-linux-x86_64.tar.zst
-include local.mk

TOOL = "$(PYTHON)" tools/toolchain.py
WITH_TOOL = env GODOT="$(GODOT)" CARGO="$(CARGO)" UV="$(UV)" RUST_BIN="$(RUST_BIN)" $(TOOL) exec --mode "$(TOOLCHAIN)" --bundle "$(BUNDLE)" --
RUFF_VERSION = $(shell "$(PYTHON)" tools/toolchain.py pin ruff)
TY_VERSION = $(shell "$(PYTHON)" tools/toolchain.py pin ty)
PYTHON_CHECKS = tools/toolchain.py tools/prepare_native_project.py tools/check_offline_toolchain.py tools/run_t185_profile.py tools/package_linux_export.py tests/test_t201_linux_native_package.py tests/test_t185_profile.py tests/test_t198_matched_callbacks.py tests/test_t199_canvas_draw_cadence.py tests/test_t217_pck_index.py tests/test_t218_pck_payload_integrity.py tests/test_t219_pck_resource_names.py tests/test_t220_pck_project_identity.py tests/t217_pck_fixture.py

.PHONY: help doctor native stage-drawing import-drawing import-atlas drawing atlas build \
        test test-graphical test-dock-toggle test-dock-flyout test-floating-tabs test-floating-context test-floating-cancel test-floating-focus test-floating-release test-dock-release test-color-interruption test-live-stroke check lint format clean bundle bundle-check bundle-verify python-test

help:
	@printf '%s\n' 'make drawing [GODOT=/path] [TOOLCHAIN=system|bundle] [BUNDLE=/path/to.tar.zst]' \
	  'make atlas / build / test / check / lint / doctor / bundle / bundle-check'

doctor:
	@GODOT="$(GODOT)" CARGO="$(CARGO)" UV="$(UV)" RUST_BIN="$(RUST_BIN)" $(TOOL) doctor --mode "$(TOOLCHAIN)" --bundle "$(BUNDLE)"

native:
	@$(WITH_TOOL) bash tools/build_native_brush.sh

stage-drawing: native
	@"$(PYTHON)" tools/build_drawing_app.py --in-place
	@"$(PYTHON)" tools/prepare_native_project.py drawing

import-drawing: stage-drawing
	@$(WITH_TOOL) godot --headless --editor --path drawing --import --quit
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/native_extension_ready.gd

import-atlas: native
	@"$(PYTHON)" tools/prepare_native_project.py .
	@$(WITH_TOOL) godot --headless --editor --path . --import --quit
	@$(WITH_TOOL) godot --headless --path . --script res://drawing/tests/native_extension_ready.gd

drawing: import-drawing
	@$(WITH_TOOL) godot --path drawing $(GODOT_ARGS)

atlas: import-atlas
	@$(WITH_TOOL) godot --path . $(GODOT_ARGS)

build: import-drawing import-atlas

test: build
	@$(WITH_TOOL) bash tools/build_native_brush.sh --test
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/native_brush_integration.gd
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/t148_native_tiles_contract.gd
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/standalone_smoke.gd
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/t182_brush_preset_controls.gd
	@$(WITH_TOOL) godot --headless --path . --script res://tests/t148_atlas_native_tile_history.gd

test-graphical: import-drawing
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t181_native_preview_retention.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t186_batch_native_preview.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t187_direct_native_preview.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t188_native_delta_runs.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t189_native_source_lookup.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t190_exact_srgb_quantization.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t191_native_row_scan.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t192_native_batch_journal.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t193_native_journal_cache.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t194_native_batch_cadence.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t195_release_catchup.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t196_release_deferred.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t197_first_preview_callback.gd

# T-262: reproducible T-085 held-preview native CI witness after both imports.
# Retain complete process logs during validation, then remove temporary files.
test-live-stroke: import-drawing import-atlas
	@set -euo pipefail; log=$$(mktemp); trap 'rm -f "$$log"' EXIT; \
	  $(WITH_TOOL) godot --headless --audio-driver Dummy --path drawing --script res://tests/live_stroke_smoke.gd 2>&1 | tee "$$log"; \
	  "$(PYTHON)" tools/check_godot_model_log.py "$$log" --marker T085_MODEL_PASSED
	@set -euo pipefail; log=$$(mktemp); trap 'rm -f "$$log"' EXIT; \
	  xvfb-run -a --server-args='-screen 0 1600x1200x24' $(WITH_TOOL) godot \
	    --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy \
	    --path drawing --script res://tests/live_stroke_native.gd 2>&1 | tee "$$log"; \
	  "$(PYTHON)" tools/check_native_t085_log.py "$$log"

# T-251: real pointer/framebuffer regression against both standalone Drawing and
# the Atlas-hosted canonical workspace. Both need an imported native extension.
test-dock-toggle: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t251_dock_toggle_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t251_atlas_dock_native.gd

# T-254: real minimized-flyout icon, context, persistence and Atlas checks.
# Stage + import before the tests so named SVG/fallback assets are available.
test-dock-flyout: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t254_flyout_icons_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t254_atlas_flyout_native.gd

# T-255: clipped floating tab hit zones in standalone and embedded Drawing.
test-floating-tabs: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t255_floating_tab_hit_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t255_atlas_floating_tab_hit_native.gd

# T-256: float-tab context menus in the same native Drawing/Atlas code path.
test-floating-context: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t256_floating_tab_menu_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t256_atlas_floating_tab_menu_native.gd

# T-257: Escape rollback of a floating move/resize in both native consumers.
test-floating-cancel: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t257_floating_cancel_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t257_atlas_floating_cancel_native.gd

# T-258: focus-loss rollback and next legitimate input in standalone + Atlas.
test-floating-focus: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t258_floating_focus_cancel_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t258_atlas_floating_focus_cancel_native.gd

# T-259: recover dropped OS mouse-up from button-mask motion (focus retained).
test-floating-release: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t259_floating_lost_release_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t259_atlas_floating_lost_release_native.gd

# T-264: lost mouse-up recovery across expanded, minimized and flyout dock drags.
test-dock-release: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t264_dock_lost_release_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t264_atlas_dock_lost_release_native.gd

# T-261: interrupted ColorPicker pointer gestures never commit phantom recents.
test-color-interruption: import-drawing import-atlas
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path drawing --script res://tests/t261_color_interruption_native.gd
	@xvfb-run -a $(WITH_TOOL) godot --display-driver x11 --rendering-method gl_compatibility --audio-driver Dummy --path . --script res://tests/t261_atlas_color_interruption_native.gd

python-test:
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_toolchain_build.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t185_profile.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t198_matched_callbacks.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t199_canvas_draw_cadence.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t068_release_gate.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t105_portability.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t201_linux_native_package.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t217_pck_index.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t218_pck_payload_integrity.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t219_pck_resource_names.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t220_pck_project_identity.py'

lint:
	@$(WITH_TOOL) uv run --no-project --no-managed-python --python "$(PYTHON)" --with "ruff==$(RUFF_VERSION)" --with "ty==$(TY_VERSION)" -- ruff check $(PYTHON_CHECKS) tests/test_toolchain_build.py
	@$(WITH_TOOL) uv run --no-project --no-managed-python --python "$(PYTHON)" --with "ruff==$(RUFF_VERSION)" --with "ty==$(TY_VERSION)" -- ty check $(PYTHON_CHECKS)

format:
	@$(WITH_TOOL) uv run --no-project --no-managed-python --python "$(PYTHON)" --with "ruff==$(RUFF_VERSION)" -- ruff format $(PYTHON_CHECKS) tests/test_toolchain_build.py

check: python-test lint test

bundle:
	@$(TOOL) bundle --output "$(BUNDLE_OUT)" --python "$(PYTHON)" --godot-archive "$(GODOT_ARCHIVE)" --uv-archive "$(UV_ARCHIVE)"

bundle-verify:
	@$(TOOL) verify --bundle "$(if $(BUNDLE),$(BUNDLE),$(BUNDLE_OUT))"

bundle-check: bundle-verify
	@$(MAKE) test TOOLCHAIN=bundle BUNDLE="$(if $(BUNDLE),$(BUNDLE),$(BUNDLE_OUT))"

clean:
	@rm -rf .build/target native/drawing_brush/target addons/drawing/native drawing/addons/drawing
	@printf '%s\n' 'Removed generated build outputs; cached toolchains retained.'
