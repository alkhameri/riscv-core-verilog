    .section .text.init
    .globl _start
    .option norvc
    .option norelax

    .macro test number
    li gp, \number
    .endm
    .macro check reg, value
    li t6, \value
    bne \reg, t6, fail
    .endm
    .macro expected cause, value
    li s8, \cause
    li s9, \value
    la s10, 2f
    la s11, 1f
    .endm
    .macro enter_user destination
    la t0, \destination
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    mret
    .endm

_start:
    la sp, _stack_top
    la t0, trap_handler
    csrw mtvec, t0
    li s7, 0
    li s0, 0x80010000

    test 2
    li t0, 0x80ff7f01
    sw t0, 0(s0)
    lb t1, 3(s0)
    check t1, -128
    lbu t1, 3(s0)
    check t1, 128
    lh t1, 2(s0)
    check t1, -32513
    lhu t1, 2(s0)
    check t1, 0x80ff
    li t0, 0x1234
    sh t0, 2(s0)
    sb t0, 1(s0)
    lw t1, 0(s0)
    check t1, 0x12343401
    add t2, t1, t1
    sw t2, 4(s0)
    lw t3, 4(s0)
    check t3, 0x24686802
    lw zero, 0(s0)

    test 3
    li t0, -1
    li t1, 1
    blt t0, t1, 1f
    j fail
1:  bgeu t0, t1, 1f
    j fail
1:  beq t0, t1, fail
    bne t1, t1, fail
    bltu t0, t1, fail
    bge t0, t1, fail
    jal ra, call_one
    check a0, 42
    la t0, 1f
    ori t0, t0, 1
    jalr t1, 0(t0)
    j fail
1:  la t0, 1b
    addi t0, t0, -4
    bne t0, t1, fail

    test 4
    li t0, -2147483648
    li t1, -1
    div t2, t0, t1
    check t2, -2147483648
    rem t2, t0, t1
    check t2, 0
    div t2, t0, zero
    check t2, -1
    rem t2, t0, zero
    check t2, -2147483648
    mulh t2, t0, t1
    check t2, 0
    mulhsu t2, t0, t1
    check t2, 0x80000000
    mulhu t2, t0, t1
    check t2, 0x7fffffff

    test 5
    li t0, 10
    sw t0, 0(s0)
    li t1, 3
    amoadd.w.aqrl t2, t1, (s0)
    check t2, 10
    lw t2, 0(s0)
    check t2, 13
    lw t1, 0(s0)
    mul t2, t1, t1
    check t2, 169
    li t1, 3
    lr.w.aq t2, (s0)
    sc.w.rl t3, t1, (s0)
    check t3, 0
    sc.w t3, t0, (s0)
    check t3, 1
    lr.w t2, (s0)
    sw t0, 4(s0)
    sc.w t3, t0, (s0)
    check t3, 1
    lr.w zero, (s0)
    sc.w t3, t0, (s0)
    check t3, 0

    test 6
    li t0, 0x123
    csrrw t1, mscratch, t0
    check t1, 0
    csrrsi t1, mscratch, 4
    check t1, 0x123
    csrrci t1, mscratch, 3
    check t1, 0x127
    csrr t1, mscratch
    check t1, 0x124
    csrr t1, mhartid
    check t1, 0
    csrrwi t1, mscratch, 7
    check t1, 0x124
    csrr t1, mscratch
    check t1, 7
    li t0, 5
    csrw mcountinhibit, t0
    li t0, 0x12345678
    csrw mcycle, t0
    csrr t1, mcycle
    bne t0, t1, fail
    csrw minstret, t0
    csrr t1, minstret
    bne t0, t1, fail
    csrw mcountinhibit, zero

    test 7
    expected 2, -1
1:  .word 0xffffffff
2:  expected 2, 1
1:  .word 0x12340001 // unsupported 16-bit encoding; upper mtval bits must be zero
2:  expected 11, 0
1:  ecall
2:  li s8, 3
    la s9, 1f
    la s10, 2f
    la s11, 1f
1:  ebreak
2:  expected 4, 0x80010001
1:  lw t0, 1(s0)
2:  expected 6, 0x80010002
1:  sw t0, 2(s0)
2:  li t0, 0x90000000
    expected 5, 0x90000000
1:  lw zero, 0(t0)
2:  expected 7, 0x90000000
1:  sw t1, 0(t0)
2:  expected 7, 0x90000000
1:  amoadd.w t2, t1, (t0)
2:  expected 5, 0x90000000
1:  lr.w t2, (t0)
2:  li s8, 0
    la s9, 1f
    addi s9, s9, 2
    la s10, 2f
    la s11, 1f
1:  .word 0x00000163 // beq x0,x0,+2: target misalignment
2:  .word 0x00001163 // untaken bne x0,x0,+2 must not trap

    test 8
    // A write to a read-only CSR traps even when the source value is zero.
    li t0, 0
    li s8, 2
    la s9, 1f
    lw s9, 0(s9)
    la s10, 2f
    la s11, 1f
1:  csrrs t1, mhartid, t0
2:  li s8, 1
    li s9, 0x90000000
    li s11, 0x90000000
    la s10, 2f
    li t0, 0x90000000
    jr t0
2:
    test 9
    // Self-modifying code must refetch after FENCE.I, including stale BTB data.
    la t0, mutable_code
    jalr ra, 0(t0)
    check a0, 1
    li t1, 0x00900513 // addi a0,zero,9
    sw t1, 0(t0)
    fence.i
    jalr ra, 0(t0)
    check a0, 9

    test 10
    // User code is RX, user data is RW. Unmatched addresses are denied.
    li t0, 0x20001fff
    csrw pmpaddr0, t0
    li t0, 0x20005fff
    csrw pmpaddr1, t0
    li t0, 0x1b1d
    csrw pmpcfg0, t0
    expected 8, 0
    la s11, user_ecall
    enter_user user_ecall
2:  expected 7, 0x80000000
    la s11, user_store
    li t0, 0x80000000
    mv a1, t0
    enter_user user_store
2:  li s8, 2
    la s9, user_csr
    lw s9, 0(s9)
    la s10, 2f
    la s11, user_csr
    enter_user user_csr
2:  li s8, 1
    li s9, 0x80010000
    la s10, 2f
    li s11, 0x80010000
    li t0, 0x80010000
    csrw mepc, t0
    li t0, 0x1800
    csrc mstatus, t0
    mret
2:  // MPRV applies the U-mode data permissions to machine-mode loads/stores.
    li t0, 0x20000
    csrw mstatus, t0
    li a1, 0x80000000
    expected 7, 0x80000000
1:  sw zero, 0(a1)
2:  csrw mstatus, zero

    test 11
    // Locked NA4 region: disallow stores even in M mode; lock address/config.
    csrw pmpcfg0, zero
    li t0, 0x20004000
    csrw pmpaddr0, t0
    li t1, 0x91
    csrw pmpcfg0, t1
    csrw pmpaddr0, zero
    csrr t2, pmpaddr0
    bne t2, t0, fail
    csrw pmpcfg0, zero
    csrr t2, pmpcfg0
    bne t2, t1, fail
    expected 7, 0x80010000
1:  sw zero, 0(s0)
2:
    test 12
    // Software interrupt occurs between instructions and returns to the saved PC.
    li s8, 0x80000003
    li s9, 0
    li t0, 8
    csrw mie, t0
    csrs mstatus, t0
    li t1, 0x02000000
    li t2, 1
    sw t2, 0(t1)
1:  lw t2, 0(t1)
    bnez t2, 1b
    csrw mie, zero
    csrci mstatus, 8

    test 13
    // Runtime prediction disable preserves architectural behavior.
    csrw 0x7c0, zero
    li t0, 32
1:  addi t0, t0, -1
    bnez t0, 1b
    csrwi 0x7c0, 1
    li t0, 32
1:  addi t0, t0, -1
    bnez t0, 1b

    test 14
    la t0, interrupt_vectors
    ori t0, t0, 1
    csrw mtvec, t0
    li s8, 0x80000003
    li s9, 0
    li t0, 8
    csrw mie, t0
    csrs mstatus, t0
    li t1, 0x02000000
    li t2, 1
    sw t2, 0(t1)
1:  lw t2, 0(t1)
    bnez t2, 1b
    csrw mie, zero
    csrci mstatus, 8
    expected 11, 0
1:  ecall // synchronous exception still uses the base in vectored mode
2:
    check s7, 22
    test 15
    // Locking a TOR entry also locks the previous entry's address register.
    li t0, 0x24000000
    csrw pmpaddr2, t0
    li t1, 0x24000004
    csrw pmpaddr3, t1
    li t1, 0x89000091
    csrw pmpcfg0, t1
    csrw pmpaddr2, zero
    csrr t2, pmpaddr2
    bne t2, t0, fail

    li t0, 0x10000010
    li t1, 1
    sw t1, 0(t0)
1:  j 1b

call_one:
    mv a2, ra
    jal t0, call_two
    jr a2
call_two:
    li a0, 42
    jr t0
mutable_code:
    li a0, 1
    ret
user_ecall:
    ecall
    j fail
user_store:
    sw zero, 0(a1)
    j fail
user_csr:
    csrr t0, mstatus
    j fail

    .align 2
trap_handler:
    mul zero, zero, zero // regression: the first instruction after a fault may stall
    csrr t3, mcause
    bne t3, s8, fail
    csrr t4, mtval
    bne t4, s9, fail
    addi s7, s7, 1
    bltz t3, interrupt_return
    csrr t5, mepc
    bne t5, s11, fail
    csrw mepc, s10
    li t6, 0x1800
    csrs mstatus, t6
    mret
interrupt_return:
    li t3, 0x02000000
    sw zero, 0(t3)
    mret
fail:
    li t0, 0x10000010
    sw gp, 0(t0)
1:  j 1b

    .balign 64
interrupt_vectors:
    j trap_handler
    j fail
    j fail
    j trap_handler // machine software interrupt at base + 4*3
