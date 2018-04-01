#!/bin/bash

qemu-system-x86_64 -s -kernel bzImage -initrd initrd.img -append 'root=/dev/raw console=ttyS0 nokaslr' -S -nographic
