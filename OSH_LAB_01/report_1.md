#实验要求

1. `git clone`已创建的仓库，在其中创建名为`hello_linux.sh`的文件，使其功能如下文所述，并使用`git commit`、`git push`等命令将修改后的仓库上传到GitHub。要求`hello_linux.sh`应为**可执行文件**，当以`./hello_linux.sh`这条命令执行它时，它应当向标准输出打印一行文本`Hello Linux`，并将标准输入的文本保存至当前目录下名为`output.txt`的文件
2. 调试操作系统的启动过程

# 实验目的

1. 了解学习Linux操作系统
2. 学习 git 、GitHub 使用流程
3. 通过使用调试工具追踪 Linux 操作系统的启动过程，并找出至少两个关键事件

# 实验过程(调试跟踪操作系统启动过程)

实验环境：debian 9

1. 安装 `htop`、`qemu`、`dpkg-dev`

2. 使用`apt source linux-image-4.9.0-6-amd64`下载内核源代码 (linux-4.9.82)

3. 使用`make menuconfig`配置内核，启用Compile the kernel with debug info选项，设置优化相关选项

4. 使用 `make`命令编译内核代码

5. 拷贝本机初始化内存盘 (initrd.img)

6. 启动 `qemu` 虚拟机，指定 `gdb` 端口（将命令写入了 `start.sh` 脚本以方便后续操作；传递`nokaslr`参数关闭地址空间随机化，从而成功设置了断点

7. 使用`kdbg -r localhost:1234 vmlinux`命令启动调试器（此处参考资料对 gdb 源码做出一些修改，详见[此网页](https://wiki.osdev.org/QEMU_and_GDB_in_long_mode)）

8. 在`start_kernel()`、`boot_cpu_init()`、`rest_init()` 、`kernel_init()` 处设置断点，进行跟踪调试

   ![](/home/smile/图片/设置断点及调试.png)

9. 参阅内核代码解析资料进一步了解和分析

# 实验内容与结果

##Linux启动过程跟踪

![](/home/smile/图片/Linux 开机启动.png)

​                                                                         图一： linux启动过程示意

1. PC启动时，首先Linux 执行 `BIOS` 中的代码， BIOS 运行时会按照CMOS的设置定义的顺序来搜索处于活动状态并且可以引导的设备。


2. 当一个启动设备被发现，第一阶段引导程序被加载到 RAM 并执行，此引导程序的作用是加载第二阶段的引导程序
3. 第二阶段引导程序被加载进 RAM 并执行，启动界面被显示，且 Linux 和可选初始磁盘（临时文件系统）被加载进内存。当镜像被加载以后，控制权从第二阶段引导程序传递到内核镜像，内核镜像先自解压和初始化。在这一步，第二阶段引导程序将检查系统硬件，枚举硬件设备，挂载主设备，加载必须的内核模块。
4. 内核启动

   start_kernel 完成了内核的初始化，启动 init 进程
   1. `debug_objects_early_init` 用于内核的对象调试
   2. `boot_init_stack_canary()` 初始化 canary, 防止缓冲区溢出
   3. `cgroup_init_early()` 初始化 cgroup 机制
   4. `boot_cpu_init()` 初始化 CPU 的启动（见后文详细说明）
   5. `page_address_init()` 初始化高端内存
   6. `setup_arch(&command_line)` 初始化 CPU ，平台数据结构等具体信息
   7. `mm_init_cpumask(&init_mm)` 初始化内存
   8. `build_all_zerolists()` 初始化内存管理节点列表，便于内存管理的初始化
   9. `page_alloc_init()` 初始化内存分配
   10. `parse_early_param()` 获取命令行 early 最早执行的参数
   11. `vfs_caches_init_early()` 初始化 vfs  cache 子系统
   12. `trap_init` 初始化终端向量
   13. `mm_init` 初始化内存管理
   14. `sched_init` 初始化调度管理
   15. `preempt_disabled()` 关闭优先权
   16. `rcu_init` 初始化直接读、拷贝更新的锁机制
   17. `trace_init` 初始化跟踪信息
   18. `context_tracking_init()` 初始化
   19. `init_IRQ` 初始化中断
   20. `time_init()` 初始化高精度time
   21. `softirq_init()` 初始化软中断
   22. `local_irq_enablr()` 开中断
   23. `console_init()` 初始化控制台（初始化控制台后 prink 就可以输出了，在之前是输出到缓冲里
   24. `vfs_cache_init()` 初始化页表
   25. `thread_stack_cache_init()` 初始化 thread cache 
   26. `check_bugs()` 检错
   27. `rest_init()`  创建并启动内核线程（见后文详细说明）

##boot_cpu_init 详述

该函数主要为了通过掩码初始化每一个CPU。

- 通过 int cpu = smp_processor_id() 获取当前处理器的 ID ，每cpu变量`cpu_number` 的值是`this_cpu_read`通过`raw_smp_processor_id`得到


- 返回的ID表示我们处于哪一个CPU上, `boot_cpu_init` 函数设置了CPU的在线, 激活，设置- CPU掩码

##rest_init 详述

####创建三个线程：

1. kernel_thread (kernel_init, NULL, CLONE_FS | CLONE_SIGHAND);创建1号进程 `kernel_init`
2. 创建 `kthreadd` 线程，它是内核线程之父，管理调度其它的内核线程，内核线程列表由kthread_create_list全局链表管理
3. 创建 `idle` 线程消耗空CPU时间

####详细描述：

1. `kernel_init kernel_init` 最开始作为进程被启动，之后它将读取根文件系统下的init程序，完成从内核态到用户态的转变，而这个init进程是所有用户态进程的父进程，生了大量的子进程，所以init进程将永远存在，其 PID 是1
2. `kthreadd` 是内核守护进程，用于管理和调度其他内核线程，其 PID 为2。kthreadd 循环运行一个叫做 kthreadd 的函数，该函数的作用是运行 kthread_create_list 全局链表中维护的内核线程。调用kthread_create 创建 create_list 链表中；被执行过的 kthread 会从 kthread_create_list 链表中删除；且 kthreadd 会不断调用 cheduler 函数让出CPU。此线程不可关闭。
3. 在没有其他进程执行时，执行 `idle`， 系统的空闲时间，其实就是指idle进程 的"运行时间"。

#参考资料

1. [QEMU and GDB in long mode - OSDev Wiki](https://wiki.osdev.org/QEMU_and_GDB_in_long_mode)
2. [从源码中跟踪Linux Kernel的启动过程 « IT Dreamer](http://burningcodes.net/%E4%BB%8E%E6%BA%90%E7%A0%81%E4%B8%AD%E8%B7%9F%E8%B8%AAlinux-kernel%E7%9A%84%E5%90%AF%E5%8A%A8%E8%BF%87%E7%A8%8B/)
3. [参考  跟踪分析Linux内核的启动过程 - 简书](https://www.jianshu.com/p/c50563d5d999)
4. [linux 3.6 启动源码分析(四) rest_init - CSDN博客](https://blog.csdn.net/qing_ping/article/details/17351933)
5. [初始化 · Linux ­Insides­中文](https://xinqiu.gitbooks.io/linux-insides-cn/content/Initialization/)