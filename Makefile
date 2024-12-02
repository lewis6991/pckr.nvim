export XDG_DATA_HOME ?= $(PWD)/.data

.DEFAULT_GOAL := test

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

ifeq ($(shell uname -m),arm64)
    LUALS_ARCH ?= arm64
else
    LUALS_ARCH ?= x64
endif

LUALS_VERSION := 3.13.2
LUALS_TARBALL := lua-language-server-$(LUALS_VERSION)-$(shell uname -s)-$(LUALS_ARCH).tar.gz
LUALS_URL := https://github.com/LuaLS/lua-language-server/releases/download/$(LUALS_VERSION)/$(LUALS_TARBALL)

luals:
	wget $(LUALS_URL)
	mkdir luals
	tar -xf $(LUALS_TARBALL) -C luals
	rm -rf $(LUALS_TARBALL)

export VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime
.PHONY: luals-check
luals-check: luals nvim-test
	VIMRUNTIME=$(XDG_DATA_HOME)/nvim-test/nvim-test-$(NVIM_TEST_VERSION)/share/nvim/runtime \
		luals/bin/lua-language-server \
			--logpath=. \
			--configpath=../.luarc.json \
			--check=lua
	@grep '^\[\]$$' check.json

