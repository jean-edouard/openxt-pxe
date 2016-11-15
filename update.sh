#!/bin/bash

# Remove config and show "updating" message
rm -f pxelinux.cfg pxelinux.cfg.new
cp pxelinux.cfg.updating pxelinux.cfg

# Empty old temp files
rm -f /tmp/pxe_added /tmp/pxe_kept /tmp/pxe_removed
touch /tmp/pxe_added /tmp/pxe_kept /tmp/pxe_removed

n=0

SAVE=

grab() {
    SERVER=$1
    BRANCH=$2
    PREFIX=$3
    MAX=$4

    BASE_URL="http://${SERVER}/builds/${BRANCH}"

    rm -rf /tmp/pxe_openxt_index /tmp/pxe_updating

    # Get the builds page and extract the build names
    wget -q -O /tmp/pxe_openxt_index "${BASE_URL}/?C=N;O=D"
    cat /tmp/pxe_openxt_index | grep "a href=\"${PREFIX}" | sed "s|.*a href=\"\(${PREFIX}-[0-9a-zA-Z-]\+\)/\".*|\1|" > /tmp/pxe_updating

    # Download / keep ($MAX - $n) builds
    for build in `cat /tmp/pxe_updating`; do
	[ $n -eq $MAX ] && break
	if [ -d $build ]; then
	    echo $build >> /tmp/pxe_kept
	else
	    mkdir $build
	    wget -q -O ${build}/netboot.tar.gz "${BASE_URL}/${build}/netboot/netboot.tar.gz" || {
		rm -rf $build
		continue
            }
	    cd $build
	    tar xzf netboot.tar.gz
	    sed -i "s|@NETBOOT_URL@|${BASE_URL}/${build}/repository|" *.ans
	    cd - > /dev/null
	    echo $build >> /tmp/pxe_added
	fi
	n=$(( $n + 1 ))
	cat ${build}/pxelinux.cfg | sed -e '/^serial/d' \
					-e '/^default/d' \
					-e '/^prompt/d' \
					-e '/^timeout/d' \
					-e "s|xc-installer|${n}|" \
					-e "s|-manual$|-m|" \
					-e "s|-upgrade$|-u|" \
					-e "s|@TFTP_PATH@/mboot.c32|mboot.c32|" \
					-e "s|@TFTP_PATH@|openxt/${build}|g" >> pxelinux.cfg.new
	npad=
	[ $n -lt 10 ] && npad=" "
	if [ -z "$SAVE" ]; then
	    SAVE="${npad}${n}: ${build}"
	else
	    pad=
	    for i in `seq ${#SAVE} 32`; do
		pad="${pad} "
	    done
	    echo >> pxelinux.cfg.new
	    echo "say ${SAVE} ${pad} ${npad}${n}: ${build}" >> pxelinux.cfg.new
	    SAVE=
	fi
    done
}

grab_releases() {
    SERVER=$1

    BASE_URL="http://${SERVER}/releases"

    rm -rf /tmp/pxe_openxt_index /tmp/pxe_updating

    # Get the release names
    wget -q -O /tmp/pxe_openxt_index "${BASE_URL}"
    cat /tmp/pxe_openxt_index | grep 'a href="[0-9]' | sed 's|.*a href="\([^"]\+\)/".*|\1|' > /tmp/pxe_updating

    for release in `cat /tmp/pxe_updating`; do
	build=`wget -q -O - "${BASE_URL}/${release}" | grep 'a href="[a-zA-Z]' | sed 's|.*a href="\([0-9a-zA-Z-]\+\)/".*|\1|'`
	if [ -d $release ]; then
	    echo $release >> /tmp/pxe_kept
	else
	    mkdir $release
	    wget -q -O ${release}/netboot.tar.gz "${BASE_URL}/${release}/${build}/netboot/netboot.tar.gz" || {
		rm -rf $release
		continue
            }
	    cd $release
	    tar xzf netboot.tar.gz
	    sed -i "s|@NETBOOT_URL@|${BASE_URL}/${release}/${build}/repository|" *.ans
	    cd - > /dev/null
	    echo $release >> /tmp/pxe_added
	fi
	cat ${release}/pxelinux.cfg | sed -e '/^serial/d' \
		 			  -e '/^default/d' \
					  -e '/^prompt/d' \
					  -e '/^timeout/d' \
					  -e "s|xc-installer|${release}|" \
					  -e "s|-manual$|-m|" \
					  -e "s|-upgrade$|-u|" \
					  -e "s|@TFTP_PATH@/mboot.c32|mboot.c32|" \
					  -e "s|@TFTP_PATH@|openxt/${release}|g" >> pxelinux.cfg.new
    done
}

SERVER="158.69.227.117"

# Current usage of the 20 entries:
#   10 master
#   10 custom master
#    6 stable-6
#    6 custom stable-6
#    2 stable-5
#    2 custom stable-5
#    2 stable-4
#    2 custom-stable-4
grab "$SERVER" "master" "oxt-dev" 10
grab "$SERVER" "master" "custom-dev" 20
grab "$SERVER" "stable-6" "oxt-dev" 26
grab "$SERVER" "stable-6" "custom-dev" 32
grab "$SERVER" "stable-5" "oxt-dev" 34
grab "$SERVER" "stable-5" "custom-dev" 36
grab "$SERVER" "stable-4" "oxt-dev" 38
grab "$SERVER" "stable-4" "custom-dev" 40

[ -n "$SAVE" ] && echo >> pxelinux.cfg.new
[ -n "$SAVE" ] && echo "say ${SAVE}" >> pxelinux.cfg.new

grab_releases "$SERVER"

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
