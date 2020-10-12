#!/bin/sh -x

# shellcheck disable=SC1091
. ../../lib/sh-test-lib
OUTPUT="$(pwd)/output"
RESULT_FILE="${OUTPUT}/result.txt"
LOGFILE="${OUTPUT}/iperf3.txt"
IPERF3_SERVER_RUNNING="no"
VERSION="3.1.4"
ETH="eth0"

usage() {
    echo "Usage: $0 [-e server ethernet device] [-v version] [-s true|false]" 1>&2
    exit 1
}

while getopts "A:c:e:t:p:v:s:Rh" o; do
  case "$o" in
    e) ETH="${OPTARG}" ;;
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

# Run local iperf3 server as a daemon when testing localhost.
ipaddr=$(lava-echo-ipv4 "${ETH}" | tr -d '\0')
if [ -z "${ipaddr}" ]; then
	lava-test-raise "${ETH} not found"
fi

################################################################################
# Wait for client requests
################################################################################

dump_msg_cache(){
	# TODO -delete this debug
	echo "################################################################################"
	echo "/tmp/lava_multi_node_cache.txt"
	echo "################################################################################"
	cat /tmp/lava_multi_node_cache.txt || true
	echo "################################################################################"
}

dump_msg_cache
rm -f /tmp/lava_multi_node_cache.txt

previous_msgseq=""
while [ true ]; do
	# Wait for the client to request 
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
		"start-iperf3-server")
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
				echo "iperf3_server_started ${IPERF3_SERVER_RUNNING}" | tee -a "${RESULT_FILE}"
			else
				echo "iperf3 server is already running"
			fi

			if [ "${IPERF3_SERVER_RUNNING}" = "pass" ]; then
				lava-send server-ready ipaddr="${ipaddr}" msgseq="${msgseq}"
			fi
			;;
		"ping")
			dump_msg_cache

			ipaddr=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
			msgseq=$(grep "msgseq" /tmp/lava_multi_node_cache.txt | tail -1 | awk -F"=" '{print $NF}')
			echo "Client has asked us to ping address ${ipaddr} with msgseq=${msgseq}"
			pingresult=pass
			ping -c 5 "${ipaddr}" || pingresult="fail"

			# Don't set msgseq, reply with the same so the sender can match up the messages
			# msgseq=$(date +%s)

			lava-send client-ping-done pingresult="${pingresult}" msgseq="${msgseq}"
			;;
		*) echo "Unknown client request: ${request}" ;;
	esac
	rm -f /tmp/lava_multi_node_cache.txt
done

################################################################################
exit 0
################################################################################
