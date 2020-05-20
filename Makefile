GHDL ?= ghdl
GHDLFLAGS=--std=08 --work=unisim
CFLAGS=-O2 -Wall

GHDLSYNTH ?= ghdl.so
YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ecp5
ECPPACK   ?= ecppack
OPENOCD   ?= openocd

# We need a version of GHDL built with either the LLVM or gcc backend.
# Fedora provides this, but other distros may not. Another option is to use
# the Docker image.
DOCKER ?= 0
PODMAN ?= 0

ifeq ($(DOCKER), 1)
DOCKERBIN=docker
USE_DOCKER=1
endif

ifeq ($(PODMAN), 1)
DOCKERBIN=podman
USE_DOCKER=1
endif

ifeq ($(USE_DOCKER), 1)
PWD = $(shell pwd)
DOCKERARGS = run --rm -v $(PWD):/src:z -w /src
GHDL      = $(DOCKERBIN) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 ghdl
CC        = $(DOCKERBIN) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 gcc
GHDLSYNTH = ghdl
YOSYS     = $(DOCKERBIN) $(DOCKERARGS) ghdl/synth:beta yosys
NEXTPNR   = $(DOCKERBIN) $(DOCKERARGS) ghdl/synth:nextpnr-ecp5 nextpnr-ecp5
ECPPACK   = $(DOCKERBIN) $(DOCKERARGS) ghdl/synth:trellis ecppack
OPENOCD   = $(DOCKERBIN) $(DOCKERARGS) --device /dev/bus/usb ghdl/synth:prog openocd
endif

all = core_tb icache_tb dcache_tb multiply_tb dmi_dtm_tb divider_tb \
	rotator_tb countzero_tb wishbone_bram_tb soc_reset_tb

all: $(all)

core_files = decode_types.vhdl common.vhdl wishbone_types.vhdl fetch1.vhdl \
	fetch2.vhdl utils.vhdl plru.vhdl cache_ram.vhdl icache.vhdl \
	decode1.vhdl helpers.vhdl insn_helpers.vhdl gpr_hazard.vhdl \
	cr_hazard.vhdl control.vhdl decode2.vhdl register_file.vhdl \
	cr_file.vhdl crhelpers.vhdl ppc_fx_insns.vhdl rotator.vhdl \
	logical.vhdl countzero.vhdl multiply.vhdl divider.vhdl execute1.vhdl \
	loadstore1.vhdl mmu.vhdl dcache.vhdl writeback.vhdl core_debug.vhdl \
	core.vhdl

soc_files = wishbone_arbiter.vhdl wishbone_bram_wrapper.vhdl \
	wishbone_debug_master.vhdl xics.vhdl syscon.vhdl soc.vhdl

soc_sim_files = sim_console.vhdl sim_uart.vhdl sim_bram_helpers.vhdl \
	sim_bram.vhdl sim_jtag_socket.vhdl sim_jtag.vhdl \
	sim-unisim/BSCANE2.vhdl sim-unisim/BUFG.vhdl \
	sim-unisim/unisim_vcomponents.vhdl dmi_dtm_xilinx.vhdl

soc_sim_c_files = sim_vhpi_c.c sim_bram_helpers_c.c sim_console_c.c \
	sim_jtag_socket_c.c
soc_sim_obj_files=$(soc_sim_c_files:.c=.o)
comma := ,
soc_sim_link=$(patsubst %,-Wl$(comma)%,$(soc_sim_obj_files))

core_tbs = multiply_tb divider_tb rotator_tb countzero_tb
soc_tbs = core_tb icache_tb dcache_tb dmi_dtm_tb wishbone_bram_tb

$(soc_tbs): %: $(core_files) $(soc_files) $(soc_sim_files) $(soc_sim_obj_files) %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(soc_sim_link) $(core_files) $(soc_files) $(soc_sim_files) $@.vhdl -e $@

$(core_tbs): %: $(core_files) glibc_random.vhdl glibc_random_helpers.vhdl %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(core_files) glibc_random.vhdl glibc_random_helpers.vhdl $@.vhdl -e $@

soc_reset_tb: fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl
	$(GHDL) -c $(GHDLFLAGS) fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl -e $@

# Hello world
GHDL_IMAGE_GENERICS=-gMEMORY_SIZE=8192 -gRAM_INIT_FILE=hello_world/hello_world.hex

# Micropython
#GHDL_IMAGE_GENERICS=-gMEMORY_SIZE=393216 -gRAM_INIT_FILE=micropython/firmware.hex

# OrangeCrab with ECP85
GHDL_TARGET_GENERICS=-gRESET_LOW=true -gCLK_INPUT=50000000 -gCLK_FREQUENCY=50000000
LPF=constraints/orange-crab.lpf
PACKAGE=CSFBGA285
NEXTPNR_FLAGS=--um5g-85k --freq 50
OPENOCD_JTAG_CONFIG=openocd/olimex-arm-usb-tiny-h.cfg
OPENOCD_DEVICE_CONFIG=openocd/LFE5UM5G-85F.cfg

# ECP5-EVN
#GHDL_TARGET_GENERICS=-gRESET_LOW=true -gCLK_INPUT=12000000 -gCLK_FREQUENCY=12000000
#LPF=constraints/ecp5-evn.lpf
#PACKAGE=CABGA381
#NEXTPNR_FLAGS=--um5g-85k --freq 12
#OPENOCD_JTAG_CONFIG=openocd/ecp5-evn.cfg
#OPENOCD_DEVICE_CONFIG=openocd/LFE5UM5G-85F.cfg

clkgen=fpga/clk_gen_bypass.vhd
toplevel=fpga/top-generic.vhdl
dmi_dtm=dmi_dtm_dummy.vhdl

fpga_files = $(core_files) $(soc_files) fpga/soc_reset.vhdl \
	fpga/pp_fifo.vhd fpga/pp_soc_uart.vhd fpga/main_bram.vhdl

synth_files = $(core_files) $(soc_files) $(fpga_files) $(clkgen) $(toplevel) $(dmi_dtm)

microwatt.json: $(synth_files)
	$(YOSYS) -m $(GHDLSYNTH) -p "ghdl --std=08 $(GHDL_IMAGE_GENERICS) $(GHDL_TARGET_GENERICS) $(synth_files) -e toplevel; synth_ecp5 -json $@"

microwatt.v: $(synth_files)
	$(YOSYS) -m $(GHDLSYNTH) -p "ghdl --std=08 $(GHDL_IMAGE_GENERICS) $(GHDL_TARGET_GENERICS) $(synth_files) -e toplevel; write_verilog $@"

# Need to investigate why yosys is hitting verilator warnings, and eventually turn on -Wall
microwatt-verilator: microwatt.v verilator/microwatt-verilator.cpp verilator/uart-verilator.c
	verilator -O3 --assert --cc microwatt.v --exe verilator/microwatt-verilator.cpp verilator/uart-verilator.c -o $@ -Wno-CASEOVERLAP -Wno-UNOPTFLAT #--trace
	make -C obj_dir -f Vmicrowatt.mk
	@cp -f obj_dir/microwatt-verilator microwatt-verilator

microwatt_out.config: microwatt.json $(LPF)
	$(NEXTPNR) --json $< --lpf $(LPF) --textcfg $@ $(NEXTPNR_FLAGS) --package $(PACKAGE)

microwatt.bit: microwatt_out.config
	$(ECPPACK) --svf microwatt.svf $< $@

microwatt.svf: microwatt.bit

prog: microwatt.svf
	$(OPENOCD) -f $(OPENOCD_JTAG_CONFIG) -f $(OPENOCD_DEVICE_CONFIG) -c "transport select jtag; init; svf $<; exit"

tests = $(sort $(patsubst tests/%.out,%,$(wildcard tests/*.out)))
tests_console = $(sort $(patsubst tests/%.console_out,%,$(wildcard tests/*.console_out)))

check: $(tests) $(tests_console) test_micropython test_micropython_long

check_light: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 test_micropython test_micropython_long $(tests_console)

$(tests): core_tb
	@./scripts/run_test.sh $@

$(tests_console): core_tb
	@./scripts/run_test_console.sh $@

test_micropython: core_tb
	@./scripts/test_micropython.py

test_micropython_long: core_tb
	@./scripts/test_micropython_long.py

TAGS:
	find . -name '*.vhdl' | xargs ./scripts/vhdltags

.PHONY: TAGS

_clean:
	rm -f *.o work-*cf unisim-*cf $(all)
	rm -f fpga/*.o fpga/work-*cf
	rm -f sim-unisim/*.o sim-unisim/unisim-*cf
	rm -f TAGS
	rm -f scripts/mw_debug/*.o
	rm -f scripts/mw_debug/mw_debug
	rm -f microwatt.bin microwatt.json microwatt.svf microwatt_out.config
	rm -f microwatt.v microwatt-verilator
	rm -rf obj_dir/

clean: _clean
	make -f scripts/mw_debug/Makefile clean
	make -f hello_world/Makefile clean

distclean: _clean
	rm -f *~ fpga/*~ lib/*~ console/*~ include/*~
	rm -rf litedram/build
	rm -f litedram/extras/*~
	rm -f litedram/gen-src/*~
	rm -f litedram/gen-src/sdram_init/*~
	make -f scripts/mw_debug/Makefile distclean
	make -f hello_world/Makefile distclean

.PHONY: all prog check check_light clean distclean
.PRECIOUS: microwatt.json microwatt_out.config microwatt.bit
