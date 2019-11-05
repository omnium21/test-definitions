#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2019 Linaro Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

SKIP_INSTALL="false"

usage() {
	echo "\
	Usage: $0
			     [-0 </dev/ttyX>] [-1 </dev/ttyX] [-s <true|false>]

	<uart0>:
	<uart1>:
		These are the two UARTs used for the loopback tests.
	<skip_install>:
		Tell the test to skip installation of dependencies, or not

	This test will perform loopback transmission between two UARTs,
	using various baud rates, parity and stop bit settings.
	"
}


while getopts "s:0:1:h" opts; do
    case "$opts" in
        s) SKIP_INSTALL="${OPTARG}" ;;
        0) UART0="${OPTARG}" ;;
        1) UART1="${OPTARG}" ;;
        h|*) usage ; exit 1 ;;
    esac
done

param_err=0
if [[ -z "${UART0}" ]]; then
	echo "ERROR: you must use option -0 to specify UART0"
	param_err=1
fi

if [[ -z "${UART1}" ]]; then
	echo "ERROR: you must use option -1 to specify UART1"
	param_err=1
fi

if [[ ! param_err -eq 0 ]]; then
	usage
	exit 1
fi

install () {
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

build_loopback () {
	if [[ ! -e uart-loopback ]]; then
		# build and/or install uart loopback tests
		make clean
		make
	fi
}

device_exists () {
	local device=$1

	if [[ -c ${device} ]]; then
		echo true
	else
		echo false
	fi
}

wait_for_device () {
	local device=$1
        local retries=20

	if [[ -z ${device} ]]; then
		echo "You must specifiy a valid device"
		exit 1
	fi

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
	echo "uart-loopback fail" >> "${RESULT_FILE}"
	exit 1
}

loopback_test () {
	local logfile
	logfile=$(mktemp "/tmp/uart-loopback.log.XXXXXXXXXXXX")

	echo "Testing data transfer from ${UART0} to ${UART1}" | tee "${logfile}"
	./test-uart-loopback.sh "${UART0}" "${UART1}" | tee -a "${logfile}"
	sed -i 's/\.//g' "${logfile}"
	grep -e "pass" -e "fail" "${logfile}" >> "${RESULT_FILE}"
}

# Install and run test
if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing dependencies"
else
	install
fi
build_loopback
create_out_dir "${OUTPUT}"
wait_for_device "${UART0}"
wait_for_device "${UART1}"
loopback_test
