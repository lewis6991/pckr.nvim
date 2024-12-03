export XDG_DATA_HOME ?= $(PWD)/.data

.DEFAULT_GOAL := test

# ------------------------------------------------------------------------------
# Nvim-test
# ------------------------------------------------------------------------------

export NVIM_TEST_VERSION ?= v0.10.0

FILTER ?= .*

nvim-test:
	git clone https://github.com/lewis6991/nvim-test
	nvim-test/bin/nvim-test --init

.PHONY: test
test: nvim-test
	nvim-test/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua \
		--filter="$(FILTER)" \
		--verbose \
		--coverage

# ------------------------------------------------------------------------------
# LuaLS
# ------------------------------------------------------------------------------

ifeq ($(shell uname -m),arm64)
    LUALS_ARCH ?= arm64
else
    LUALS_ARCH ?= x64
endif

LUALS_VERSION := 3.13.2
LUALS_TARBALL := lua-language-server-$(LUALS_VERSION)-$(shell uname -s)-$(LUALS_ARCH).tar.gz
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/$(LUALS_TARBALL)

.INTERMEDIATE: $(LUALS_TARBALL)
$(LUALS_TARBALL):
	wget $(LUALS_URL)

luals: $(LUALS_TARBALL)
	mkdir luals
	tar -xf $< -C luals

export VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime
.PHONY: luals-check
luals-check: luals nvim-test
	VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime \
		luals/bin/lua-language-server \
			--logpath=luals_check \
			--configpath=../.luarc.json \
			--check=lua
	@grep '^\[\]$$' luals_check/check.json

# ------------------------------------------------------------------------------
# Stylua
# ------------------------------------------------------------------------------
ifeq ($(shell uname -s),Darwin)
    STYLUA_PLATFORM := macos-aarch64
else
    STYLUA_PLATFORM := linux-x86_64
endif

STYLUA_VERSION := v2.0.1
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL := https://github.com/JohnnyMorganz/StyLua/releases/download/$(STYLUA_VERSION)/$(STYLUA_ZIP)

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

stylua: $(STYLUA_ZIP)
	unzip $<

.PHONY: stylua-check
stylua-check: stylua
	./stylua --check lua/**/*.lua

.PHONY: stylua-run
stylua-run: stylua
	./stylua \
		lua/**/*.lua \
		lua/*.lua \
		test/*.lua
