#!/bin/sh -x

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf3.txt"
# If SERVER is blank, we are the server, otherwise
# If we are the client, we set SERVER to the ipaddr of the server
SERVER=""
# Time in seconds to transmit for
TIME="10"
# Number of parallel client streams to run
THREADS="1"
# Specify iperf3 version for CentOS.
VERSION="3.1.4"
# By default, the client sends to the server,
# Setting REVERSE="-R" means the server sends to the client
REVERSE=""
# CPU affinity is blank by default, meaning no affinity.
# CPU numbers are zero based, eg AFFINITY="-A 0" for the first CPU
AFFINITY=""
ETH="eth0"
EXPECTED_RESULT="pass"
IPERF3_SERVER_RUNNING="no"

usage() {
    echo "Usage: $0 [-c server] [-e server ethernet device] [-t time] [-p number] [-v version] [-A cpu affinity] [-R] [-s true|false]" 1>&2
    exit 1
}

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

create_out_dir "${OUTPUT}"
cd "${OUTPUT}"

if [ "${SKIP_INSTALL}" = "true" ] || [ "${SKIP_INSTALL}" = "True" ]; then
    info_msg "iperf3 installation skipped"
else
    dist_name
    # shellcheck disable=SC2154
    case "${dist}" in
        debian|ubuntu|fedora)
            install_deps "iperf3"
            ;;
        centos)
            install_deps "wget gcc make"
            wget https://github.com/esnet/iperf/archive/"${VERSION}".tar.gz
            tar xf "${VERSION}".tar.gz
            cd iperf-"${VERSION}"
            ./configure
            make
            make install
            ;;
    esac
fi

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
	echo "${ipaddr}" > "${ipaddrstash}"
fi
echo "My IP address is ${ipaddr}"

dump_msg_cache
rm -f /tmp/lava_multi_node_cache.txt

if [ "${ipaddr}" = "" ]; then
	echo "ERROR: ipaddr is invalid"
	actual_result="fail"
else
	tx_msgseq="$(date +%s)"
	lava-send client-request request="start-iperf3-server" msgseq="${tx_msgseq}"
	wait_for_msg server-ready "${tx_msgseq}"

	SERVER=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

	if [ -z "${SERVER}" ]; then
		echo "ERROR: no server specified"
		result="fail"
	else
		echo "server-ready: ${SERVER}"
		echo "${SERVER}" > /tmp/server.ipaddr
		result="pass"
	fi
fi
echo "start-iperf3-server ${result}" | tee -a "${RESULT_FILE}"
rm -f /tmp/lava_multi_node_cache.txt
