#!/bin/bash
# shellcheck disable=SC1091

OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"

#. ../../lib/sh-test-lib
#create_out_dir "${OUTPUT}"
mkdir -p ${OUTPUT}

usage() {
    echo "Usage: $0" 1>&2
    exit 1
}

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
sha="22a6ae81ea7162e91ca5623e227ff7fbfa66049c"
url="https://raw.githubusercontent.com/tpm2-software/tpm2-tss-engine/${sha}/test/"

################################################################################
#
################################################################################
tpm_test()
{
	local file="$1"
	local success_string="$2"
	local result=fail

	echo "################################################################################"
	echo "test: $file    success_string: ${success_string}"
	echo "################################################################################"

	wget -q ${url}/${file} || echo "ERROR: wget ${file} failed"
	if [ -e "${file}" ]; then
		rm -f /tmp/tpm.log || true
		bash $file 2>&1 | tee /tmp/tpm.log
		grep -e "${success_string}" /tmp/tpm.log && result=pass
	fi
	echo "$file $result" | tee -a ${RESULT_FILE}
}

################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
test_matrix=(
	ecdsa-emptyauth.sh              "Signature Verified Successfully"
	ecdsa.sh                        "Signature Verified Successfully"
	ecdsa-handle-flush.sh           "Signature Verified Successfully"
	rand.sh                         "engine \"tpm2tss\" set."
	rsadecrypt.sh                   "test xabcde12345abcde12345 = xabcde12345abcde12345"
	rsasign.sh                      "Signature Verified Successfully"
	rsasign_parent.sh               "Signature Verified Successfully"
	rsasign_parent_pass.sh          "Signature Verified Successfully"
	rsasign_persistent.sh           "Signature Verified Successfully"
	rsasign_persistent_emptyauth.sh "Signature Verified Successfully"
	sclient.sh                      "SUCCESS"
	sserver.sh                      "Verify return code: 0 (ok)"
)

for ((i=0;i<${#test_matrix[@]};i=$i+2)); do
	tpm_test "${test_matrix[${i}]}" "${test_matrix[${i}+1]}"
done

echo "################################################################################"
cat ${RESULT_FILE}
