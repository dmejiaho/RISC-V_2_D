# =============================================================================
#  Firmware de prueba para femto_UN v2
#  Toolchain: xPack riscv-none-elf-gcc (en Fedora el paquete del sistema no
#  trae sysroot). Para otro toolchain: make CROSS=riscv64-unknown-elf
#
#  Salidas:
#     firmware_flash.hex    -> para la simulación (modelo spiflash.v)
#     firmware.bin          -> binario plano
#     firmware_shifted.bin  -> binario corrido 1 bit, para grabar en la flash
#                              real / emulador ESP32 (igual que en la v1)
#
#  Cambiar el programa: make PROG=test_ram_bytes  (el programa debe tener _start)
# =============================================================================

# Programa principal (sin .S). Ej.: make PROG=test_ram_bytes
PROG    ?= uart_full_demo
OBJECTS  = $(PROG).o putchar.o

CROSS   ?= riscv-none-elf
AS      = $(CROSS)-as
LD      = $(CROSS)-ld
OBJCOPY = $(CROSS)-objcopy
OBJDUMP = $(CROSS)-objdump
AFLAGS  = -march=rv32i_zicsr -mabi=ilp32

all: firmware_flash.hex firmware_shifted.bin firmware.lst

firmware.elf: $(OBJECTS) bram.ld
	$(LD) -T bram.ld -m elf32lriscv -nostdlib -Map firmware.map -N -o $@ $(OBJECTS)

firmware_flash.hex: firmware.elf
	$(OBJCOPY) -O verilog $< $@

firmware.bin: firmware.elf
	$(OBJCOPY) -O binary $< $@

firmware_shifted.bin: firmware.bin
	python3 fix_shift.py $< $@ --bits 1 --dir right --hex-output firmware_shifted.hex

firmware.lst: firmware.elf
	$(OBJDUMP) -h -S $< > $@

%.o: %.S
	$(AS) $(AFLAGS) -c $< -o $@

clean:
	rm -f *.o *.elf *.bin *.map *.lst firmware_flash.hex firmware_shifted.hex

.PHONY: all clean
