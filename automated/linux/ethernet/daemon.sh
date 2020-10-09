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

# Run local iperf3 server as a daemon when testing localhost.
cmd="lava-echo-ipv4"
if which "${cmd}"; then
    ipaddr=$(${cmd} "${ETH}" | tr -d '\0')
    if [ -z "${ipaddr}" ]; then
        lava-test-raise "${ETH} not found"
    fi
else
    echo "WARNING: command ${cmd} not found. We are not running in the LAVA environment."
fi


################################################################################
# Wait for client requests
################################################################################

# TODO -delete this debug
			echo "################################################################################"
			echo "/tmp/lava_multi_node_cache.txt"
			echo "################################################################################"
			cat /tmp/lava_multi_node_cache.txt || true
			echo "################################################################################"


while [ true ]; do
	# Wait for the client to request 
	cmd="lava-wait"
	if which "${cmd}"; then
		${cmd} client-request
	fi

	# read the client request
	request=$(grep "request" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')

	echo "client-request \"${request}\"received"

	# perform the client request
	case "${request}" in
		"finished")
			echo "Client has signalled we are finished. Exiting."
			exit 0
			;;
		"start-iperf3-server")
			echo "################################################################################"
			echo "/tmp/lava_multi_node_cache.txt"
			echo "################################################################################"
			cat /tmp/lava_multi_node_cache.txt || true
			echo "################################################################################"
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
				cmd="lava-send"
				if which "${cmd}"; then
					${cmd} server-ready ipaddr="${ipaddr}"
				fi
			fi
			;;
		"ping")
			echo "################################################################################"
			echo "/tmp/lava_multi_node_cache.txt"
			echo "################################################################################"
			cat /tmp/lava_multi_node_cache.txt || true
			echo "################################################################################"
			ipaddr=$(grep "ipaddr" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
			datestr=$(grep "datestr" /tmp/lava_multi_node_cache.txt | awk -F"=" '{print $NF}')
			echo "Client has asked us to ping address ${ipaddr} with datestr=${datestr}"
			echo -n "Our date is " ; date --rfc-3339=ns
			pingresult=pass
			ping -c 5 "${ipaddr}" || pingresult="fail"
			cmd="lava-send"
			if which "${cmd}"; then
				${cmd} client-ping-done pingresult="${pingresult}"
			fi
			;;
		*) echo "Unknown client request: ${request}" ;;
	esac
done

################################################################################
exit 0
################################################################################
