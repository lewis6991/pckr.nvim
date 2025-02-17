export XDG_DATA_HOME ?= $(PWD)/.data

.DEFAULT_GOAL := test

UNAME_S := $(shell uname -s)
UNAME_M := $(shell uname -m)

# ------------------------------------------------------------------------------
# Nvim-test
# ------------------------------------------------------------------------------

export NVIM_TEST_VERSION ?= v0.10.3

FILTER ?= .*

NVIM_TEST := deps/nvim-test
NVIM_TEST_REV = v1.1.0

.PHONY: nvim-test
nvim-test: $(NVIM_TEST)

$(NVIM_TEST):
	git clone \
		--filter=blob:none \
		--branch $(NVIM_TEST_REV) \
		https://github.com/lewis6991/nvim-test $@
	$@/bin/nvim-test --init

.PHONY: test
test: $(NVIM_TEST)
	$(NVIM_TEST)/bin/nvim-test test \
		--lpath=$(PWD)/lua/?.lua \
		--filter="$(FILTER)" \
		--verbose \
		--coverage

.PHONY: test-all
test-all: \
    test-v0.9.5 \
    test-v0.10.3 \
    test-nightly

# Dummy rule to force pattern rules to be phony
.PHONY: phony_explicit
phony_explicit:

.PHONY: test-%
test-%: phony_explicit
	$(MAKE) $(MAKEFLAGS) test NVIM_TEST_VERSION=$*

# ------------------------------------------------------------------------------
# Stylua
# ------------------------------------------------------------------------------
ifeq ($(UNAME_S),Darwin)
    STYLUA_PLATFORM := macos-aarch64
else
    STYLUA_PLATFORM := linux-x86_64
endif

STYLUA_VERSION := v2.0.2
STYLUA_ZIP := stylua-$(STYLUA_PLATFORM).zip
STYLUA_URL := https://github.com/JohnnyMorganz/StyLua/releases/download/$(STYLUA_VERSION)/$(STYLUA_ZIP)
STYLUA := deps/stylua

.INTERMEDIATE: $(STYLUA_ZIP)
$(STYLUA_ZIP):
	wget $(STYLUA_URL)

.PHONY: stylua
stylua: $(STYLUA)

$(STYLUA): $(STYLUA_ZIP)
	unzip $< -d $(dir $@)

LUA_FILES := $(shell git ls-files lua test)

.PHONY: stylua-check
stylua-check: $(STYLUA)
	$(STYLUA) --check $(LUA_FILES)

.PHONY: stylua-run
stylua-run: $(STYLUA)
	$(STYLUA) $(LUA_FILES)

# ------------------------------------------------------------------------------
# LuaLS
# ------------------------------------------------------------------------------

ifeq ($(UNAME_M),arm64)
    LUALS_ARCH ?= arm64
else
    LUALS_ARCH ?= x64
endif

LUALS_VERSION := 3.13.6
LUALS := deps/lua-language-server-$(LUALS_VERSION)-$(UNAME_S)-$(LUALS_ARCH)
LUALS_TARBALL := $(LUALS).tar.gz
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/$(notdir $(LUALS_TARBALL))

.PHONY: luals
luals: $(LUALS)

$(LUALS):
	wget --directory-prefix=$(dir $@) $(LUALS_URL)
	mkdir -p $@
	tar -xf $(LUALS_TARBALL) -C $@
	rm -rf $(LUALS_TARBALL)

.PHONY: luals-check
luals-check: $(LUALS) nvim-test
	VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime \
		$(LUALS)/bin/lua-language-server \
			--configpath=../.luarc.json \
			--check=lua
