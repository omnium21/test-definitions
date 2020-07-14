#!/bin/sh

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
EEPROM="/sys/bus/spi/devices/spi0.1/eeprom"
BLOCK_COUNT=128
BLOCK_SIZE=1024

. ../../lib/sh-test-lib

create_out_dir "${OUTPUT}"

usage() {
    echo "Usage: $0 [-e <eeprom_device>] [-s <skip install: true|false]" 1>&2
    exit 1
}

while getopts "b:c:e:h:s" o; do
  case "$o" in
    b) BLOCK_SIZE="${OPTARG}" ;;
    c) BLOCK_COUNT="${OPTARG}" ;;
    e) EEPROM="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done



################################################################################
# Data Test
################################################################################
data_test () {
	local count=$1
	local bs=$2
	local pattern=$3
	local tmpfile=$(mktemp "/tmp/eeprom.XXXXXXXXXXXX")

	case ${pattern} in
	"0" | "00" | "zero" | "zeros")
		str="all zeros"
		# Generate random data
		dd if=/dev/zero count=1  bs=${bs} of=${tmpfile} 2> /dev/null
		;;
	"ff" | "FF")
		str="all ones"
		dd if=/dev/zero count=1 bs=${bs} 2> /dev/null | tr '\000' '\377' > ${tmpfile} # 377 octal = 0xFF
		;;
	"55")
		str="all 5s"
		dd if=/dev/zero count=1 bs=${bs} 2> /dev/null | tr '\000' '\125' > ${tmpfile} # 125 octal = 0x55
		;;
	"aa" | "AA")
		str="all As"
		dd if=/dev/zero count=1 bs=${bs} 2> /dev/null | tr '\000' '\252' > ${tmpfile} # 252 octal = 0xAA
		;;
	*)
		str="random data"
		# Generate random data
		dd if=/dev/urandom of=${tmpfile}       count=1  bs=${bs} 2> /dev/null
		;;
	esac

	if [ "${VERBOSE}" = "1" ]; then
		echo "Testing write/read of ${bs} bytes of ${str} to SPI EEPROM..."
		cat ${tmpfile} | head -c ${bs} | hexdump -v -C ${tmpfile}
		echo VERBOSE=${VERBOSE}
	fi

	# Write an exact amount of data
	dd if=${tmpfile}      of=${EEPROM}       count=1  bs=${bs} 2> /dev/null

	# Read an exact amount of data
	dd if=${EEPROM}      of=${tmpfile}.read  count=1  bs=${bs} 2> /dev/null

	cmp ${tmpfile} ${tmpfile}.read && result="pass" || result="fail"

	if [ "${result}" = "fail" ]; then
		echo "write-data failed when writing ${count} blocks of ${bs} bytes of ${str} to ${EEPROM}"
	fi
	rm ${tmpfile}*
}

################################################################################
# Check device exists
################################################################################
echo "Check EEPROM device ${EEPROM} exists before running tests..."
if [ -e ${EEPROM} ]; then
	result="pass"
else
	result="fail"
fi
echo "eeprom-device-exists ${result}" | tee -a ${RESULT_FILE}


################################################################################
# Test access using standard data access method
################################################################################
if [ "${result}" = "pass" ]; then
	echo "Test EEPROM read/write using standard file access..."

	# Target corner cases
	for size in `seq 1 33` `seq 4089 4096`; do
		echo -n "With block size: ${size} pattern: "
		for pattern in 00 55 AA FF random; do
			echo -n "${pattern} "
			if [ "${result}" = "pass" ]; then
				data_test 1 ${size} ${pattern}
			fi
		done
		echo ""
	done
	echo ""
	echo "eeprom-data-access ${result}" | tee -a ${RESULT_FILE}
fi


################################################################################
# Try filling the device
################################################################################
if [ "${result}" = "pass" ]; then
	echo "Test we can write to the entire device of ${BLOCK_COUNT} blocks of ${BLOCK_SIZE} bytes"
	echo -n "With pattern: "

	for pattern in 00 55 AA FF random; do
		if [ "${result}" = "pass" ]; then
			echo -n "${pattern} "
			data_test ${BLOCK_COUNT} ${BLOCK_SIZE} ${pattern}
		fi
	done
	echo ""
	echo "eeprom-fill ${result}" | tee -a ${RESULT_FILE}
fi


################################################################################
# Test access using standard file operations like "echo" and "cat"
################################################################################
if [ "${result}" = "pass" ]; then
	echo "Test string access works..."

	out=" SPI EEPROM test"
	len=$(expr ${#out} + 16) # pad out the amount of data by an arbitrary amount

	# First blank the start of the device
	data_test 1 ${len} 00

	echo "${out}" > ${EEPROM}
	in=$(cat ${EEPROM} | head -c ${len} | tr -d '\000')
	
	[ "${in}" = "${out}" ] && result=pass || result=fail
	echo "eeprom-string-access ${result}" | tee -a ${RESULT_FILE}
fi
