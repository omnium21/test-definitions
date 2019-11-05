#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019 Schneider Electric
#
# Test UARTs using loopback between two ports with different speeds, etc
# tx and rx devices can be passed in

TXUART=${1:-/dev/ttyS1}
RXUART=${2:-/dev/ttyUSB0}


DIR="$( dirname "$0" )"

ERRORS=0

device_exists () {
	local device=$1
	if [[ ! -e ${device} ]]; then
		echo "ERROR: Device ${device} does not exist"
		((ERRORS++))
	fi
}
device_exists ${TXUART}
device_exists ${RXUART}

if [[ ${ERRORS} -gt 0 ]]; then
	exit 1
fi

test_one () {
	LENGTH=$1
	${DIR}/uart-loopback -o ${TXUART} -i ${RXUART} -s ${LENGTH} -r
	if [ "$?" -ne "0" ]; then ERRORS=$((ERRORS+1)); fi
}

# Test transfers of lengths that typically throw problems
test_one_cfg () {
	SETTINGS=$1
	stty -F ${TXUART} ${SETTINGS}
	stty -F ${RXUART} ${SETTINGS}

	local errors=${ERRORS}

	for length in `seq 1 33`; do
		test_one ${length}
	done

	test_one 4095
	test_one 4096
	test_one 4097

	if [[ "$errors" == "$ERRORS" ]]; then
		echo " pass"
	else
		echo " fail"
	fi
}

# Note that we specify the _changes_ to the tty settings, so don't comment one out!
baudrates=(9600 38400 115200 230400)
for baud in ${baudrates[@]} ;
do
	echo -n "${baud}:8n1:raw"
	test_one_cfg "${baud} -parenb -cstopb -crtscts cs8 -ignbrk -brkint  -parmrk -istrip -inlcr -igncr -icrnl -ixon -opost -echo -echonl -icanon -isig -iexten"

	echo -n "${baud}:8o1"
	test_one_cfg " parenb parodd"

	echo -n "${baud}:8e1"
	test_one_cfg "-parodd"

	echo -n "${baud}:8n2"
	test_one_cfg "-parenb cstopb"

	echo -n "${baud}:8n1:CTS/RTS"
	test_one_cfg "-cstopb crtscts"

	# This is the same as the first test, putting the UART back into 115200
	echo -n "${baud}:8n1:raw"
	test_one_cfg "-crtscts"

done

echo
echo "Tests complete with $ERRORS Errors."

