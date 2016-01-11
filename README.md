# openxt-pxe
Script to generate a PXE config file for OpenXT

Example:
- Install a tftp server and the pxelinux files `apt-get install tftpd-hpa pxelinux`
- Point the tftp server to /home/pxe `mkdir /home/pxe ; vi /etc/default/tftpd-hpa`
- Populate /home/pxe `cd /usr/lib/syslinux/modules/bios ; cp chain.c32 ldlinux.c32 libcom32.c32 libutil.c32 mboot.c32 /usr/lib/PXELINUX/pxelinux.0 /home/pxe`
- Run this script `git clone https://github.com/jean-edouard/openxt-pxe.git openxt ; cd openxt ; ./update.sh`
