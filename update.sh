#!/bin/bash

# Remove config and show "updating" message
rm -f pxelinux.cfg pxelinux.cfg.new
cp pxelinux.cfg.updating pxelinux.cfg

# Empty old temp files
rm -f /tmp/pxe_added /tmp/pxe_kept /tmp/pxe_removed
touch /tmp/pxe_added /tmp/pxe_kept /tmp/pxe_removed

n=0

grab() {
    SERVER=$1
    BRANCH=$2
    PREFIX=$3
    MAX=$4

    rm -rf /tmp/pxe_openxt_index /tmp/pxe_updating

    # Get the builds page and extract the build names
    wget -q -O /tmp/pxe_openxt_index "http://${SERVER}/builds/${BRANCH}/?C=N;O=D"
    cat /tmp/pxe_openxt_index | grep "a href=\"${PREFIX}" | sed "s|.*a href=\"\(${PREFIX}-[0-9a-zA-Z-]\+\)/\".*|\1|" > /tmp/pxe_updating

    # Download / keep ($MAX - $n) builds
    for build in `cat /tmp/pxe_updating`; do
	[ $n -eq $MAX ] && break
	if [ -d $build ]; then
	    echo $build >> /tmp/pxe_kept
	else
	    mkdir $build
	    wget -q -O ${build}/netboot.tar.gz "http://${SERVER}/builds/${BRANCH}/${build}/netboot/netboot.tar.gz" || {
		rm -rf $build
		continue
            }
	    cd $build
	    tar xzf netboot.tar.gz
	    sed -i "s|@NETBOOT_URL@|http://${SERVER}/builds/${BRANCH}/${build}/repository|" *.ans
	    cd - > /dev/null
	    echo $build >> /tmp/pxe_added
	fi
	n=$(( $n + 1 ))
	cat ${build}/pxelinux.cfg | sed -e '/^serial/d' \
					-e '/^default/d' \
					-e '/^prompt/d' \
					-e '/^timeout/d' \
					-e "s|xc-installer|${n}|" \
					-e "s|@TFTP_PATH@/mboot.c32|mboot.c32|" \
					-e "s|@TFTP_PATH@|openxt/${build}|g" >> pxelinux.cfg.new
	echo "say ${n}: ${build}" >> pxelinux.cfg.new
    done
}

SERVER="158.69.227.117"

# Current usage of the 20 entries:
#   6 master
#   6 custom master
#   4 stable-5
#   4 custom stable-5
grab "$SERVER" "master" "oxt-dev" 6
grab "$SERVER" "master" "custom-dev" 12
grab "$SERVER" "stable-5" "oxt-dev" 16
grab "$SERVER" "stable-5" "custom-dev" 20

# Remove old builds
for dir in `ls -d *-dev-*`; do
    grep $dir /tmp/pxe_added >/dev/null || grep $dir /tmp/pxe_kept > /dev/null || {
        rm -rf $dir
        echo $dir >> /tmp/pxe_removed
    }
done

# Store the pxe config
rm -f pxelinux.cfg
mv pxelinux.cfg.new pxelinux.cfg

# Cleanup
rm /tmp/pxe_openxt_index /tmp/pxe_updating
