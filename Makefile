
.DEFAULT_GOAL := test

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

