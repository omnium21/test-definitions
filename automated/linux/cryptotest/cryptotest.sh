#!/bin/sh
# shellcheck disable=SC1091

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
CUNIT_FILE="CUnitAutomated-Results.xml"
CRYPTO_DEVICE="/dev/cryptotest"
CTESTS="/usr/bin/crypto_test/ctests"

#TODO . ../../lib/sh-test-lib
#TODO create_out_dir "${OUTPUT}"
mkdir -p ${OUTPUT}

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

################################################################################
# Copied from automated/linux/spectre-meltdown-checker-test/bin/spectre-meltdown-checker.sh
# example usage:
#	dmesg_grep 'Xen HVM callback vector for event delivery is enabled$'; ret=$?
################################################################################
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

################################################################################
#
################################################################################
file_exists()
{
	file=$1
	if [ -e "${file}" ]; then
		result="pass"
	else
		result="fail"
	fi
	echo "file_exists_$file ${result}" | sed 'sX/X_Xg' | tee -a "${RESULT_FILE}"
}

################################################################################
#
################################################################################
check_file_list()
{
	filelist="$*"
	for file in ${filelist}; do
		file_exists "$file"
	done
}

################################################################################
#
################################################################################
eip_test()
{
	local testcase="${1}"
	local params="${2}"
	local expected_result="${3}"
	local description="${4}"

	if [ "${result}" = pass ]; then
		echo "${testcase}: ${description}"

		${CTESTS} ${params} | tee ${testcase}.log

		if grep "${expected_result}" ${testcase}.log > /dev/null; then
			result=pass
		else
			result=fail
		fi
	else
		result=skip
	fi
	echo "${testcase} ${result}" | tee -a ${RESULT_FILE}
}

################################################################################
#
################################################################################
eip_test_double()
{
	local testcase="${1}"
	local params="${2}"
	local expected_result_1="${3}"
	local expected_result_2="${4}"
	local description="${5}"

	if [ "${result}" = pass ]; then
		echo "${testcase}: ${description}"

		${CTESTS} ${params} | tee ${testcase}.log

		result_1=$(cat ${testcase}.log | grep -e "Success!" -e "Failed!" | head -1)
		result_2=$(cat ${testcase}.log | grep -e "Success!" -e "Failed!" | tail -1)
		if echo ${result_1} | grep -e ${expected_result_1}  && echo ${result_2} | grep -e ${expected_result_2}; then
			result=pass
		else
			result=fail
		fi
	else
		result=skip
	fi
	echo "${testcase} ${result}" | tee -a ${RESULT_FILE}
}


# Check device does NOT exist
# It won't exist until the module is inserted
if [ -c "${CRYPTO_DEVICE}" ]; then
	result="fail"
else
	result="pass"
fi
echo "device-not-exists-yet ${result}" | tee -a ${RESULT_FILE}

if [ "${result}" = pass ]; then
	module_cryptotest=$(find /lib/modules/ -name cryptotest.ko)
	if [ -n "${module_cryptotest}" ] && insmod ${module_cryptotest}; then
		result="pass"
	else
		result="fail"
	fi
else
	result="skip"
fi
echo "insmod-cryptotest ${result}" | tee -a ${RESULT_FILE}

if [ "${result}" = pass ]; then
	# Check device exists
	if [ -c ${CRYPTO_DEVICE} ]; then
		result="pass"
	else
		result="fail"
	fi
else
	result="skip"
fi
echo "device-exists ${result}" | tee -a ${RESULT_FILE}

if [ "${result}" = pass ]; then
	module_eip28=$(find /lib/modules/ -name crypto-safexcel-eip28.ko)
	if [ -n "${module_eip28}" ] && insmod ${module_eip28}; then
		result="pass"
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
	else
		result="fail"
	fi
else
	result="skip"
fi
echo "insmod-crypto-safexcel-eip28 ${result}" | tee -a ${RESULT_FILE}

if [ "${result}" = pass ]; then
	if [ -e "${CTESTS}" ]; then
		result="pass"
	else
		result="fail"
	fi
else
	result="skip"
fi
echo ctests-exist ${result} | tee -a ${RESULT_FILE}

if [ "${result}" = pass ]; then
	TESTDIR=$(mktemp -d "/tmp/ctests.XXXXX")
	rm -rf "${TESTDIR}"
	mkdir -p "${TESTDIR}"
	cd "${TESTDIR}"

	${CTESTS} -f 12345

	filelist="\
		ecc_test/eccfile.txt \
		ecc_test/openssl_1/signature_521.bin \
		ecc_test/openssl_1/public_521_wrong.bin \
		ecc_test/openssl_1/public_521.bin \
		ecc_test/openssl_1/private_521_wrong.bin \
		ecc_test/openssl_1/private_521.bin \
		ecc_test/openssl_1/signature_384.bin \
		ecc_test/openssl_1/public_384_wrong.bin \
		ecc_test/openssl_1/public_384.bin \
		ecc_test/openssl_1/private_384_wrong.bin \
		ecc_test/openssl_1/private_384.bin \
		ecc_test/openssl_1/signature_256.bin \
		ecc_test/openssl_1/public_256_wrong.bin \
		ecc_test/openssl_1/public_256.bin \
		ecc_test/openssl_1/private_256_wrong.bin \
		ecc_test/openssl_1/private_256.bin \
		ecc_test/openssl_1/signature_224.bin \
		ecc_test/openssl_1/public_224_wrong.bin \
		ecc_test/openssl_1/public_224.bin \
		ecc_test/openssl_1/private_224_wrong.bin \
		ecc_test/openssl_1/private_224.bin \
		ecc_test/openssl_1/signature_192.bin \
		ecc_test/openssl_1/public_192_wrong.bin \
		ecc_test/openssl_1/public_192.bin \
		ecc_test/openssl_1/private_192_wrong.bin \
		ecc_test/openssl_1/private_192.bin \
		ecc_test/openssl/signature_521.bin \
		ecc_test/openssl/public_521_wrong.bin \
		ecc_test/openssl/public_521.bin \
		ecc_test/openssl/private_521_wrong.bin \
		ecc_test/openssl/private_521.bin \
		ecc_test/openssl/signature_384.bin \
		ecc_test/openssl/public_384_wrong.bin \
		ecc_test/openssl/public_384.bin \
		ecc_test/openssl/private_384_wrong.bin \
		ecc_test/openssl/private_384.bin \
		ecc_test/openssl/signature_256.bin \
		ecc_test/openssl/public_256_wrong.bin \
		ecc_test/openssl/public_256.bin \
		ecc_test/openssl/private_256_wrong.bin \
		ecc_test/openssl/private_256.bin \
		ecc_test/openssl/signature_224.bin \
		ecc_test/openssl/public_224_wrong.bin \
		ecc_test/openssl/public_224.bin \
		ecc_test/openssl/private_224_wrong.bin \
		ecc_test/openssl/private_224.bin \
		ecc_test/openssl/signature_192.bin \
		ecc_test/openssl/public_192_wrong.bin \
		ecc_test/openssl/public_192.bin \
		ecc_test/openssl/private_192_wrong.bin \
		ecc_test/openssl/private_192.bin \
		ecc_test/openssl/hash \
	"
	check_file_list "${filelist}"
else
	result="skip"
fi
echo "check_file_list ${result}" | tee -a ${RESULT_FILE}

eip_test        "EIP-001" "-l 256 -k pub -d"              "Success!"            "Test case 1, good test on signature generated from openssl, with test data displayed"
eip_test        "EIP-002" "-l 256 -k pub"                 "Success!"            "Test case 2, good test on signature generated from openssl, without test data displayed"
eip_test        "EIP-003" "-l 256 -k pub -e h"            "Failed!"             "Test case 3, VERIFY test with hash error"
eip_test        "EIP-004" "-l 256 -k pub -e p"            "Failed!"             "Test case 4, VERIFY test with public key error"
eip_test        "EIP-005" "-l 256 -k pub -e s"            "Failed!"             "Test case 5, VERIFY test with signature error"
eip_test        "EIP-009" "-l 256 -k pub -s"              "Failed!"             "Test case 9, error VERFIY test with no signature generated from eip28," 
eip_test        "EIP-006" "-l 256 -k pri -d"              "Success!"            "Test case 6, good test, with test data displayed"
eip_test        "EIP-007" "-l 256 -k pri"                 "Success!"            "Test case 7, good test, without test data displayed" 
eip_test        "EIP-008" "-l 256 -k pub -s"              "Success!"            "Test case 8, good VERIFY test on signature generated from eip28," 
eip_test        "EIP-010" "-l 256 -k pub -s -e h"         "Failed!"             "Test case 10, error VERIFY test on signature generated from eip28, but modified error hash,"
eip_test        "EIP-011a" "-l 256 -k pri -e p"           "Success!"            "Test case 11, SIGN test with private key error"
eip_test        "EIP-011b" "-l 256 -k pub -s"             "Failed!"             "Test case 11, SIGN test with private key error"
eip_test        "EIP-012a" "-l 256 -k pri -e h"           "Success!"            "Test case 12, SIGN test with hash error"
eip_test        "EIP-012b" "-l 256 -k pub -s"             "Failed!"             "Test case 12, SIGN test with hash error"
eip_test        "EIP-013" "-l 256 -t 5"                   "SUCCESS"             "Test case 13, ECDSA Multithread test" 
eip_test_double "EIP-014" "-l 256 -c ecdh -p g -d"        "Success!" "Success!" "Test case 14, good test, with test data displayed"
eip_test_double "EIP-015" "-l 256 -c ecdh -p g"           "Success!" "Success!" "Test case 15, good test, with test data displayed"
eip_test        "EIP-016" "-l 256 -c ecdh -p g -e p -d"   "Failed!"             "Test case 16, private key error"
eip_test        "EIP-017" "-l 256 -c ecdh -p c -d"        "Success!"            "Test case 17, good test, with test data displayed"
eip_test        "EIP-018" "-l 256 -c ecdh -p c"           "Success!"            "Test case 18, good test, without test data displayed"
eip_test        "EIP-019" "-l 256 -c ecdh -p c -e p -d"   "Failed!"             "Test case 19, private key error"
eip_test        "EIP-019" "-l 256 -c ecdh -p c -e p -d"   "Failed!"             "Test case 19, private key error"
eip_test        "EIP-020" "-l 256 -c ecdh -p c -e q -d"   "Failed!"             "Test case 20, public key error"
eip_test        "EIP-021" "-l 256 -c ecdh -t 5"           "SUCCESS"             "Test case 21, ECDH Multithread test"

# cleanup
if [ -n "${module_eip28}" ] && rmmod ${module_eip28}; then
	result="pass"
else
	result="fail"
fi
echo "rmmod-crypto-safexcel-eip28 ${result}" | tee -a ${RESULT_FILE}

if [ -n "${module_cryptotest}" ] && rmmod ${module_cryptotest}; then
	result="pass"
else
	result="fail"
fi
echo "rmmod-cryptotest ${result}" | tee -a ${RESULT_FILE}
