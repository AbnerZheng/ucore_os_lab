#include <asm.h>

# 启动CPU: 切换到32位保护模式，跳转到C代码
# BIOS将该代码从硬盘的第一个扇区读入到硬件地址0x7c00，然后开始在实模式
# 下执行, 将%cs设为0， %ip设为7c00.

.set PROT_MODE_CSEG,        0x8                     # 内核代码段选择器
.set PROT_MODE_DSEG,        0x10                    # 内核数据段选择器
.set CR0_PE_ON,             0x1                     # 保护模式使能标志

# 开始地址应该为 0:7c00, 在实模式下，运行的bootloader的起始地址
.globl start
start:
.code16                                             # Assemble for 16-bit mode
    cli                                             # 禁用中断
    cld                                             # String operations increment

    # Set up the important data segment registers (DS, ES, SS).
    xorw %ax, %ax                                   # Segment number zero
    movw %ax, %ds                                   # -> Data Segment
    movw %ax, %es                                   # -> Extra Segment
    movw %ax, %ss                                   # -> Stack Segment

    # 使能A20
    # 为了向下兼容，物理地址线第20号绑定为0， 所以高于1MB的地址
    #  For backwards compatibility with the earliest PCs, physical
    #  address line 20 is tied low, so that addresses higher than
    #  1MB wrap around to zero by default. This code undoes this.
seta20.1:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.1

    movb $0xd1, %al                                 # 0xd1 -> port 0x64
    outb %al, $0x64                                 # 0xd1 means: write data to 8042's P2 port

seta20.2:
    inb $0x64, %al                                  # Wait for not busy(8042 input buffer empty).
    testb $0x2, %al
    jnz seta20.2

    movb $0xdf, %al                                 # 0xdf -> port 0x60
    outb %al, $0x60                                 # 0xdf = 11011111, means set P2's A20 bit(the 1 bit) to 1

    # 从实模式切换到保护模式，使用一个启动GDT标志和段转换，使得虚拟地址对应到物理地址，所以
    # 在切换中不改变有效内存映射
    lgdt gdtdesc
    movl %cr0, %eax
    orl $CR0_PE_ON, %eax
    movl %eax, %cr0

    # Jump to next instruction, but in 32-bit code segment.
    # Switches processor into 32-bit mode.
    ljmp $PROT_MODE_CSEG, $protcseg

.code32                                             # 32位模式的汇编代码
protcseg:
    # 设置保护模式数据段寄存器
    movw $PROT_MODE_DSEG, %ax                       # Our data segment selector
    movw %ax, %ds                                   # -> DS: Data Segment
    movw %ax, %es                                   # -> ES: Extra Segment
    movw %ax, %fs                                   # -> FS
    movw %ax, %gs                                   # -> GS
    movw %ax, %ss                                   # -> SS: Stack Segment

    # 建立栈指针，然后调用C代码， 栈范围为0-start(0x7c00)  0:7c00
    movl $0x0, %ebp
    movl $start, %esp
    call bootmain

    # bootmain()不应该返回，如果返回了，死循环
spin:
    jmp spin

# Bootstrap GDT
.p2align 2                                          # 强制4字节的对齐
gdt:
    SEG_NULLASM                                     # null seg
    SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)           # bootloader and kernel的代码段
    SEG_ASM(STA_W, 0x0, 0xffffffff)                 # bootloader and kernel的数据段

gdtdesc:
    .word 0x17                                      # sizeof(gdt) - 1
    .long gdt                                       # address gdt
