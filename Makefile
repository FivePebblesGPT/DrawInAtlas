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
PYTHON_CHECKS = tools/toolchain.py tools/prepare_native_project.py tools/check_offline_toolchain.py tools/run_t185_profile.py tests/test_t185_profile.py

.PHONY: help doctor native stage-drawing import-drawing import-atlas drawing atlas build \
        test test-graphical check lint format clean bundle bundle-check bundle-verify python-test

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

python-test:
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_toolchain_build.py'
	@"$(PYTHON)" -m unittest discover -s tests -p 'test_t185_profile.py'

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
