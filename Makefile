# Synchronous FIFO
#   make lint    Verilator lint (-Wall) of the RTL at several parameter sets
#   make test    build and run the self-checking testbench (Verilator, with assertions)
#   make synth   Yosys synthesis + cell statistics
#   make wave    rebuild with VCD tracing (build/sync_fifo.vcd)
#   make clean

VERILATOR ?= verilator
YOSYS     ?= yosys

RTL   := rtl/sync_fifo.sv
SVA   := sva/sync_fifo_sva.sv
TB    := tb/fifo_test.sv tb/tb_top.sv
BUILD := build

VFLAGS := --binary --timing --assert -j 0 --top-module tb_top

.PHONY: all lint test synth wave clean

all: lint test synth

lint:
	$(VERILATOR) --lint-only -Wall $(RTL)
	$(VERILATOR) --lint-only -Wall -GDATA_W=16 -GDEPTH=7 $(RTL)
	$(VERILATOR) --lint-only -Wall -GDATA_W=32 -GDEPTH=2 $(RTL)
	@echo "lint OK"

test:
	@mkdir -p $(BUILD)
	$(VERILATOR) $(VFLAGS) -Mdir $(BUILD)/sim $(RTL) $(SVA) $(TB) -o tb_top > $(BUILD)/build.log 2>&1 \
	    || (cat $(BUILD)/build.log; exit 1)
	$(BUILD)/sim/tb_top | tee $(BUILD)/sim.log
	@grep -q "ALL TESTS PASSED" $(BUILD)/sim.log

synth:
	@mkdir -p $(BUILD)
	$(YOSYS) -q -l $(BUILD)/synth.log -p "\
	    read_verilog -sv $(RTL); \
	    chparam -set DATA_W 8 -set DEPTH 16 sync_fifo; \
	    synth -top sync_fifo; \
	    check -assert; \
	    tee -q -o $(BUILD)/synth_stat.txt stat"
	@echo "synthesis OK (8 x 16)"
	@grep -E "cells$$|DFF|MUX" $(BUILD)/synth_stat.txt

wave:
	@mkdir -p $(BUILD)
	$(VERILATOR) $(VFLAGS) --trace -DDUMP -Mdir $(BUILD)/wave $(RTL) $(SVA) $(TB) -o tb_top > $(BUILD)/build.log 2>&1 \
	    || (cat $(BUILD)/build.log; exit 1)
	cd $(BUILD) && ./wave/tb_top

clean:
	rm -rf $(BUILD)
