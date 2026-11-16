# Toolchain setup: CLI assignments override local.mk, which overrides these defaults.
PYTHON ?= python3
TOOLCHAIN ?= auto
BUNDLE ?=
GODOT ?= godot
CARGO ?= cargo
UV ?= uv
BUNDLE_OUT ?= .build/bundles/drawing-toolchain-linux-x86_64.tar.zst
-include local.mk

TOOL = $(PYTHON) tools/toolchain.py
WITH_TOOL = GODOT="$(GODOT)" CARGO="$(CARGO)" UV="$(UV)" $(TOOL) exec --mode "$(TOOLCHAIN)" --bundle "$(BUNDLE)" --
RUFF_VERSION := $(shell $(PYTHON) tools/toolchain.py pin ruff)
TY_VERSION := $(shell $(PYTHON) tools/toolchain.py pin ty)

.PHONY: help doctor native stage-drawing import-drawing import-atlas drawing atlas build \
        test check lint format clean bundle bundle-check bundle-verify python-test

help:
	@printf '%s\n' 'make drawing [GODOT=/path] [TOOLCHAIN=system|bundle] [BUNDLE=/path/to.tar.zst]' \
	  'make atlas / build / test / check / lint / doctor / bundle / bundle-check'

doctor:
	@GODOT="$(GODOT)" CARGO="$(CARGO)" UV="$(UV)" $(TOOL) doctor --mode "$(TOOLCHAIN)" --bundle "$(BUNDLE)"

native:
	@$(WITH_TOOL) bash tools/build_native_brush.sh

stage-drawing: native
	@$(PYTHON) tools/build_drawing_app.py --in-place
	@$(PYTHON) tools/prepare_native_project.py drawing

import-drawing: stage-drawing
	@$(WITH_TOOL) godot --headless --editor --path drawing --import --quit

import-atlas: native
	@$(PYTHON) tools/prepare_native_project.py .
	@$(WITH_TOOL) godot --headless --editor --path . --import --quit

drawing: import-drawing
	@$(WITH_TOOL) godot --path drawing

atlas: import-atlas
	@$(WITH_TOOL) godot --path .

build: import-drawing import-atlas

test: build
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/native_brush_integration.gd
	@$(WITH_TOOL) godot --headless --path drawing --script res://tests/t148_native_tiles_contract.gd
	@$(WITH_TOOL) godot --headless --path . --script res://tests/t148_atlas_native_tile_history.gd

python-test:
	@$(PYTHON) -m unittest discover -s tests -p 'test_toolchain_build.py'

lint:
	@$(WITH_TOOL) uv run --no-project --no-managed-python --python "$(PYTHON)" --with "ruff==$(RUFF_VERSION)" --with "ty==$(TY_VERSION)" -- ruff check tools/toolchain.py tools/prepare_native_project.py tests/test_toolchain_build.py
	@$(WITH_TOOL) uv run --no-project --no-managed-python --python "$(PYTHON)" --with "ruff==$(RUFF_VERSION)" --with "ty==$(TY_VERSION)" -- ty check tools/toolchain.py tools/prepare_native_project.py

format:
	@$(WITH_TOOL) uv run --no-project --no-managed-python --python "$(PYTHON)" --with "ruff==$(RUFF_VERSION)" -- ruff format tools/toolchain.py tools/prepare_native_project.py tests/test_toolchain_build.py

check: python-test lint test

bundle:
	@$(PYTHON) tools/toolchain.py bundle --output "$(BUNDLE_OUT)" --python "$(PYTHON)"

bundle-verify:
	@$(PYTHON) tools/toolchain.py verify --bundle "$(BUNDLE_OUT)"

bundle-check: bundle-verify
	@$(MAKE) test TOOLCHAIN=bundle BUNDLE="$(BUNDLE_OUT)"

clean:
	@rm -rf .build/target drawing/addons/drawing
	@printf '%s\n' 'Removed generated build outputs; cached toolchains retained.'
