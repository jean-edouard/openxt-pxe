#!/bin/bash

# Configuration
SERVER="openxt.ainfosec.com"
PROTOCOL="https"
MIRROR_REPOSITORIES=0
MIRROR_LOCATION="/home/builds"
MIRROR_URL="http://openxt.local/builds"
WGET="wget"

# Remove config and show "updating" message
rm -f pxelinux.cfg pxelinux.cfg.new
cp pxelinux.cfg.updating pxelinux.cfg

# Empty old temp files
rm -f /tmp/pxe_added /tmp/pxe_kept /tmp/pxe_removed
touch /tmp/pxe_added /tmp/pxe_kept /tmp/pxe_removed

# Build ID
n=0
# PXE menu columns 1 and 2 buffers
SAVE1=
SAVE2=

add_build_to_pxe() {
    BUILD="$1"
    NAME="$2"

    cat ${BUILD}/pxelinux.cfg | sed -e '/^serial/d' \
				    -e '/^default/d' \
				    -e '/^prompt/d' \
				    -e '/^timeout/d' \
				    -e "s|xc-installer|${NAME}|" \
				    -e "s|-manual$|-m|" \
				    -e "s|-upgrade$|-u|" \
				    -e "s|@TFTP_PATH@/mboot.c32|mboot.c32|" \
				    -e "s|@TFTP_PATH@|openxt/${BUILD}|g" >> pxelinux.cfg.new
}

grab_generic() {
    BASE_URL="$1"
    BRANCH="$2"
    PXE_PREFIX="$3"
    MAX=$4
    ADD_TO_MENU=$5

    # Download / keep ($MAX - $n) builds
    for build in `cat /tmp/pxe_updating`; do
	[ $n -eq $MAX ] && break
	if [ -d $build ]; then
	    echo $build >> /tmp/pxe_kept
	else
	    # Get Netboot
	    mkdir $build
	    if [ "${BRANCH}" = "stable-6" ]; then
		netboot="${BASE_URL}/${build}/openxt-dev-${build}-stable-6/netboot/netboot.tar.gz"
	    else
		netboot="${BASE_URL}/${build}/netboot/netboot.tar.gz"
	    fi
	    $WGET -q -O ${build}/netboot.tar.gz "${netboot}" || {
		rm -rf $build
		continue
            }
	    # Get repository
	    if [[ $MIRROR_REPOSITORIES -eq 1 ]] && [[ ! -d /home/builds/${build} ]]; then
		mkdir /home/builds/${build}
		if [ "${BRANCH}" = "stable-6" ]; then
		    repository="${BASE_URL}/${build}/openxt-dev-${build}-stable-6/update/update.tar"
		else
		    repository="${BASE_URL}/${build}/update/update.tar"
		fi
		$WGET -q -O ${MIRROR_LOCATION}/${build}/repository.tar "${repository}"
		# Extract repository
		cd ${MIRROR_LOCATION}/${build}
		tar xf repository.tar
		rm repository.tar
		cd - > /dev/null
	    fi
	    # Extract netboot
	    cd $build
	    tar xzf netboot.tar.gz
	    rm netboot.tar.gz
	    if [[ $MIRROR_REPOSITORIES -eq 1 ]]; then
		sed -i "s|@NETBOOT_URL@|${MIRROR_URL}/${build}|" *.ans
	    else
		sed -i "s|@NETBOOT_URL@|${BASE_URL}/${build}/repository|" *.ans
	    fi
	    cd - > /dev/null
	    echo $build >> /tmp/pxe_added
	fi
	n=$(( $n + 1 ))
	# Add ID entry to PXE
	add_build_to_pxe "${build}" "${n}"
	# Add name (build number) entry to PXE
	add_build_to_pxe "${build}" "${build}"
	# Last thing to do is add the new entries to the menu. Skip if requested.
	[[ $ADD_TO_MENU -eq 1 ]] || continue
	npad=
	[ $n -lt 10 ] && npad=" "
	name="${PXE_PREFIX}${build}"
	if [ -z "$SAVE1" ]; then
	    SAVE1="${npad}${n}:${name}"
	elif [ -z "$SAVE2" ]; then
	    SAVE2="${npad}${n}:${name}"
	else
	    pad1=
	    for i in `seq ${#SAVE1} 24`; do
		pad1="${pad1} "
	    done
	    pad2=
	    for i in `seq ${#SAVE2} 24`; do
		pad2="${pad2} "
	    done
	    echo >> pxelinux.cfg.new
	    echo "say ${SAVE1} ${pad1} ${SAVE2} ${pad2} ${npad}${n}:${name}" >> pxelinux.cfg.new
	    SAVE1=
	    SAVE2=
	fi
    done
}

grab_old() {
    BRANCH=$1
    PREFIX=$2
    MAX=$3

    base_url="${PROTOCOL}://${SERVER}/builds/legacy/${BRANCH}"

    rm -rf /tmp/pxe_openxt_index /tmp/pxe_updating

    # Get the builds page and extract the build names
    $WGET -q -O /tmp/pxe_openxt_index "${base_url}/?C=N;O=D"
    cat /tmp/pxe_openxt_index | grep "a href=\"${PREFIX}" | sed "s|.*a href=\"\(${PREFIX}-[0-9a-zA-Z-]\+\)/\".*|\1|" > /tmp/pxe_updating

    grab_generic "${base_url}" "${BRANCH}" "" ${MAX} 1
}

grab_new() {
    BRANCH=$1
    TYPE=$2
    MAX=$3

    base_url="${PROTOCOL}://${SERVER}/builds/${TYPE}/${BRANCH}"

    rm -rf /tmp/pxe_openxt_index /tmp/pxe_updating

    # Get the builds page and extract the build names
    $WGET -q -O /tmp/pxe_openxt_index "${base_url}/?C=N;O=D"
    cat /tmp/pxe_openxt_index | grep "a href=\"[0-9]" | sed "s|.*a href=\"\([0-9]\+\)/\".*|\1|" > /tmp/pxe_updating

    grab_generic "${base_url}" "${BRANCH}" "${BRANCH} ${TYPE} #" ${MAX} 1
}

grab_releases() {
    base_url="${PROTOCOL}://${SERVER}/releases"

    rm -rf /tmp/pxe_openxt_index /tmp/pxe_updating

    # Get the release names
    $WGET -q -O /tmp/pxe_openxt_index "${base_url}"
    cat /tmp/pxe_openxt_index | grep 'a href="[0-9]' | sed 's|.*a href="\([^"]\+\)/".*|\1|' > /tmp/pxe_updating

    # Ideally at this point we would use grab_generic, but this is just too different...
    for release in `cat /tmp/pxe_updating`; do
	if [ -d $release ]; then
	    echo $release >> /tmp/pxe_kept
	else
	    mkdir $release
	    if [[ $release = 4* ]] || [[ $release = 5* ]] || [[ $release = 6* ]]; then
		build=`$WGET -q -O - "${base_url}/${release}" | grep 'a href="[a-zA-Z]' | sed 's|.*a href="\([0-9a-zA-Z-]\+\)/".*|\1|'`
	    else
		build=`$WGET -q -O - "${base_url}/${release}" | grep 'a href="[1-9]' | sed 's|.*a href="\([0-9]\+\)/".*|\1|'`
	    fi
	    # Get netboot
	    $WGET -q -O ${release}/netboot.tar.gz "${base_url}/${release}/${build}/netboot/netboot.tar.gz" || {
		rm -rf $release
		continue
            }
	    # Extract netboot
	    cd $release
	    tar xzf netboot.tar.gz
	    sed -i "s|@NETBOOT_URL@|${base_url}/${release}/${build}/repository|" *.ans
	    cd - > /dev/null
	    # TODO: get and extract repository too?
	    echo $release >> /tmp/pxe_added
	fi
	add_build_to_pxe "${release}" "${release}"
    done
}

grab() {
    BRANCH=$1
    TYPE=$2
    MAX=$3

    if [[ "${BRANCH}" = "stable-4" ]] || [[ "${BRANCH}" = "stable-5" ]]; then
	grab_old "${BRANCH}" "${TYPE}" ${MAX}
    else
	grab_new "${BRANCH}" "${TYPE}" ${MAX}
    fi
}

# Download regular builds
# Current usage of the 60 entries:
#   12 master
#   12 custom master
#    9 stable-7
#    9 custom stable-7
#    3 stable-6
#    3 custom stable-6
#    3 stable-5
#    3 custom stable-5
#    3 stable-4
#    3 custom-stable-4
grab "master" "regular" 12
grab "master" "custom" 24
grab "stable-7" "regular" 33
grab "stable-7" "custom" 42
grab "stable-6" "regular" 45
grab "stable-6" "custom" 48
grab "stable-5" "oxt-dev" 51
grab "stable-5" "custom-dev" 54
grab "stable-4" "oxt-dev" 57
grab "stable-4" "custom-dev" 60

# Flush PXE menu columns 1 and 2
if [ -n "$SAVE2" ]; then
    echo >> pxelinux.cfg.new
    pad1=
    for i in `seq ${#SAVE1} 24`; do
	pad1="${pad1} "
    done
    echo "say ${SAVE1} ${pad1} ${SAVE2}" >> pxelinux.cfg.new
elif [ -n "$SAVE1" ]; then
    echo >> pxelinux.cfg.new
    echo "say ${SAVE1}" >> pxelinux.cfg.new
fi

# Download release builds
grab_releases "$NEW_SERVER"

# Remove old builds
# TODO: improve the listing so it doesn't fail when nothing gets matched
for dir in `ls -d *-dev-* [1-9][0-9][0-9][0-9]`; do
    grep $dir /tmp/pxe_added >/dev/null || grep $dir /tmp/pxe_kept > /dev/null || {
        rm -rf $dir
	rm -rf /home/builds/`basename $dir`
        echo $dir >> /tmp/pxe_removed
    }
done

# Store the pxe config
rm -f pxelinux.cfg
mv pxelinux.cfg.new pxelinux.cfg

# Cleanup
rm /tmp/pxe_openxt_index /tmp/pxe_updating
