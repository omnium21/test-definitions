#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019 Linaro Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
YKUSH_PORT="none"
YKUSHCMD=$(which ykushcmd)

SKIP_INSTALL="false"
FORMAT_DEVICE="false"

usage() {
	echo "\
	Usage: $0
		     [--device </dev/sdX>]
		     [--skip_install  <true|false>]
		     [--format_device <true|false>]

	<device>:
		This is the block device to be tested.
	<format_device>
		This will erase the device and create a partition table
		with a single ext4 partition on it.
	<skip_install>:
		Tell the test to skip installation of dependencies, or not

	This test will perform tests on a block device.
	"
}

while [ "$1" != "" ]; do
	case $1 in
		"-h" | "-?" | "-help" | "--help" | "--h" | "help" )
			usage
			exit 0
			;;
		"-f" | "--f" | "-format-device" | "--format-device" )
			shift
			FORMAT_DEVICE=$1
			;;
		"-d" | "--d" | "-dev" | "--dev" )
			shift
			DEVICE=$1
			;;
		"--skip_install" | "--SKIP_INSTALL" | "-skip_install" | "-SKIP_INSTALL" | "--s" | "-s" )
			shift
			SKIP_INSTALL=$1
			;;
		"-ykush_port" | "--y" | "-y" )
			shift
			YKUSH_PORT=$1
			;;
		*)
			usage
			exit 1
			;;
	esac
	shift
done

install() {
	# install dependencies
	dist=
	dist_name
	case "${dist}" in
		debian|ubuntu)
			pkgs="make gcc git"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		fedora|centos)
			pkgs="make gcc git"
			install_deps "${pkgs}" "${SKIP_INSTALL}"
			;;
		# When we don't have a package manager
		# Assume dependencies pre-installed
		*)
			echo "Unsupported distro: ${dist}! Package installation skipped!"
			;;
	esac
}

build_ykush() {
	# if ykush support isn't enabled, we have nothing to do
	if [[ "${YKUSH_PORT}" == "" || "${YKUSH_PORT}" == "none" ]]; then
		return
	fi
	# If ${YKUSHCMD} already exists, there is no need to build it
	if [[ "${YKUSHCMD}" == "" ]]; then
		cmd=${PWD}/ykush/bin/ykushcmd
		if [[ -e ${cmd} ]]; then
			echo "A local ykushcmd exists, use it"
			YKUSHCMD=${cmd}
		else
			if [ ! -e ykush ]; then
				git clone https://github.com/Yepkit/ykush
			fi
			if [ -e ykush ]; then
				pushd ykush > /dev/null 2>&1 || return
				make clean
				make
				YKUSHCMD=${PWD}/bin/ykushcmd
				popd > /dev/null 2>&1 || return
			else
				echo "ERROR: ykush repo doesn't exist"
				exit 1
			fi
		fi

		# after all that, if the command still doesn't exist, it's an error
		if [[ "${YKUSH_PORT}" != "" && "${YKUSH_PORT}" != "none" && "${YKUSHCMD}" == "" ]]; then
			echo "ERROR: ykushcmd doesn't exist"
			exit 1
		fi
	else
		echo "ykushcmd is installed to ${YKUSHCMD}"
	fi
}

ykush_port() {
	local port=$1
	local state=$2
	local updown="d"

	if [[ "${port}" != "" && "${port}" != "none" && "${YKUSHCMD}" != "" && -e "${YKUSHCMD}" ]]; then
		if [ "$state" == "on" ]; then
			updown="u"
		fi
		${YKUSHCMD} -${updown} "${YKUSH_PORT}" > /dev/null 2>&1
	fi
}

device_exists () {
	local device=$1

	if [[ -e ${device} ]]; then
		echo true
	else
		echo false
	fi
}

wait_for_device () {
	local device=$1
        local retries=20

	echo -n "Waiting for ${device}: "
        for ((i=0;i<retries;++i)); do
		local exists
		exists=$(device_exists "${device}")
		if [[ "${exists}" == "true" ]]; then
			echo "done"
			sleep 0.5 # allow the device some time to settle after being plugged in
			return
		fi
		echo -n "."
		sleep 0.5
	done
	echo "failed"
	echo "block-device ${DEVICE} fail" >> "${RESULT_FILE}"
	exit 1
}

block_device_test () {
	local logfile
	local result
	local passcount
	local part_num
	local partdev
	local partname
	local devname
	local mnt

	logfile=$(mktemp "/tmp/block-device.log.XXXXXXXXXXXX")

	echo "Block Device Test" | tee    "${logfile}"
	echo "Device=${DEVICE}"  | tee -a "${logfile}"

	part_num=1
	partdev=${DEVICE}${part_num}
	partname=$(basename -- ${partdev})
	devname=$(basename -- ${DEVICE})

	if [ "${FORMAT_DEVICE}" = "true" ] || [ "${FORMAT_DEVICE}" = "True" ]; then
		echo "Erase device ${DEVICE}" | tee -a "${logfile}"
		dd if=/dev/zero of=${DEVICE} bs=512 count=2048
		echo "Create partition table on ${DEVICE}" | tee -a "${logfile}"
		echo 'type=83' | sfdisk --force ${DEVICE}
		echo "Format ${partdev} as ext4" | tee -a "${logfile}"
		mkfs.ext4 -F ${partdev}
	fi

	# Create a 10M file on the block device
	mnt=/tmp/rmnt/${partname}/
	mkdir -p ${mnt}
	mount -t auto ${partdev} ${mnt}
	dd if=/dev/urandom of=${mnt}/10M bs=1024 count=10240
	umount ${mnt}

	# Test the block device - this expects the 10M file to exist
	echo "Testing block device ${devname}" | tee -a "${logfile}"
	./test-block-device.sh "${partdev}" | tee -a "${logfile}"

	passcount=$(grep -e "completed ok" ${logfile} | wc -l)
	if [[ "${passcount}" == "0" ]]; then
		result=fail
	else
		result=pass
	fi
	echo "block-device-${devname}-${result}" >> "${RESULT_FILE}"

	# Run the bonnie++ test on the block device
	echo "Testing block device ${devname} with bonnie++" | tee -a "${logfile}"
	./test-block-device.sh "${partdev}" -b | tee -a "${logfile}"

	passcount=$(grep -e "completed ok" ${logfile} | wc -l)
	if [[ "${passcount}" == "0" ]]; then
		result=fail
	else
		result=pass
	fi
	echo "block-device-${devname}-bonnie++ ${result}" >> "${RESULT_FILE}"
}

# Install and run test
if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing dependencies"
else
	install
fi
build_ykush
create_out_dir "${OUTPUT}"
ykush_port "${YKUSH_PORT}" on
wait_for_device "${DEVICE}"
block_device_test
# TODO - leave device on for now
# ykush_port "${YKUSH_PORT}" off
