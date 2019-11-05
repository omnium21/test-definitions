#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019 Linaro Ltd.

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
TEST_SUITE="uart-loopback"
YKUSH_PORT="none"
YKUSHCMD=$(which ykushcmd)

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

while [ "$1" != "" ]; do
	case $1 in
		"-h" | "-?" | "-help" | "--help" | "--h" | "help" )
			usage
			exit 0
			;;
		"-0" | "--0" | "-uart0" | "--uart0" )
			shift
			UART0=$1
			;;
		"-1" | "--1" | "-uart1" | "--uart1" )
			shift
			UART1=$1
			;;
		"-skip_install" | "-SKIP_INSTALL" | "--s" | "-s" )
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
build_loopback() {
	if [[ ! -e uart-loopback ]]; then
		# build and/or install uart loopback tests
		make clean
		make
	fi
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
				pushd ykush 2>&1 > /dev/null
				make clean
				make
				YKUSHCMD=${PWD}/bin/ykushcmd
				popd 2>&1 > /dev/null
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
		${YKUSHCMD} -${updown} ${YKUSH_PORT} 2>&1 > /dev/null
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
        for ((i=0;i<${retries};++i)); do
		local exists=$(device_exists ${device})
		if [[ "${exists}" == "true" ]]; then
			echo "done"
			return
		fi
		echo -n "."
		sleep 0.5
	done
	echo "failed"
	exit 1
}

loopback_test() {
	local logfile=$(mktemp "/tmp/$(basename $0).XXXXXXXXXXXX")

	echo Testing data transfer from ${UART0} to ${UART1} | tee ${logfile}
	./test-uart-loopback.sh ${UART0} ${UART1} | tee -a ${logfile}
	sed -i 's/\.//g' ${logfile}
	grep -e "pass" -e "fail" ${logfile} >> ${RESULT_FILE}
}

# Install and run test
if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
	info_msg "Skip installing dependencies"
else
	install
fi
build_loopback
build_ykush
create_out_dir "${OUTPUT}"
ykush_port ${YKUSH_PORT} on
wait_for_device ${UART0}
wait_for_device ${UART1}
loopback_test
ykush_port ${YKUSH_PORT} off
