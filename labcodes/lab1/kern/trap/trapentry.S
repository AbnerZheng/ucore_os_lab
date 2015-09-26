#include <memlayout.h>

# vectors.S sends all traps here.
# vectors.S 将所有的traps都送到此处处理
.text
.globl __alltraps
__alltraps:
    # 把这些寄存器都压栈来构建一个trap frame
    # therefore make the stack look like a struct trapframe
    pushl %ds
    pushl %es
    pushl %fs
    pushl %gs
    pushal

    # load GD_KDATA into %ds and %es to set up data segments for kernel
    # GD_KDATA 为16
    movl $GD_KDATA, %eax
    movw %ax, %ds
    movw %ax, %es

    # push %esp to pass a pointer to the trapframe as an argument to trap()
    // 将当前的栈指针地址作为参数传入给trap
    pushl %esp

    # call trap(tf), where tf=%esp
    call trap

    # pop the pushed stack pointer
    popl %esp

    # return falls through to trapret...
.globl __trapret
__trapret:
    # restore registers from stack
    # 从栈中恢复寄存器
    popal

    # restore %ds, %es, %fs and %gs
    popl %gs
    popl %fs
    popl %es
    popl %ds

    # get rid of the trap number and error code
    addl $0x8, %esp
    # 使用iret指令返回之前调用__alltraps的函数
    iret

