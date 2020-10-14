#!/bin/sh -x

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf3.txt"
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
CMD="usage"

usage() {
    echo "Usage: $0 [-c command] [-e server ethernet device] [-t time] [-p number] [-v version] [-A cpu affinity] [-R] [-r expected ping result] [-s true|false]" 1>&2
    exit 1
}

while getopts "A:c:e:t:p:v:s:r:Rh" o; do
  case "$o" in
    A) AFFINITY="-A ${OPTARG}" ;;
    c) CMD="${OPTARG}" ;;
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
	case "$CMD" in
		daemon)
			previous_msgseq=""
			while [ true ]; do
				# Wait for the client to make a request
				lava-wait client-request

				# read the client request
				request=$(grep "request" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
				msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

				if [ "${msgseq}" = "${previous_msgseq}" ]; then
					echo "Ignoring duplicate message ${msgseq}"
					continue
				fi

				# log this message so we don't handle it again
				previous_msgseq="${msgseq}"

				echo "client-request \"${request}\" with stamp ${msgseq} received"

				# perform the client request
				case "${request}" in
					"finished")
						echo "Client has signalled we are finished. Exiting."
						exit 0
						;;
					"iperf3-server")
						dump_msg_cache
						if [ "${IPERF3_SERVER_RUNNING}" != "pass" ]; then
							################################################################################
							# Start the server
							# report pass/fail as a test result
							# send the server's IP address to the client(s)
							################################################################################
							echo "Client has asked us to start the iperf3 server"
							cmd="iperf3 -s -D"
							${cmd}
							if pgrep -f "${cmd}" > /dev/null; then
								IPERF3_SERVER_RUNNING="pass"
							else
								IPERF3_SERVER_RUNNING="fail"
							fi
							echo "iperf3-server-running ${IPERF3_SERVER_RUNNING}" | tee -a "${RESULT_FILE}"
						else
							echo "iperf3 server is already running"
						fi

						if [ "${IPERF3_SERVER_RUNNING}" = "pass" ]; then
							lava-send server-ready ipaddr="${ipaddr}" msgseq="${msgseq}"
						fi
						;;
					"ping-request")
						dump_msg_cache

						ipaddr=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						echo "Client has asked us to ping address ${ipaddr} with msgseq=${msgseq}"
						pingresult=pass
						ping -c 5 "${ipaddr}" || pingresult="fail"
						lava-send client-ping-done pingresult="${pingresult}" msgseq="${msgseq}"
						;;
					"md5sum-request")
						dump_msg_cache
						filename=$(grep "filename" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
						echo "Client has asked us to md5sum ${filename}"
						our_sum=$(md5sum "${filename}" | tail -1 | cut -d " " -f 1 | tee -a "${filename}".md5)
						echo "Our md5sum is ${our_sum}"
						lava-send md5sum-result md5sum="${our_sum}" msgseq="${msgseq}"
						;;
					*) echo "Unknown client request: ${request}" ;;
				esac
				rm -f /tmp/lava_multi_node_cache.txt
			done
			;;
		ping-request)
			tx_msgseq="$(date +%s)"
			lava-send client-request request="ping-request" ipaddr="${ipaddr}" msgseq="${tx_msgseq}"
			wait_for_msg client-ping-done "${tx_msgseq}"

			pingresult=$(grep "pingresult" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
			echo "The daemon says that pinging the client returned ${pingresult}"
			echo "We are expecting ping to ${EXPECTED_RESULT}"

			if [ "${pingresult}" = "${EXPECTED_RESULT}" ]; then
				result="pass"
			else
				result="fail"
			fi
			echo "client-ping-request ${result}" | tee -a "${RESULT_FILE}"
			;;
		iperf3-server)
			tx_msgseq="$(date +%s)"
			lava-send client-request request="iperf3-server" msgseq="${tx_msgseq}"
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
			echo "iperf3-server ${result}" | tee -a "${RESULT_FILE}"
			;;
		iperf3-client)
			SERVER="$(cat /tmp/server.ipaddr)"
			if [ -z "${SERVER}" ]; then
				echo "ERROR: no server specified"
				exit 1
			else
				echo "Using SERVER=${SERVER}"
			fi

			# We are running in client mode
			# Run iperf3 test with unbuffered output mode.
			stdbuf -o0 iperf3 -c "${SERVER}" -t "${TIME}" -P "${THREADS}" "${REVERSE}" "${AFFINITY}" 2>&1 \
				| tee "${LOGFILE}"

			# Parse logfile.
			if [ "${THREADS}" -eq 1 ]; then
				grep -E "(sender|receiver)" "${LOGFILE}" \
					| awk '{printf("iperf3_%s pass %s %s\n", $NF,$7,$8)}' \
					| tee -a "${RESULT_FILE}"
			elif [ "${THREADS}" -gt 1 ]; then
				grep -E "[SUM].*(sender|receiver)" "${LOGFILE}" \
					| awk '{printf("iperf3_%s pass %s %s\n", $NF,$6,$7)}' \
					| tee -a "${RESULT_FILE}"
			fi
			;;
		scp-request)
			# TODO - this relies on running iperf3 tests first
			SERVER="$(cat /tmp/server.ipaddr)"
			if [ -z "${SERVER}" ]; then
				echo "ERROR: no server specified"
				exit 1
			else
				echo "Using SERVER=${SERVER}"
			fi

			filename=$(mktemp ~/largefile.XXXXX)
			dd if=/dev/urandom of="${filename}" bs=1M count=1024
			scp -o StrictHostKeyChecking=no "${filename}" root@"${SERVER}":"${filename}"
			our_sum=$(md5sum "${filename}" | tail -1 | cut -d " " -f 1 | tee -a "${filename}".md5)

			tx_msgseq="$(date +%s)"
			lava-send client-request request="md5sum-request" filename="${filename}" msgseq="${tx_msgseq}"
			wait_for_msg md5sum-result "${tx_msgseq}"
			their_sum=$(grep "md5sum" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')

			if [ "${their_sum}" = "${our_sum}" ]; then
				result=pass
			else
				result=fail
			fi
			echo "scp-request ${result}" | tee -a "${RESULT_FILE}"
			;;
		finished)
			lava-send client-request request="finished"
			;;
		*)
			usage
			;;
	esac
fi
echo "$0 ${result}" | tee -a "${RESULT_FILE}"
