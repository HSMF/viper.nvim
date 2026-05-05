NVIM ?= nvim
PLENARY ?= $(shell \
  for p in \
    "$$HOME/.local/share/nvim/lazy/plenary.nvim" \
    "$$HOME/.local/share/nvim/site/pack/packer/start/plenary.nvim"; \
  do [ -d "$$p" ] && echo "$$p" && break; done)

.PHONY: test

test:
	@if [ -z "$(PLENARY)" ]; then \
	  echo "ERROR: plenary.nvim not found. Set PLENARY=/path/to/plenary.nvim"; exit 1; \
	fi
	$(NVIM) --headless \
	  -u tests/minimal_init.lua \
	  --cmd "set rtp+=$(PLENARY)" \
	  -c "lua require('plenary.test_harness').test_directory('tests/', {sequential=true})" \
	  -c "qa!"
