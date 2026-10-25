# RISC-V-Cambios

Repositorio creado con el fin de arreglar algunos problemas que se tenían con el
primer procesador **femto_UN** (FemtoRV32 *quark* + UART + flash SPI + RAM SPI,
fabricado en Tiny Tapeout) y añadir algunas funciones nuevas.

Se parte de la versión original del curso de VLSI (Universidad Nacional de
Colombia, sede Manizales): lo que está bien se deja igual, lo que está mal se
corrige y lo que se puede mejorar se mejora. Cada cambio queda registrado en
[`docs/CHANGES.md`](docs/CHANGES.md) con su motivo y cómo se verificó.

**Cambios en la RAM, original vs. nuevo:** [`docs/RAM.md`](docs/RAM.md)

**Simulación con compuertas (`make tt_um_femto`), Ctrl+C y `finish`:** [`docs/POSTSINTESIS.md`](docs/POSTSINTESIS.md)

## Objetivos de la v2

| Bloque | Estado en v1 | Objetivo en v2 |
|---|---|---|
| Flash SPI (`MappedSPIFlash.v`) | Corregida (32 bits, muestreo en flanco de subida) | Se mantiene |
| Flash: primera instrucción | Se perdía al salir del reset | Corregido (F1) |
| RAM SPI (`MappedSPIRAM.v`) | Funciona con palabras de 32 bits, con errores | Reescrita: 8/16/32 bits, little-endian, WREN — pasa `test_ram_bytes` en simulación ([detalle](docs/RAM.md)) |
| Interrupciones (`femtorv32_quark_un_irq.v`) | Versión del profesor, sin verificar | Funcionan en simulación |
| UART (`uart.v`) | Registros sin reset: en compuertas TXD queda en X | Con reset; la netlist v2 imprime igual que el RTL |
| Netlist de compuertas | Solo la del chip fabricado (v1) | `make synth` genera la de la v2 y `make tt_um_femto` la simula ([detalle](docs/POSTSINTESIS.md)) |

## Estructura

```
v1_original/          Copia intacta de la versión anterior (solo referencia, no se edita)
  rtl/                  femto_UN/src del repo del curso
  sim/                  testbench, modelos de memoria y Makefile de tinytapeout/
  firmware/             programas en ensamblador y herramientas
v2/                   Versión nueva (aquí se trabaja)
  rtl/                  RTL del SoC
  sim/                  testbench, modelos spiflash/spiram, Makefile y vistas de GTKWave
    hex/                  programas ya ensamblados (test_ram_bytes, uart_full_demo)
    verilog_model/        modelos de simulación de las celdas sky130 (de la PDK)
  firmware/asm/         programas de prueba
  synth/                síntesis con Yosys: script, librería sky130 y netlist v2
docs/
  CHANGES.md            registro de cambios v1 -> v2 y pendientes
  RAM.md                cambios en la RAM: original vs. nuevo, con ondas
  POSTSINTESIS.md       simulación con compuertas (make tt_um_femto)
  img/                  imágenes de los documentos
```

Al inicio `v2/` es igual a `v1_original/` en los archivos que usa el SoC.
Así cada corrección se ve como un *diff* limpio contra la versión vieja:

```bash
diff v1_original/rtl/MappedSPIRAM.v v2/rtl/MappedSPIRAM.v
```

## Uso rápido

Requisitos (Fedora): Icarus Verilog, GTKWave y el toolchain xPack
`riscv-none-elf-gcc` en el `PATH`.

```bash
cd v2/sim
make firmware   # ensambla v2/firmware/asm y copia firmware_flash.hex
make sim        # simula y abre GTKWave
make run        # solo simula, sin abrir GTKWave

make test_ram          # prueba de la RAM: ensambla test_ram_bytes, simula 80 ms
                       # guardando cada acceso en ram_log.txt, y abre GTKWave con su vista
make test_ram_hex      # lo mismo con el programa ya ensamblado (sin toolchain RISC-V)
make test_ram_original # la misma prueba con la RAM ORIGINAL, para comparar

make tt_um_femto       # simulación con compuertas de la v2 (como en el curso);
                       # Ctrl+C y `finish` para detenerla, o TIEMPO_MS=8
make tt_um_femto_original  # la netlist del chip fabricado
make synth             # regenera la netlist de la v2 (requiere Yosys)
```

Opciones de `make run`: `TIEMPO_MS=80` alarga la simulación; `RAM_LOG=1`
guarda cada lectura/escritura de la RAM en `v2/sim/ram_log.txt`. Para cargar otro programa:
`make firmware PROG=test_ram_bytes`.

## Origen

`v1_original/` se tomó del repositorio del curso
[`cicamargoba/VLSI`](https://github.com/cicamargoba/VLSI), commit `42705d7`
(14 de octubre de 2026), carpetas `femto_UN/src`, `tinytapeout/` y
`femtoRV/firmware/asm`. Las bibliotecas de celdas sky130 y la netlist de
compuertas no se copiaron por tamaño; están en el repositorio del curso.
