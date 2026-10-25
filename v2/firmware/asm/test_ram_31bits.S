# =============================================================================
# test_ram_31bits.S — muestra el error de los 31 bits de la RAM original
#
# Escribe 0x9ABCDEF0 en la RAM (0x00010100) y lo vuelve a leer en a1.
# El bit 31 de este valor es 1, así que si la RAM pierde ese bit se nota:
#     RAM original -> a1 = 0x1ABCDEF0   (solo guarda 31 bits)
#     RAM nueva    -> a1 = 0x9ABCDEF0   (guarda los 32 bits)
#
# Los nop solo ajustan cuándo ocurre cada acceso: con la RAM original, la
# lectura llega bien alineada al chip en este punto, así que lo único que
# falla es el bit perdido. Empieza con nop para no depender de la primera
# instrucción.
# =============================================================================
.section .text
.global _start
_start:
    nop
    lui  s0, 0x10
    addi s0, s0, 0x100          # s0 = 0x00010100 (RAM)
    li   t0, 0x9ABCDEF0
    nop
    nop
    nop
    nop
    nop
    sw   t0, 0(s0)              # escribe 0x9ABCDEF0
    nop
    nop
    lw   a1, 0(s0)              # lo lee en a1
fin:
    j    fin
