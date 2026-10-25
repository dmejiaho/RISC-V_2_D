# v1_original — versión anterior (solo referencia)

Copia intacta, sin modificaciones, del repositorio del curso
[`cicamargoba/VLSI`](https://github.com/cicamargoba/VLSI), commit `42705d7`:

| Carpeta aquí | Origen en el repo del curso |
|---|---|
| `rtl/` | `femto_UN/src/` |
| `sim/` | `tinytapeout/` (testbench, Makefile, hex, gtkw) + `tinytapeout/cores/sim_spi_flash/spiflash.v` + `tinytapeout/cores/sim_spi_ram/spiram.v` + `tinytapeout/config.v` (versión corregida por el profesor; no la de `cores/sim_spi_ram/`) |
| `firmware/asm/` | `femtoRV/firmware/asm/` (fuentes, Makefile, linker script, scripts) |
| `firmware/firmware_words_src/` | `femtoRV/firmware/firmware_words_src/` (solo fuente) |

No se edita: los cambios van en `../v2/` y se registran en `../docs/CHANGES.md`.
El `Makefile` de `sim/` conserva las rutas originales del repo del curso, así
que no corre desde esta carpeta.
