OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY { RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128K }
SECTIONS {
    .text : { *(.text.init) *(.text*) *(.rodata*) } > RAM
    .data : { *(.data*) *(.sdata*) } > RAM
    .bss (NOLOAD) : { *(.bss*) *(.sbss*) *(COMMON) } > RAM
    . = ALIGN(16);
    __heap_start = .;
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
