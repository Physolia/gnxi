#!/bin/bash

##################################
### Demo of oc_config_validate ###
##################################

GNMI_PORT=9339
NO_TLS=0
ROOT_CA=0
CLIENT_TLS=0
STOP_ON_ERROR=0
LOG_GNMI=0
DEBUG=0

BASEDIR=$(dirname $0)
CERTSDIR=${BASEDIR}/../../certs
GNMI_TARGET=${BASEDIR}/../../gnmi_target/

build_gnmi_target() {

    if ! which go ; then
      echo "Install golang to run the gNMI Target"
      return 1
    fi
    go build -o ${BASEDIR}/ $GNMI_TARGET
}

# start_gnmi_target <gnmi_port>
start_gnmi_target() {

    OPTS="-key $CERTSDIR/target.key -cert $CERTSDIR/target.crt -ca $CERTSDIR/ca.crt"
    if [[ "$NO_TLS" -eq 1 ]]; then
        OPTS="--notls"
    fi

    echo "--- Start gNMI TARGET $OPTS"
    ${BASEDIR}/gnmi_target -bind_address ":$1" -config $BASEDIR/target_config.json --insecure $OPTS >> /dev/null 2>&1 &
    sleep 10
}

# stop_gnmi_target <gnmi_port>
stop_gnmi_target() {
    echo "--- Stop TARGET"
    pkill -f "gnmi_target -bind_address :$1"
}

# start_oc_config_validate <gnmi_port>
start_oc_config_validate() {
    OPTS=""
    if [[ "$NO_TLS" -eq 1 ]]; then
        OPTS="--no_tls"
    fi
    if [[ "$ROOT_CA" -eq 1 ]]; then
        OPTS="-ca $CERTSDIR/ca.crt"
    fi
    if [[ "$CLIENT_TLS" -eq 1 ]]; then
        OPTS="$OPTS -key $CERTSDIR/client.key -cert $CERTSDIR/client.crt"
    fi
    if [[ "$STOP_ON_ERROR" -eq 1 ]]; then
        OPTS="$OPTS --stop_on_error"
    fi
    if [[ "$LOG_GNMI" -eq 1 ]]; then
        OPTS="$OPTS --log_gnmi"
    fi
    if [[ "$VERBOSE" -eq 1 ]]; then
        OPTS="$OPTS --verbose"
    fi
    for t in config telemetry; do
      echo
      echo "--- Run oc_config_validate $OPTS for $t"
      echo
      PYTHONPATH="$PYTHONPATH:${BASEDIR}/.." python3 -m oc_config_validate --target "localhost:$1" --tests_file $BASEDIR/${t}_tests.yaml --results_file $BASEDIR/${t}_results.json --init_config_file $BASEDIR/init_config.json --init_config_xpath "/system/config" --target_cert_as_root_ca $OPTS
    done
  }

parse_options() {
  while getopts "p:NRCSLVh" opt; do
    case ${opt} in
      p )
        GNMI_PORT=$OPTARG
        ;;
      N )
        NO_TLS=1
        ;;
      R )
        ROOT_CA=1
        ;;
      C )
        CLIENT_TLS=1
        ;;
      S )
        STOP_ON_ERROR=1
        ;;
      L )
        LOG_GNMI=1
        ;;
      V )
        VERBOSE=1
        ;;
      * )
        echo "
demo.sh [-p <gNMI Port>]
        [-N] # No TLS
        [-R] # Use Root CA file
        [-C] # Use client TLS files
        [-S] # Stop on error
        [-L] # Log Gnmi messages to the test results
        [-V] # Enable verbose output
"
          return 1
        ;;
    esac
  done
return 0
}

main() {
    
    if parse_options "$@"; then
        if [[ ! ( -f $CERTSDIR/target.key && -f $CERTSDIR/target.crt && -f $CERTSDIR/ca.crt ) ]]; then
          echo "--- Creating local self-signed certificates"
          ( cd $CERTSDIR && ./generate.sh >> /dev/null 2>&1 )
        fi
        if [[ ! -f ${BASEDIR}/gnmi_target ]]; then
            echo "--- Building gNMI TARGET"
            if ! build_gnmi_target; then
              echo "ERR: Unable to build gnmi_target"
              return 1
            fi
        fi

        start_gnmi_target "${GNMI_PORT}"
        start_oc_config_validate "${GNMI_PORT}"
        stop_gnmi_target "${GNMI_PORT}"
    fi
}

main "$@"
