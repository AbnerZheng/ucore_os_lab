#include <defs.h>
#include <x86.h>
#include <elf.h>

/* *********************************************************************
 * This a dirt simple boot loader, whose sole job is to boot
 * an ELF kernel image from the first IDE hard disk.
 *
 * DISK LAYOUT
 *  * This program(bootasm.S and bootmain.c) is the bootloader.  bootloader由bootasm.S和bootmain.c两个文件组成
 *    It should be stored in the first sector of the disk.  bootloader应该放在disk中第一个扇区
 *
 *  * The 2nd sector onward holds the kernel image.  第二个扇区放置内核镜像
 *
 *  * The kernel image must be in ELF format.  内核镜像必须为ELF格式
 *
 *  启动步骤
 *  * 当cpu启动的时候， 载入BIOS到内存，之后执行它
 *
 *  * BIOS初始化设备，设置中断例行程序，并且读入启动设备（比如硬盘）的第一个扇区到内存，并且跳转到该程序
 *
 *  * 假设该boot loader放置在硬盘的第一个扇区，该代码接管一切
 *
 *  * 控制起始于bootasm.S, 将CPU设为保护模式， 建立一个栈使得C代码接下去运行，接着调用bootmain()
 *
 *  * 该文件中的bootmain接管，读入内核，并且跳转到内核。
 * */

#define SECTSIZE        512   // 每个扇区为512个字节
#define ELFHDR          ((struct elfhdr *)0x10000)      // scratch space

/*
 * waitdisk - 等待硬盘准备好
 * inb从外部设备读入数据，其中inb(0x1F7)为读取磁盘状态
 * 死循环到硬盘准备好
 * */

static void
waitdisk(void) {
    while ((inb(0x1F7) & 0xC0) != 0x40)
        /* do nothing */;
}

/* *
 * readsect - 读入一个单独扇区@secno到@dst
 *
 * @secno: 扇区号
 * @dst: 目标地址，为void指针
 * */

static void
readsect(void *dst, uint32_t secno) {
    // 等待硬盘准备好
    // 死循环
    waitdisk();

    // 下面这里为写硬盘
    // 需要看硬盘指令手册
    outb(0x1F2, 1);                         // count = 1
    outb(0x1F3, secno & 0xFF);              // 写入低八位, 显然这里的数据位为八位
    outb(0x1F4, (secno >> 8) & 0xFF);       // 写入9-16位
    outb(0x1F5, (secno >> 16) & 0xFF);      // 写入17-24位
    outb(0x1F6, ((secno >> 24) & 0xF) | 0xE0);  // 写入25-32位，其中，25-28为扇区号码， 29位为0，30-32为1.
    outb(0x1F7, 0x20);                      // cmd 0x20 - 读取扇区

    // wait for disk to be ready
    // 阻塞等待
    waitdisk();

    // read a sector
    insl(0x1F0, dst, SECTSIZE / 4);
}

/* *
 * readseg - read @count bytes at @offset from kernel into virtual address @va,
 * might copy more than asked.
 * */
static void
readseg(uintptr_t va, uint32_t count, uint32_t offset) {
    uintptr_t end_va = va + count;

    // round down to sector boundary
    va -= offset % SECTSIZE;

    // translate from bytes to sectors; kernel starts at sector 1
    uint32_t secno = (offset / SECTSIZE) + 1;

    // If this is too slow, we could read lots of sectors at a time.
    // We'd write more to memory than asked, but it doesn't matter --
    // we load in increasing order.
    for (; va < end_va; va += SECTSIZE, secno ++) {
        readsect((void *)va, secno);
    }
}

/* bootmain - the entry of bootloader */
void
bootmain(void) {
    // read the 1st page off disk
    readseg((uintptr_t)ELFHDR, SECTSIZE * 8, 0);

    // is this a valid ELF?
    if (ELFHDR->e_magic != ELF_MAGIC) {
        goto bad;
    }

    struct proghdr *ph, *eph;

    // load each program segment (ignores ph flags)
    ph = (struct proghdr *)((uintptr_t)ELFHDR + ELFHDR->e_phoff);
    eph = ph + ELFHDR->e_phnum;
    for (; ph < eph; ph ++) {
        readseg(ph->p_va & 0xFFFFFF, ph->p_memsz, ph->p_offset);
    }

    // call the entry point from the ELF header
    // note: does not return
    ((void (*)(void))(ELFHDR->e_entry & 0xFFFFFF))();

bad:
    outw(0x8A00, 0x8A00);
    outw(0x8A00, 0x8E00);

    /* do nothing */
    while (1);
}

