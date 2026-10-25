# Registro de cambios v1 → v2

Cada entrada dice qué archivo cambió, qué estaba mal (o qué se mejoró), qué se
hizo y cómo se verificó. La referencia siempre es `v1_original/`.

Estados: **Hecho (sim)** verificado en simulación · **Hecho** verificado
también en hardware · **Aplicado** cambio hecho, falta verificar ·
**Pendiente** identificado, sin cambiar.

## Cambios

| # | Archivo | Problema / mejora | Cambio | Verificación | Estado |
|---|---|---|---|---|---|
| 1 | `v2/firmware/asm/uart_full_demo.S` | Línea 11 corrupta en la v1: `csrsi mstatus, 8` quedó partida por un texto pegado (`sw ra,0(sp) ...`), así que el programa de prueba de interrupciones no ensambla | Se restauró `csrsi mstatus, 8` (MIE = 1) | Ensambla con `make` | Hecho (sim) |
| 2 | `v2/firmware/asm/Makefile` | El Makefile de la v1 usa `riscv32-unknown-elf`, `-march=rv32i` y depende de `firmware_words` (para BRAM, no se usa en este SoC) | `CROSS ?= riscv-none-elf` (xPack); `-march=rv32i_zicsr`, que el ensamblador moderno exige para `csrw`/`csrsi`; programa elegible con `PROG=` | Ensambla con `make` | Hecho (sim) |
| 3 | `v2/sim/Makefile`, `v2/sim/config.v` | Makefile de la v1 con rutas a `../femto_UN/src` y `cores/` del repo del curso. El repo del curso tiene dos `config.v`: el de `cores/sim_spi_ram/` viene sin cerrar un `` `ifdef`` | Rutas relativas a `v2/rtl`; targets `run`, `sim`, `firmware`, `test_ram`, `ver_ram`, `clean`. Se usa `tinytapeout/config.v` (corregido por el profesor) | `make run` | Hecho (sim) |
| 4 | `v2/rtl/femtorv32_quark_un_irq.v`, `v2/rtl/femto.v` | Señales usadas antes de declararse (`instr`, `PC`, `funct3IsShift`, `writeBackData`, `LOAD_*` en el CPU; `cs`, `dpram_dout`, `spi_ram_rbusy/wbusy` en el SoC). Icarus Verilog 12+ (Fedora 44) lo rechaza con 73 errores | Declaraciones movidas al inicio del módulo; las definiciones pasan a `assign`. La lógica no cambia | Compila con Icarus 12 | Hecho (sim) |
| F1 | `v2/rtl/MappedSPIFlash.v` | Al salir del reset la flash pasaba un ciclo por `START`. El CPU pide la primera instrucción justo en ese ciclo (`rstrb` dura un ciclo), la flash no la ve, `rbusy` queda en 0 y el CPU ejecuta `0x00000000` en lugar de la instrucción en 0x0. **La primera instrucción de todo programa se perdía**; por eso los programas del curso la repiten (`lui t1, 0x400` dos veces) | En reset, `state <= WAIT_STRB` (una línea). Los programas con la instrucción repetida siguen funcionando | `test_ram_bytes.S` empieza con `li sp`: sin F1 la pila queda en 0x400 (flash) y el programa se cae en la primera llamada | Hecho (sim) |
| R1–R6 | `v2/rtl/MappedSPIRAM.v` (reescrito), `v2/rtl/femto.v` | Ver la tabla de abajo | Mismo esquema de SCK que la flash (ya validado en hardware); máscara de bytes; dirección alineada; little-endian; SCK quieto fuera de transferencias; WREN antes de cada WRITE. Puerto nuevo `wmask` (`femto.v` conecta `mem_wmask`), `word_address` pasa a llamarse `address` | `test_ram_bytes.S`: 13/13 OK, y el modelo del chip termina con los bytes esperados | Hecho (sim) |
| 5 | `v2/sim/tt_um_femto_TB.v` | Duración fija (~19 ms), no alcanza para programas largos; no había forma de ver los accesos a la RAM | `+tiempo_ms=N` (`make run TIEMPO_MS=N`); `+ram_log` (`RAM_LOG=1`) guarda cada lectura/escritura en `ram_log.txt`; vuelca al VCD las direcciones 0x100–0x10B del chip | — | Hecho (sim) |
| 6 | `v2/sim/tt_um_femto_ram.gtkw` (nuevo) | — | Vista de GTKWave para la RAM: lado CPU, bus SPI y contenido del chip | Todas las señales existen en el VCD | Hecho (sim) |
| 7 | `v2/firmware/asm/test_ram_bytes.S` (nuevo) | — (al inicio pone `s1`, `s2` y `t1` en 0: las subrutinas los guardan en la pila y sin valor inicial salían como X en las ondas) | Prueba de la RAM con `sw/sh/sb` y `lw/lh/lhu/lb/lbu`, escrituras seguidas y verificación de bytes vecinos; imprime `Tn OK` / `Tn FALLO valor` | Con la RAM de la v1 se cae en T1; con la v2 pasa todo | Hecho (sim) |
| 8 | `v2/sim/Makefile`, `v2/sim/hex/`, `v2/sim/tt_um_femto_ram_original.gtkw`, `docs/RAM.md` (nuevos) | Comparar la RAM nueva con la original en las mismas condiciones; simular sin toolchain RISC-V | `make test_ram_hex` (hex ya ensamblado), `make test_ram_original` (misma prueba con `v1_original/rtl/MappedSPIRAM.v`, `femto.v` adaptado por `sed`). `docs/RAM.md` explica cada cambio con las tramas SPI decodificadas del VCD | Original: `T1` y el programa se pierde; 573 de 1208 tramas llegan corridas 1 bit. Nuevo: 13/13 OK | Hecho (sim) |
| U2 | `v2/rtl/uart.v` | `tx_bitcount`, `txd_reg` y `rx_data` sin reset. En la simulación con compuertas el X inicial se propaga (pesimismo de X) y TXD queda en X desde el primer carácter; en RTL y en el chip no se nota | Reset de los tres registros. La lógica no cambia | Netlist v2: `T1 OK` a 3,233 ms, igual que RTL; RTL sigue 13/13 | Hecho (sim) |
| 9 | `v2/synth/` (nuevo), `v2/rtl/femto.v` | No había netlist de compuertas de la v2 | `synth.ys` (Yosys + `trimmed.lib` sky130 del curso) → `tt_um_femto_v2.v` (7 657 celdas). `femto.v`: puertos `VPWR`/`VGND` bajo `USE_POWER_PINS`, para que la netlist se conecte al testbench como la del chip | `make synth` | Hecho (sim) |
| 10 | `v2/sim/Makefile`, `v2/sim/tt_um_femto_TB.v`, `v2/sim/tt_um_femto_gl.gtkw`, `v2/sim/verilog_model/`, `v1_original/sim/tt_um_femto.v` | Simular en compuertas como `make tt_um_femto` del curso | Targets `tt_um_femto` (v2) y `tt_um_femto_original` (chip). `trap '' INT` y `setsid -f` para que tras Ctrl+C + `finish` se abra GTKWave. Testbench: decodifica TXD por líneas, aviso cada 1 ms, VCD reducido por defecto (`VCD_COMPLETO=1` para todo) | Netlist v2: misma salida y mismos tiempos que RTL. Ver `docs/POSTSINTESIS.md` | Hecho (sim) |

### Detalle de la RAM

| # | Problema en la v1 | Efecto | Corrección en v2 |
|---|---|---|---|
| R1 | En `RECEIVE` pasa a `START` sin guardar el último bit de MISO; muestrea con `clk_div` y no en el flanco de subida | Palabra leída corrida | Se muestrea con `clk_div_rise` y se guardan los 32 bits |
| R2 | Ignora `mem_wmask`: toda escritura manda 32 bits | `sb`/`sh` dañan los bytes vecinos | Se envían 1, 2 o 4 bytes según la máscara (la FM25V02 escribe byte a byte) |
| R3 | Usa `mem_address[15:0]` sin alinear | Un `sb` a A+1 escribe 4 bytes desde A+1 | Lecturas en la dirección alineada; escrituras en el byte exacto |
| R4 | Sin *swizzle* de bytes | `lb`/`lbu` leen el byte equivocado | Little-endian, igual que la flash |
| R5 | SCK corre siempre; restos sin usar (`edge_CLK`); `rd`/`wr` sin prioridad | Según la fase de SCK cuando baja `CS_N`, la trama llega corrida 1 bit: el chip recibe `0x04` (WRDI) en lugar de WRITE o `0x06` en lugar de READ (573 de 1208 tramas en la prueba). Explica la intermitencia en hardware | SCK solo durante la transferencia; `wr` tiene prioridad |
| R6 | No envía WREN. El modelo `spiram.v` borra WEL al final de cada WRITE, igual que el chip real | En el modelo, después de la primera escritura las demás se ignoran | `0x06` (CS_N alto) y luego `0x02` en cada escritura |

## Pendientes

| # | Tarea |
|---|---|
| H1 | Probar la RAM v2 en hardware (FPGA o siguiente chip) con `test_ram_bytes.S` |
| I2 | `uart_full_demo.S`: `j _start` reinicia todo en cada vuelta y la ISR no guarda registros (hoy no afecta porque solo toca `s2`) |
| I3 | Probar interrupciones en hardware con `ui_in[3]` |
| U1 | El `$write` del testbench (en `femto.v`, bajo `BENCH`) imprime cualquier escritura en la UART, también las del registro de control (`0x08`, `0x00`), y salen caracteres basura entre letras |

## Verificado en simulación

- **I1, interrupciones:** con `uart_full_demo.S`, `s2` cuenta cada pulso de `interrupt_request` una vez que `mstatus.MIE = 1`, y el programa principal sigue (imprime `Hello World / Op / R=`).
