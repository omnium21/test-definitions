#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2019 Schneider Electric
# Test a block device
#
# test-block-device.sh [FILE] [OPTION]
# FILE is the block device, e.g. /dev/mmcblk0p1
# OPTIONs:
#  -b to run Bonie++

if [ ! -n "$1" ]; then
	echo "Please specify the input block device name (e.g. /dev/mmcblk0p1) to be tested as an argument"
	echo "You can select bonnie as the test method by specifying -b as second command parameter."
	exit
fi

DEV_PATH=$1
TRIM="/dev/"
export DEV=${DEV_PATH#${TRIM}}

USE_BONNIE=$2

ERROR=0

# Test device mounts
mkdir -p /tmp/rmnt/$DEV
mount -t auto $DEV_PATH /tmp/rmnt/$DEV
if [ "$?" != "0" ]; then
	echo "Error when mounting device"
	exit
fi

if [ "$USE_BONNIE" == "-b" ]; then
	# Device mounted so run bonnie to test it.
	echo "Using Bonnie++ to test block device $DEV ..."
	echo "Warning: You may see out of memory errors due to the way bonnie"
	echo "stresses the system."
	bonnie\+\+ -u root -d /tmp/rmnt/$DEV > out-bonnie-$DEV
else
	echo "Time to read 10MB from the card:"
	time -p sh -c 'cp /tmp/rmnt/$DEV/10M .; sync'
	echo "Check md5sum matches the file on the card"
	md5sum 10M
	rm 10M

	# Generate a random file 10MB
	dd if=/dev/urandom of=/tmp/$DEV-random bs=1024 count=10240

	echo "Time to write 10MB to the card:"
	time -p sh -c 'cp /tmp/$DEV-random /tmp/rmnt/$DEV/$DEV-random; sync'

	# Compare files
	cmp /tmp/$DEV-random /tmp/rmnt/$DEV/$DEV-random
	if [ "$?" -ne "0" ]; then ERROR=1; fi
fi


# Finished testing device so make sure we can un-mount it.
umount /tmp/rmnt/$DEV
if [ "$?" != "0" ]; then
	echo "Error when un-mounting device"
fi

if [ $ERROR -ne "0" ]; then
	echo "ERROR: Test failed"
else
	echo "Block Device $DEV tests completed ok"
fi
