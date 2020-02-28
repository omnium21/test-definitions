#!/bin/sh
# shellcheck disable=SC1091

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
CUNIT_FILE="CUnitAutomated-Results.xml"
CRYPTO_DEVICE="/dev/cryptotest"

. ../../lib/sh-test-lib

create_out_dir "${OUTPUT}"

usage() {
    echo "Usage: $0 [-c <crypto_device>] [-s <skip install: true|false]" 1>&2
    exit 1
}

while getopts "c:h:s" o; do
  case "$o" in
    c) CRYPTO_DEVICE="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

# Copied from automated/linux/spectre-meltdown-checker-test/bin/spectre-meltdown-checker.sh
# example usage:
#	dmesg_grep 'Xen HVM callback vector for event delivery is enabled$'; ret=$?
#
dmesg_grep()
{
	# grep for something in dmesg, ensuring that the dmesg buffer
	# has not been truncated
	dmesg_grepped=''
	if ! dmesg | grep -qE -e '(^|\] )Linux version [0-9]' ; then
		# dmesg truncated
		return 2
	fi
	dmesg_grepped=$(dmesg | grep -E "$1" | head -1)
	# not found:
	[ -z "$dmesg_grepped" ] && return 1
	# found, output is in $dmesg_grepped
	return 0
}

# Check device does NOT exist
# It won't exist until the module is probed
if [ -c "${CRYPTO_DEVICE}" ]; then
	result="fail"
else
	result="pass"
fi
echo "device-not-exists-yet ${result}" | tee -a ${RESULT_FILE}

if [ "${result}" = pass ]; then

	modprobe cryptotest

	# Expected output in dmesg:
	dmesg_grep 'Cryptotest init'
	ret=$?

	if [ "${ret}" -eq 0 ]; then
		result="pass"
	else
		result="fail"
	fi
	echo "modprobe-cryptotest ${result}" | tee -a ${RESULT_FILE}
fi

if [ "${result}" = pass ]; then

	# Check device exists
	if [ -c ${CRYPTO_DEVICE} ]; then
		result="pass"
	else
		result="fail"
	fi
	echo "device-exists ${result}" | tee -a ${RESULT_FILE}
fi

if [ "${result}" = pass ]; then
	modprobe crypto-safexcel-eip28
	# Expected output in dmesg:
	dmesg_grep 'crypto-safexcel-eip28 40044000.crypto_eip28: IRQ initialization is done'
	irq_done=$?
	dmesg_grep 'crypto-safexcel-eip28 40044000.crypto_eip28: HW initialization is done'
	hw_init_done=$?
	if [[ "${irq_done}" -eq 0 && "${hw_init_done}" -eq 0 ]]; then
		result="pass"
	else
		result="fail"
	fi
	echo "modprobe-cryptotest ${result}" | tee -a ${RESULT_FILE}
fi

if [ "${result}" = pass ]; then
	ctests=/usr/bin/crypto_test/ctests
	if [ -e "${ctests}" ]; then
		result="pass"
	else
		result="fail"
	fi
	echo ctests-exist ${result} | tee -a ${RESULT_FILE}
fi

if [ "${result}" = pass ]; then
	logfile="${OUTPUT}/cunit-output"
	/usr/bin/crypto_test/ctests | tee ${logfile}

	## Parse output from test
	info_msg "Parsing results from ${logfile}"

	# Expected output
	# Number of failures      : 0
	failures=$(grep 'Number of failures' ${logfile} | awk -F ':' '{gsub(/ /, "", $2); print $2}')

	if [ ${failures} -eq 0 ]; then
		result="pass"
	else
		result="fail"
	fi
	echo "ctests ${result}" | tee -a ${RESULT_FILE}

fi

# cleanup
rmmod crypto-safexcel-eip28
rmmod cryptotest
