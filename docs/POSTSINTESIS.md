# Simulación con compuertas: `make tt_um_femto`

Este documento explica qué hace `make tt_um_femto` en el repo del curso
([`cicamargoba/VLSI`](https://github.com/cicamargoba/VLSI), carpeta
`tinytapeout/`), por qué el profesor lo detiene con Ctrl+C y `finish`, y cómo
se hace lo mismo con la versión nueva (v2) en este repositorio.

## 1. Qué es `make tt_um_femto` del curso

```make
tt_um_femto:
	iverilog -DUSE_POWER_PINS -DFUNCTIONAL -DUNIT_DELAY=#1 -o tt_um_femto.vpp -s tt_um_femto_TB \
	   tt_um_femto_TB.v tt_um_femto.v cores/sim_spi_flash/spiflash.v \
	   verilog_model/sky130_fd_sc_hd.v cores/sim_spi_ram/spiram.v verilog_model/primitives.v
	./tt_um_femto.vpp
	gtkwave tt_um_femto_TB.vcd &
```

**No simula el RTL.** `tt_um_femto.v` es la **netlist del chip que se
fabricó**: 123 mil líneas de celdas sky130 conectadas entre sí. Tampoco es
la salida de la síntesis: es la netlist **post-layout**, la que sale al final
del flujo de Tiny Tapeout (OpenLane), después de colocar y rutear. Se nota en
lo que contiene:

| En `tt_um_femto.v` | Cantidad | Qué indica |
|---|---|---|
| `fill_*`, `decap_*`, `tapvpwrvgnd_1` | ~8 400 | Relleno y conexión a alimentación: se agregan al colocar las celdas en el layout |
| `clkbuf_*` | ~560 | Árbol de reloj (CTS), después de colocar |
| `dlygate4sd3_1` | 1 316 | Retardos para corregir *hold* después del ruteo |
| Pines `VPWR`/`VGND` en cada celda | — | Netlist con alimentación |

Cada archivo del comando cumple un papel:

| Archivo / opción | Papel |
|---|---|
| `tt_um_femto_TB.v` | Testbench: reloj de 25 MHz, reset, pulsos de interrupción, bytes por UART |
| `tt_um_femto.v` | El chip, en compuertas |
| `sky130_fd_sc_hd.v`, `primitives.v` | Qué hace cada celda sky130 (modelos de simulación de la PDK) |
| `spiflash.v`, `spiram.v` | La flash y la RAM de la placa, fuera del chip |
| `-DUSE_POWER_PINS` | Las celdas tienen pines `VPWR`/`VGND`; el testbench les pone 1 y 0 |
| `-DFUNCTIONAL` | Modelos sin tiempos: solo la función lógica de cada celda |
| `-DUNIT_DELAY=#1` | Cada celda tarda 1 unidad de tiempo, siempre igual |

Como no se carga un archivo SDF con los retardos reales del ruteo, **esta
simulación no dice si el chip cumple tiempos**. Dice si el circuito ya
colocado y ruteado hace lo mismo que el RTL.

## 2. Por qué el profesor espera y luego da Ctrl+C y `finish`

**Es lenta.** El RTL describe el procesador con unas pocas operaciones por
ciclo. La netlist son ~20 mil celdas, y cada una se evalúa por separado en
cada cambio de sus entradas. Además, el Makefile del curso vuelca al VCD
**todas** las señales, incluido el interior de cada celda (~150 mil
señales).

| Simulación | Tiempo real por 1 ms simulado | VCD por 1 ms |
|---|---|---|
| RTL (`make test_ram_hex`) | ~0,4 s | ~3 MB |
| Netlist v2, vista por defecto (`make tt_um_femto`) | ~20 s | ~21 MB |
| Netlist del chip, vista por defecto (`make tt_um_femto_original`) | ~90 s | ~280 MB |
| Netlist del chip, todo el VCD (como el curso) | varios minutos | ~1 GB |

*Medido en el entorno donde se preparó este repo (2 núcleos); en un
computador normal es algo más rápido, pero las proporciones son las mismas.*

El testbench termina solo (`$finish`) a los ~19 ms simulados, lo que con la
netlist completa tomaría mucho tiempo. Por eso el profesor deja correr la
simulación entre 30 s y 1 min y la detiene a mano:

1. **Ctrl+C.** vvp **no se cierra**: pausa la simulación y abre su consola
   interactiva:
   ```
   ** VVP Stop(0) **
   ** Flushing output streams.
   ** Current simulation time is 12475740000 ticks.
   >
   ```
2. **`finish`** (escrito en ese prompt `>`). vvp ejecuta `$finish`: termina la
   simulación **cerrando bien el VCD** hasta el instante en que se pausó.
   Después se abre GTKWave con lo simulado hasta ahí.

Otros comandos útiles en ese prompt: `cont` (sigue simulando), `time`
(muestra el tiempo actual), `help`.

Si en lugar de `finish` se cierra la terminal o se da Ctrl+C otra vez, vvp se
cae sin cerrar el VCD: GTKWave puede quejarse o mostrar el archivo cortado.

### Detalle del Makefile: `trap '' INT` y `setsid -f`

Ctrl+C no le llega solo a vvp: la terminal se lo manda a todo lo que corre
en primer plano, o sea a `make`, al shell que ejecuta la receta y a vvp. vvp
lo atrapa y abre su prompt, pero `make` y el shell se cortan. Con una receta
como la del curso, después de `finish` **GTKWave no se abre**: `make` termina
con `*** Interrupt` y no ejecuta la línea siguiente. En este repo la receta
queda así:

```make
trap '' INT; vvp tt_um_femto.vpp +firmware=$(GL_HEX) +tiempo_ms=$(TIEMPO_MS); \
setsid -f gtkwave tt_um_femto_TB.vcd tt_um_femto_gl.gtkw
```

- `trap '' INT`: el shell de la receta ignora Ctrl+C. vvp instala su propio
  manejador y lo sigue recibiendo, así que su prompt aparece igual.
- vvp y gtkwave en **la misma línea**: al terminar vvp, el shell sigue con
  gtkwave.
- `setsid -f` en lugar de `&`: con un `&` normal, GTKWave no alcanzaba a
  arrancar, porque `make`, interrumpido, termina enseguida. `setsid -f` lo
  lanza en una sesión aparte y vuelve de inmediato, igual que `&`.

Se comprobó simulando las teclas en una terminal: correr, Ctrl+C, `finish`
→ el VCD queda cerrado en el instante de la pausa y GTKWave se abre. `make`
igual imprime `*** Interrupt` al final; es normal. Sin Ctrl+C (por ejemplo
con `TIEMPO_MS=8`), GTKWave se abre al terminar, igual que en el curso.

## 3. La versión nueva en compuertas

La netlist del curso es la de la v1 (RAM original, flash que pierde la primera
instrucción). Para simular la v2 en compuertas hay que generar su propia
netlist:

```bash
cd v2/sim
make synth           # RTL v2 -> netlist sky130 con Yosys (../synth/tt_um_femto_v2.v)
make tt_um_femto     # simula esa netlist y abre GTKWave
```

`make synth` solo hace falta si se cambia el RTL: la netlist generada ya viene
en el repo. Requiere Yosys (viene en oss-cad-suite).

### Post-síntesis, no post-layout

La netlist de la v2 sale de **síntesis** (Yosys + la librería sky130 que usa
OpenLane), no de todo el flujo físico. Es el paso anterior al layout:

| | Netlist del chip (curso) | Netlist v2 (`make synth`) |
|---|---|---|
| Etapa | Post-layout (OpenLane completo) | Post-síntesis (Yosys) |
| Celdas | 19 537: ~9 200 de lógica (1 513 flip-flops), 8 421 de relleno, 1 920 de reloj y *hold* | 7 657, todas de lógica (1 650 flip-flops) |
| Relleno, árbol de reloj, retardos de *hold* | Sí | No (los agrega el layout) |
| Pines de alimentación en las celdas | Sí (`-DUSE_POWER_PINS`) | No; el top tiene `VPWR`/`VGND` para conectarse igual al testbench |
| Modelos de simulación | `sky130_fd_sc_hd.v` + `primitives.v` | Los mismos |
| Testbench, flash, RAM | Mismos | Mismos |

Funcionalmente las dos responden a la misma pregunta: **¿el circuito hecho de
compuertas hace lo mismo que el RTL?** Para tener la netlist post-layout de la
v2 hay que correr el flujo de Tiny Tapeout (LibreLane) con el RTL nuevo. La
netlist que resulte se simula con este mismo target:

```bash
make tt_um_femto NETLIST=ruta/a/la/netlist_post_layout.v
```

(si trae pines de alimentación en las celdas, hay que agregar
`-DUSE_POWER_PINS` como en `tt_um_femto_original`).

### Targets y opciones

| Comando | Qué hace |
|---|---|
| `make synth` | Sintetiza la v2 (`../synth/synth.ys`). Resumen de celdas en `../synth/synth_stat.txt` |
| `make tt_um_femto` | Netlist v2 + modelos sky130 + flash + RAM, con el mismo comando que el curso |
| `make tt_um_femto_original` | La netlist del chip fabricado (`v1_original/sim/tt_um_femto.v`), con el testbench de este repo |

| Opción | Por defecto | Efecto |
|---|---|---|
| `TIEMPO_MS=N` | 0 (duración original, ~19 ms) | Termina sola a los N ms simulados, sin Ctrl+C. Ej.: `make tt_um_femto TIEMPO_MS=8` |
| `GL_HEX=archivo` | `hex/test_ram_bytes.hex` | Programa que se carga en la flash para `tt_um_femto`. Ej.: `GL_HEX=hex/uart_full_demo.hex` |
| `GL_HEX_V1=archivo` | `hex/uart_full_demo.hex` | Programa para `tt_um_femto_original` (con `test_ram_bytes` el chip viejo falla por la flash y la RAM originales) |
| `NETLIST=archivo` | `../synth/tt_um_femto_v2.v` | Otra netlist (por ejemplo, una post-layout) |
| `VCD_COMPLETO=1` | 0 | Vuelca también el interior de cada celda, como el curso (VCD enorme y más lento) |

### Qué se agregó al testbench para las compuertas

Con la netlist no existe el `$write` de `femto.v` que imprime la UART en la
simulación RTL, y casi no hay señales internas con nombre. Por eso, solo en
la simulación con compuertas, el testbench:

- **Decodifica el pin TXD** y muestra en la terminal cada línea que imprime el
  programa, con su tiempo. El bit de la UART dura 16 × 13 = 208 ciclos de
  reloj (divisor de `uart.v`).
  ```
  [  3.233 ms] UART: T1 OK
  [  6.552 ms] UART: T2 OK
  ```
- **Avisa el avance** cada 1 ms simulado (`[  2.000 ms] simulando...`), así
  se sabe cuánto lleva antes de dar Ctrl+C.
- **Vuelca al VCD** las señales del testbench (reloj, reset, TXD, buses de la
  flash y la RAM) y, por defecto, solo el nivel de la netlist, sin el
  interior de las celdas.

## 4. Qué mirar

### En la terminal

Con `make tt_um_femto` y el programa `test_ram_bytes`:

```
[  1.000 ms] simulando...
[  2.000 ms] simulando...
[  3.000 ms] simulando...
[  3.233 ms] UART: T1 OK
...
[  6.552 ms] UART: T2 OK
```

Los tiempos coinciden **exactamente** con la simulación RTL: la netlist hace
lo mismo, ciclo por ciclo. Con 30 s a 1 min de espera se llega a ~2-3 ms
simulados. Para ver `T1 OK` hay que pasar de 3,3 ms.

Prueba completa en compuertas (`make tt_um_femto TIEMPO_MS=50`):

```
[  3.233 ms] UART: T1 OK
[  6.552 ms] UART: T2 OK
 ...
[ 45.125 ms] UART: T13 OK
[ 47.101 ms] UART: FIN
```

| | RTL (`make test_ram_hex`) | Netlist v2 (`make tt_um_femto TIEMPO_MS=50`) |
|---|---|---|
| Resultado | 13/13 OK, `FIN` | 13/13 OK, `FIN` |
| Tiempo de `T1 OK` / `FIN` | 3,233 ms / 47,1 ms | 3,233 ms / 47,101 ms |
| Contenido final de la RAM (0x100–0x10B) | `11 AA EF BE 78 56 34 12 F0 DE BC 9A` | `11 AA EF BE 78 56 34 12 F0 DE BC 9A` |
| Tiempo real | ~30 s | ~17 min |
| VCD | ~0,3 GB | **~3,3 GB** (bórralo con `make clean`) |

### En GTKWave

`make tt_um_femto` abre la vista `tt_um_femto_gl.gtkw`, que sirve para las
dos netlists porque solo usa pines y el modelo de la RAM:

| Grupo | Señales | Qué ver |
|---|---|---|
| Control | `CLK`, `RESET`, `interrupt_request` | Reset hasta ~0,24 µs; los 20 pulsos de interrupción del testbench |
| UART | `TXD`, `RXD` | Cada carácter: bit de inicio en 0, 8 bits, parada en 1. Nunca debe haber X (rojo) |
| Flash SPI | `spi_cs`, `spi_clk`, `spi_mosi`, `spi_miso` | Una trama por instrucción: `03` + dirección (MOSI) y la instrucción (MISO) |
| RAM SPI | `spi_cs_n_ram`, `spi_clk_ram`, ... | WREN y WRITE, y READ, igual que en RTL (ver `docs/RAM.md`) |
| RAM: contenido del chip | `mem[256..267]` | `11 22 33 44` a ~0,11 ms, `AA` en 0x101 a ~16,8 ms, etc. |
| Pines del chip | `uo_out`, `ui_in` | Los 8 pines de salida y entrada como bus |

Primeras tramas en la netlist v2 (iguales a las del RTL):

```
FLASH   0.3 us  03 00 00 00 -> 37 01 01 00   (lui sp, 0x10: la primera instrucción se lee bien)
        8.1 us  03 00 00 04 -> 13 01 01 40   (addi sp, sp, 0x400)
RAM    86.1 us  06                           (WREN)
       89.8 us  02 00 01 00 11 22 33 44      (sw 0x44332211 en 0x10100)
      125.8 us  03 00 01 00 -> 11 22 33 44   (lw: devuelve lo escrito)
```

**Señales internas.** Siguen existiendo los registros con nombre, pero
separados bit por bit, por ejemplo `femto0.CPU.PC[0]` … `femto0.CPU.PC[23]`.
En GTKWave: en el panel *SST* abre `tt_um_femto_TB → uut`, escribe
`femto0.CPU.PC` en el filtro, selecciona todos los bits, agrégalos y, con clic
derecho, usa **Combine Down** para verlos como un bus. Los cables sin nombre
se llaman `_01234_` y no sirven para leer.

## 5. Lo que encontró la simulación con compuertas

La primera corrida de la v2 en compuertas **no imprimía nada**. Los buses de
flash y RAM estaban bien, pero TXD se volvía X en el primer bit de datos:

```
462.541 us  TXD = 0   (bit de inicio de la 'T')
462.541 us  femto0.per_uart.uart0.txd_reg[0..6] = x
470.861 us  TXD = x   (primer bit de datos)
```

`d_in_uart` tenía el carácter correcto (`0x54`), pero `txd_reg` quedaba en X
al cargarlo. La causa: en `uart.v`, `tx_bitcount` y `txd_reg` **no tenían
reset**.

- En RTL, la carga `txd_reg <= tx_data` tiene prioridad y el valor inicial no
  importa: un `if` con X toma la rama `else`.
- En compuertas, la síntesis mezcla las condiciones en una sola lógica, y el X
  del contador sin inicializar se propaga aunque lógicamente no debería influir
  (*pesimismo de X*).
- En el chip real los registros arrancan en 0 o 1, nunca en X, así que
  funciona. Por eso el chip sí imprime.

**Corrección (v2):** reset para `tx_bitcount`, `txd_reg` y `rx_data` en
`uart.v`. Con eso la netlist imprime `T1 OK` a los 3,233 ms, igual que el
RTL. La lógica no cambia (la simulación RTL da los mismos resultados).

La netlist del chip fabricado tiene la misma UART, pero en ella **no** pasa:
con `make tt_um_femto_original` y `uart_full_demo`, `txd_reg` carga la `H`
(`0x48`) a los 341 µs y TXD transmite `Hell…` sin ningún X. La síntesis de
OpenLane armó esa lógica de otra manera y el X no se filtra. El pesimismo de
X depende de cómo queda sintetizado el circuito, así que conviene no dejar
registros sin reset aunque el RTL funcione.

## 6. Resumen de comandos

```bash
cd v2/sim

# Como en clase: correr, esperar 30 s - 1 min, Ctrl+C, escribir finish
make tt_um_femto

# Sin Ctrl+C: que pare sola a los 8 ms (ve T1 OK y T2 OK)
make tt_um_femto TIEMPO_MS=8

# La prueba completa en compuertas (~17 min, VCD de ~3,3 GB)
make tt_um_femto TIEMPO_MS=50

# El chip fabricado (netlist del curso), para comparar
make tt_um_femto_original

# Regenerar la netlist después de cambiar el RTL
make synth
```
