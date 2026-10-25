# =============================================================================
#  Simulación RTL de femto_UN v2 (Icarus Verilog + GTKWave)
#  Uso:
#     make sim        -> compila, simula y abre GTKWave
#     make run        -> compila y simula (sin abrir GTKWave)
#     make firmware   -> recompila el firmware y copia firmware_flash.hex aquí
#                        (otro programa: make firmware PROG=test_ram_bytes)
#     make test_ram   -> prueba de la RAM completa + GTKWave con su vista
#     make ver_ram    -> abre GTKWave con la vista de la RAM
#     make test_ram_hex      -> como test_ram, con el hex ya ensamblado (sin toolchain)
#     make test_ram_original -> la misma prueba con la RAM ORIGINAL, para comparar
#
#  Simulación con compuertas sky130 (como `make tt_um_femto` del curso):
#     make synth                -> sintetiza la v2 con Yosys (../synth/tt_um_femto_v2.v)
#     make tt_um_femto          -> simula la netlist de la v2 y abre GTKWave
#     make tt_um_femto_original -> simula la netlist del chip fabricado (curso)
#     Ver docs/POSTSINTESIS.md (Ctrl+C y `finish`, qué mirar).
#     make clean
# =============================================================================

RTL_DIR = ../rtl
FW_DIR  = ../firmware/asm

RTL  = $(RTL_DIR)/femto.v
RTL += $(RTL_DIR)/femtorv32_quark_un_irq.v
RTL += $(RTL_DIR)/perip_uart.v
RTL += $(RTL_DIR)/uart.v
RTL += $(RTL_DIR)/perip_mult.v
RTL += $(RTL_DIR)/mult.v
RTL += $(RTL_DIR)/bram.v
RTL += $(RTL_DIR)/MappedSPIFlash.v
RTL += $(RTL_DIR)/MappedSPIRAM.v

# Modelos de las memorias externas (spiram.v incluye config.v)
MODELS = spiflash.v spiram.v

TB     = tt_um_femto_TB.v
DEFS   = -DBENCH -DSIM -DPASSTHROUGH_PLL -DBOARD_FREQ=27 -DCPU_FREQ=27
FW_HEX ?= firmware_flash.hex
# 0 = duración original del testbench (~19 ms); ej.: make run TIEMPO_MS=60
TIEMPO_MS ?= 0
# RAM_LOG=1 guarda cada lectura/escritura de la RAM en ram_log.txt
RAM_LOG ?= 0
ifeq ($(RAM_LOG),1)
  PLUSARGS_EXTRA = +ram_log
endif

all: run

sim.vvp: $(TB) $(RTL) $(MODELS)
	iverilog -I . $(DEFS) -o $@ $(TB) $(RTL) $(MODELS)

run: sim.vvp $(FW_HEX)
	vvp sim.vvp +firmware=$(FW_HEX) +tiempo_ms=$(TIEMPO_MS) $(PLUSARGS_EXTRA)

sim: run
	gtkwave tt_um_femto_TB.vcd tt_um_femto_sim.gtkw &

# Programa a cargar: make firmware PROG=test_ram_bytes
PROG ?= uart_full_demo
firmware:
	$(MAKE) -C $(FW_DIR) clean
	$(MAKE) -C $(FW_DIR) PROG=$(PROG)
	cp $(FW_DIR)/firmware_flash.hex .

# Prueba completa de la RAM: ensambla test_ram_bytes, simula 80 ms con el
# registro de accesos y abre GTKWave con la vista de la RAM.
test_ram:
	$(MAKE) firmware PROG=test_ram_bytes
	$(MAKE) run TIEMPO_MS=80 RAM_LOG=1
	$(MAKE) ver_ram

ver_ram:
	gtkwave tt_um_femto_TB.vcd tt_um_femto_ram.gtkw &

# Igual que test_ram pero con el firmware ya ensamblado (hex/), sin toolchain.
test_ram_hex:
	$(MAKE) run FW_HEX=hex/test_ram_bytes.hex TIEMPO_MS=80 RAM_LOG=1
	$(MAKE) ver_ram

# Misma prueba con la RAM ORIGINAL (v1_original/rtl/MappedSPIRAM.v), para
# comparar. femto.v se adapta a los puertos viejos (word_address, sin wmask).
# Resultados en tt_um_femto_TB_original.vcd y ram_log_original.txt.
RAM_V1 = ../../v1_original/rtl/MappedSPIRAM.v
RTL_V1 = $(filter-out $(RTL_DIR)/femto.v $(RTL_DIR)/MappedSPIRAM.v,$(RTL)) femto_ram_original.v $(RAM_V1)

femto_ram_original.v: $(RTL_DIR)/femto.v
	sed -e 's/\.address(mem_address/.word_address(mem_address/' \
	    -e '/\.wmask(mem_wmask)/d' $< > $@

test_ram_original: femto_ram_original.v
	iverilog -I . $(DEFS) -o sim_original.vvp $(TB) $(RTL_V1) $(MODELS)
	# se corre en su propia carpeta para no pisar los archivos de la versión nueva
	mkdir -p build_original
	cd build_original && vvp ../sim_original.vvp +firmware=../hex/test_ram_bytes.hex +tiempo_ms=80 +ram_log
	mv build_original/tt_um_femto_TB.vcd tt_um_femto_TB_original.vcd
	mv build_original/ram_log.txt ram_log_original.txt
	rmdir build_original
	gtkwave tt_um_femto_TB_original.vcd tt_um_femto_ram_original.gtkw &

# =============================================================================
#  Simulación con compuertas (gate-level), igual que `make tt_um_femto` del
#  repo del curso: netlist + modelos de celdas sky130 + modelos de flash y RAM.
#  -DFUNCTIONAL      modelos de celdas sin tiempos (solo la función lógica)
#  -DUNIT_DELAY=#1   cada celda tarda 1 unidad de tiempo
#  Sin BENCH ni SIM: el testbench conecta VPWR/VGND y decodifica TXD.
#
#  Es lenta: se puede parar con Ctrl+C y escribir `finish` en el prompt de vvp
#  (el VCD queda bien cerrado y se abre GTKWave), o fijar la duración con
#  TIEMPO_MS=N para que termine sola.
# =============================================================================
CELLS    = verilog_model/sky130_fd_sc_hd.v verilog_model/primitives.v
NETLIST  ?= ../synth/tt_um_femto_v2.v
GL_HEX   ?= hex/test_ram_bytes.hex
GL_DEFS  = -DFUNCTIONAL -DUNIT_DELAY=\#1
# VCD_COMPLETO=1: vuelca también el interior de cada celda (como el curso; VCD enorme)
VCD_COMPLETO ?= 0
ifeq ($(VCD_COMPLETO),1)
  GL_PLUSARGS = +vcd_completo
endif

synth:
	cd ../synth && yosys -q -l synth.log -s synth.ys
	@echo "Netlist: ../synth/tt_um_femto_v2.v   (resumen en ../synth/synth_stat.txt)"

# Ctrl+C llega a la vez a make, al shell de la receta y a vvp. vvp lo atrapa y
# abre su prompt; make y el shell, en cambio, se cortarían y GTKWave no se
# abriría. Por eso: `trap '' INT` (el shell ignora Ctrl+C), vvp + gtkwave en
# la misma línea, y `setsid -f` en lugar de `&` (un `&` normal no alcanza a
# arrancar porque make, interrumpido, termina enseguida). Al escribir
# `finish`, vvp cierra el VCD y se abre GTKWave.
tt_um_femto: $(NETLIST)
	iverilog $(GL_DEFS) -I . -o tt_um_femto.vpp -s tt_um_femto_TB $(TB) $(NETLIST) spiflash.v $(CELLS) spiram.v
	trap '' INT; vvp tt_um_femto.vpp +firmware=$(GL_HEX) +tiempo_ms=$(TIEMPO_MS) $(GL_PLUSARGS); \
	setsid -f gtkwave tt_um_femto_TB.vcd tt_um_femto_gl.gtkw

# Netlist del chip fabricado (post-layout, con pines de alimentación), tal
# como la simula el profesor: por eso lleva -DUSE_POWER_PINS.
NETLIST_V1 = ../../v1_original/sim/tt_um_femto.v
# Programa por defecto: la demo del curso (Hello World + interrupciones). Con
# test_ram_bytes el chip viejo falla (flash y RAM originales), ver docs/RAM.md.
GL_HEX_V1 ?= hex/uart_full_demo.hex
tt_um_femto_original:
	iverilog -DUSE_POWER_PINS $(GL_DEFS) -I . -o tt_um_femto_original.vpp -s tt_um_femto_TB $(TB) $(NETLIST_V1) spiflash.v $(CELLS) spiram.v
	trap '' INT; vvp tt_um_femto_original.vpp +firmware=$(GL_HEX_V1) +tiempo_ms=$(TIEMPO_MS) $(GL_PLUSARGS); \
	setsid -f gtkwave tt_um_femto_TB.vcd tt_um_femto_gl.gtkw

clean:
	rm -f sim.vvp sim_original.vvp a.out *.vcd ram_log*.txt femto_ram_original.v
	rm -f tt_um_femto.vpp tt_um_femto_original.vpp
	rm -rf build_original

.PHONY: all run sim firmware test_ram test_ram_hex test_ram_original ver_ram synth tt_um_femto tt_um_femto_original clean
