#!/bin/sh
#
# Description:
#   This script is intended to help an administrator update the content
#   managed by the SystemPrep capability. It will use the SystemPrep
#   BootStrap script to download new content and configure it to be available
#   on the system.
#
# Usage:
#   See `systemprep-updatecontent.sh -h`.
#
#################################################################
__SCRIPTPATH=$(readlink -f ${0})
__SCRIPTDIR=$(dirname ${__SCRIPTPATH})
__SCRIPTNAME=$(basename ${__SCRIPTPATH})


log()
{
    if [ "$1" != "-v" ]
    then
        logger -i -t "${__SCRIPTNAME}" -s -- "$1" 2> /dev/console
        echo "$1"
    elif [ -n "${VERBOSE}" ]
    then
        log "$2"
    fi
}  # ----------  end of function log  ----------


die()
{
    [ -n "$1" ] && log "$1" >&2
    log "ERROR: ${__SCRIPTNAME} failed"'!' >&2
    exit 1
}  # ----------  end of function die  ----------


print_usage()
{
    cat << EOT

  This script will update the content managed by the systemprep capability.
  Parameters may be passed as short-form or long-form arguments, or they may
  be exported as environment variables. Command line arguments take precedence
  over environment variables.

  Usage: ${__SCRIPTNAME} [required] [options]

  Required:
  -e|--environment|\$SYSTEMPREP_ENV
      The environment in which the system is operating. This is parameter
      accepts a tri-state value:
        "true":   Attempt to detect the environment automatically. WARNING:
                  Currently this value is non-functional.
        "false":  Do not set an environment. Any content that is dependent on
                  the environment will not be available to this system.
        <string>: Set the environment to the value of "<string>". Note that
                  uppercase values will be converted to lowercase.

  Options:
  -p|--oupath|\$SYSTEMPREP_OUPATH
      The OU in which to place the instance when joining the domain. If unset
      or an empty string, the framework will use the value from the enterprise
      environment pillar. Default is "".
  -u|--bootstrap-url|\$SYSTEMPREP_BOOTSTRAP_URL
      URL of the systemprep bootstrapper.
  -h|--help
      Display this message.
  -v|--verbose
      Display verbose output

EOT
}  # ----------  end of function print_usage  ----------


lower()
{
    echo "${1}" | tr '[:upper:]' '[:lower:]'
}  # ----------  end of function lower  ----------


# Define default values
SYSTEMPREP_ENV="${SYSTEMPREP_ENV}"
OUPATH="${SYSTEMPREP_OUPATH}"
BOOTSTRAP_URL="${SYSTEMPREP_BOOTSTRAP_URL:-https://systemprep.s3.amazonaws.com/BootStrapScripts/SystemPrep-Bootstrap--Linux.sh}"
VERBOSE=

# Parse command-line parameters
SHORTOPTS="hve:u:p:"
LONGOPTS="help,verbose,environment:,bootstrap-url:,oupath:"
ARGS=$(getopt \
    --options "${SHORTOPTS}" \
    --longoptions "${LONGOPTS}" \
    --name "${__SCRIPTNAME}" \
    -- "$@")

if [ $? -ne 0 ]
then
    # Bad arguments.
    print_usage
    exit 1
fi

eval set -- "${ARGS}"

while [ true ]
do
    # When adding options to the case statement, be sure to update SHORTOPTS
    # and LONGOPTS
    case "${1}" in
        -h|--help)
            print_usage
            exit 0
            ;;
        -e|--environment)
            shift
            SYSTEMPREP_ENV=$(lower "${1}")
            ;;
        -p|--oupath)
            shift
            OUPATH="${1}"
            ;;
        -u|--bootstrap-url)
            shift
            BOOTSTRAP_URL="${1}"
            ;;
        -v|--verbose)
            VERBOSE="true"
            ;;
        --)
            shift
            break
            ;;
        *)
            print_usage
            die "ERROR: Unhandled option parsing error."
            ;;
    esac
    shift
done


# Validate parameters
if [ -z "${SYSTEMPREP_ENV}" ]
then
    print_usage
    die "ERROR: Mandatory parameter (-e|--environment) was not specified."
fi

log -v "Printing parameters:"
log -v "  environment:   ${SYSTEMPREP_ENV}"
log -v "  oupath: ${OUPATH}"
log -v "  bootstrap-url: ${BOOTSTRAP_URL}"


# Check dependencies
if [ $(command -v curl > /dev/null 2>&1)$? -ne 0 ]
then
    die "ERROR: Could not find 'curl'."
fi


# Execute
log "Using bootstrapper to update systemprep content..."
curl -L --retry 3 --silent --show-error "${BOOTSTRAP_URL}" | \
    sed "{
        s/^ENTENV=.*/ENTENV=\"${SYSTEMPREP_ENV}\"/
        s/^OUPATH=.*/OUPATH=\"${OUPATH}\"/
        s/^NOREBOOT=.*/NOREBOOT=\"True\"/
        s/^SALTSTATES=.*/SALTSTATES=\"None\"/
    }" | \
    bash || \
    die "ERROR: systemprep bootstrapper failed."

log "Sucessfully updated systemprep content."
