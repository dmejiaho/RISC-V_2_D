# =============================================================================
# test_ram_bytes.S — prueba de la RAM SPI con accesos de 32, 16 y 8 bits
#
# La RAM está mapeada en 0x00010000. Las pruebas usan la zona 0x00010100;
# la pila queda aparte, en 0x00010400.
#
# Por cada prueba se imprime por UART:
#     "Tn OK"                    si el valor leído es el esperado
#     "Tn FALLO xxxxxxxx"        con el valor que se leyó
# Al final: "FIN".
#
# Contenido esperado de la RAM (byte por dirección) al terminar:
#     0x100: 11 AA EF BE     0x104: 78 56 34 12     0x108: F0 DE BC 9A
# =============================================================================

.equ RAM_TEST, 0x00010100

.section .text
.global _start
_start:
    li    sp, 0x00010400          # pila en la RAM, lejos de la zona de prueba
    li    s0, RAM_TEST            # s0 = dirección base de las pruebas
    li    s3, 0                   # s3 = número de prueba
    li    s1, 0                   # s1, s2 y t1 se guardan en la pila en las subrutinas
    li    s2, 0                   # (putchar guarda t1); sin valor inicial salen como X
    li    t1, 0                   # (rojo) en la simulación

    # ---- T1: sw / lw ---------------------------------------------------
    li    t0, 0x44332211
    sw    t0, 0(s0)
    lw    a1, 0(s0)
    li    a2, 0x44332211
    call  check

    # ---- T2..T5: lbu de cada byte (orden little-endian) -----------------
    lbu   a1, 0(s0)
    li    a2, 0x11
    call  check
    lbu   a1, 1(s0)
    li    a2, 0x22
    call  check
    lbu   a1, 2(s0)
    li    a2, 0x33
    call  check
    lbu   a1, 3(s0)
    li    a2, 0x44
    call  check

    # ---- T6: sb en el byte 1, el resto no debe cambiar ------------------
    li    t0, 0xAA
    sb    t0, 1(s0)
    lw    a1, 0(s0)
    li    a2, 0x4433AA11
    call  check

    # ---- T7: sh en la media palabra alta --------------------------------
    li    t0, 0xBEEF
    sh    t0, 2(s0)
    lw    a1, 0(s0)
    li    a2, 0xBEEFAA11
    call  check

    # ---- T8..T10: lecturas con signo ------------------------------------
    lh    a1, 2(s0)
    li    a2, 0xFFFFBEEF
    call  check
    lhu   a1, 2(s0)
    li    a2, 0x0000BEEF
    call  check
    lb    a1, 1(s0)
    li    a2, 0xFFFFFFAA
    call  check

    # ---- T11..T12: escrituras seguidas (cada WRITE necesita su WREN) -----
    li    t0, 0x12345678
    sw    t0, 4(s0)
    li    t0, 0x9ABCDEF0
    sw    t0, 8(s0)
    lw    a1, 4(s0)
    li    a2, 0x12345678
    call  check
    lw    a1, 8(s0)
    li    a2, 0x9ABCDEF0
    call  check

    # ---- T13: la primera palabra no se dañó -----------------------------
    lw    a1, 0(s0)
    li    a2, 0xBEEFAA11
    call  check

    la    a0, msg_fin
    call  putstring
fin:
    j     fin


# -----------------------------------------------------------------------------
# check: compara a1 (leído) con a2 (esperado) e imprime el resultado
# -----------------------------------------------------------------------------
check:
    addi  sp, sp, -8
    sw    ra, 0(sp)
    sw    a1, 4(sp)
    addi  s3, s3, 1

    li    a0, 'T'
    call  putchar
    mv    a0, s3
    call  putdec
    li    a0, ' '
    call  putchar

    lw    a1, 4(sp)
    beq   a1, a2, .Lok
    la    a0, msg_fallo
    call  putstring
    lw    a0, 4(sp)
    call  puthex
    j     .Lnl
.Lok:
    la    a0, msg_ok
    call  putstring
.Lnl:
    li    a0, '\n'
    call  putchar
    lw    ra, 0(sp)
    addi  sp, sp, 8
    ret

# putdec: imprime a0 en decimal (0..99)
putdec:
    addi  sp, sp, -8
    sw    ra, 0(sp)
    sw    s1, 4(sp)
    li    t2, 10
    li    s1, 0
.Ldiv:                            # s1 = a0 / 10, a0 = a0 % 10
    blt   a0, t2, .Ldiv_fin
    addi  a0, a0, -10
    addi  s1, s1, 1
    j     .Ldiv
.Ldiv_fin:
    mv    t3, a0
    beqz  s1, .Lunidad
    addi  a0, s1, '0'
    call  putchar
.Lunidad:
    addi  a0, t3, '0'
    call  putchar
    lw    s1, 4(sp)
    lw    ra, 0(sp)
    addi  sp, sp, 8
    ret

# puthex: imprime a0 como 8 dígitos hexadecimales
puthex:
    addi  sp, sp, -12
    sw    ra, 0(sp)
    sw    s1, 4(sp)
    sw    s2, 8(sp)
    mv    s1, a0
    li    s2, 8
.Lhex:
    srli  a0, s1, 28
    li    t2, 10
    blt   a0, t2, .Ldig
    addi  a0, a0, 'A' - 10
    j     .Lput
.Ldig:
    addi  a0, a0, '0'
.Lput:
    call  putchar
    slli  s1, s1, 4
    addi  s2, s2, -1
    bnez  s2, .Lhex
    lw    s2, 8(sp)
    lw    s1, 4(sp)
    lw    ra, 0(sp)
    addi  sp, sp, 12
    ret

# putstring: imprime la cadena terminada en 0 que empieza en a0
putstring:
    addi  sp, sp, -8
    sw    ra, 0(sp)
    sw    s1, 4(sp)
    mv    s1, a0
.Lstr:
    lbu   a0, 0(s1)
    beqz  a0, .Lstr_fin
    call  putchar
    addi  s1, s1, 1
    j     .Lstr
.Lstr_fin:
    lw    s1, 4(sp)
    lw    ra, 0(sp)
    addi  sp, sp, 8
    ret

.section .rodata
msg_ok:    .asciz "OK"
msg_fallo: .asciz "FALLO "
msg_fin:   .asciz "FIN\n"
