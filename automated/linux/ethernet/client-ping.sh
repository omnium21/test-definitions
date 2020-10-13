#!/bin/sh -x

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
ETH="eth0"
EXPECTED_RESULT="pass"

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

while getopts "A:c:e:t:p:v:s:r:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    c) SERVER="${OPTARG}" ;;
    e) ETH="${OPTARG}" ;;
    t) TIME="${OPTARG}" ;;
    p) THREADS="${OPTARG}" ;;
    r) EXPECTED_RESULT="${OPTARG}" ;;
    R) REVERSE="-R" ;;
    v) VERSION="${OPTARG}" ;;
    s) SKIP_INSTALL="${OPTARG}" ;;
    h|*) usage ;;
  esac
done

command_exists(){
	local cmd

	cmd="$1"

	if ! which "${cmd}"; then
		echo "ERROR: ${cmd} not available"
		exit 1
	fi
}
command_exists "lava-echo-ipv4"
command_exists "lava-send"
command_exists "lava-wait"
command_exists "ping"

# Run local iperf3 server as a daemon when testing localhost.
#ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
#if [ -z "${ipaddr}" ]; then
#	lava-test-raise "${ETH} not found"
#fi

get_ipaddr() {
	local ipaddr
	local interface

	interface="${1}"
	ipaddr=$(ip addr show "${interface}" | grep -a2 "state " | grep "inet "| tail -1 | awk '{print $2}' | cut -f1 -d'/')
	echo "${ipaddr}"
}

dump_msg_cache(){
	# TODO -delete this debug
	echo "################################################################################"
	echo "/tmp/lava_multi_node_cache.txt"
	echo "################################################################################"
	cat /tmp/lava_multi_node_cache.txt || true
	echo "################################################################################"
}


wait_for_msg(){
	local message="${1}"
	local msgseq="${2}"

	while [ true ]; do
		# Wait for the daemon to respond
		lava-wait "${message}"

		dump_msg_cache

		# report pass/fail depending on whether we expected ping to succeed or not
		rx_msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

		if [ "${rx_msgseq}" -lt "${msgseq}" ]; then
			echo "WARNING: Ignoring duplicate message (${rx_msgseq} < ${msgseq})"
			rm -f /tmp/lava_multi_node_cache.txt
			continue
		elif [ "${rx_msgseq}" -gt "${msgseq}" ]; then
			echo "ERROR: We missed the reply to our message (rx_msgseq=${rx_msgseq} > msgseq=${msgseq})"
			# TODO - report lava test fail
			exit 1
		else
			echo "ACK: we found the droid we were looking for..."
			break
		fi
	done
}


echo "################################################################################"
ip addr show
echo "################################################################################"

# Try to get the stashed IP address first, otherwise, try to work it out
ipaddrstash="/tmp/ipaddr-${ETH}.txt"
if [ -e "${ipaddrstash}" ]; then
	ipaddr="$(cat ${ipaddrstash})"
else
	ipaddr=$(get_ipaddr $ETH)
fi

dump_msg_cache
rm -f /tmp/lava_multi_node_cache.txt

if [ "${ipaddr}" = "" ]; then
	echo "ERROR: ipaddr is invalid"
	# TODO - report lava test fail
	exit 1
fi

tx_msgseq="$(date +%s)"
lava-send client-request request="ping" ipaddr="${ipaddr}" msgseq="${tx_msgseq}"
wait_for_msg client-ping-done "${tx_msgseq}"

rx_msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
pingresult=$(grep "pingresult" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
echo "The daemon says that pinging the client returned ${pingresult} stamp ${rx_msgseq}"
echo "We are expecting ping to ${EXPECTED_RESULT}"

if [ "${tx_msgseq}" = "${rx_msgseq}" ]; then
	echo "tx_msgseq ${tx_msgseq} matches rx_msgseq ${rx_msgseq}"
else
	echo "WARNING: tx_msgseq ${tx_msgseq} DOES NOT match rx_msgseq ${rx_msgseq}"
	# TODO - what do we do about this??
fi

if [ "${pingresult}" = "${EXPECTED_RESULT}" ]; then
	actual_result="pass"
else
	actual_result="fail"
fi
echo "client-ping-request ${actual_result}" | tee -a "${RESULT_FILE}"
rm -f /tmp/lava_multi_node_cache.txt
