#!/usr/bin/env bash
set -e

#User variables
SOURCEISS3BUCKET="True"
AWSREGION="us-east-1"
SYSTEMPREPMASTERSCRIPTSOURCE="https://s3.amazonaws.com/systemprep/MasterScripts/systemprep-linuxmaster.py"
SYSTEMPREPPARAMS=( "SaltStates=Highstate"
                   "NoReboot=False"
                   "SourceIsS3Bucket=${SOURCEISS3BUCKET}"
                   "AwsRegion=${AWSREGION}" )

#System variables
SCRIPTNAME=${0}
LOGGER=$(which logger)
TIMESTAMP=$(date -u +"%Y%m%d_%H%M_%S")
WORKINGDIR=/usr/tmp
LOGDIR=/var/log
LOGTAG=systemprep
LOGFILE="${LOGDIR}/${LOGTAG}-${TIMESTAMP}.log"
LOGLINK="${LOGDIR}/${LOGTAG}.log"

# Validate log directory exists
if [[ ! -d ${LOGDIR} ]]; then
  echo "Creating ${LOGDIR} directory." >(${LOGGER} -t "${LOGTAG}" -s 2> /dev/console) 2>&1
  mkdir ${LOGDIR} >(${LOGGER} -i -t "${LOGTAG}" -s 2> /dev/console) 2>&1
fi

# Validate working directory exists
if [[ ! -d ${WORKINGDIR} ]]; then
  echo "Creating ${WORKINGDIR} directory" >(${LOGGER} -t "${LOGTAG}" -s 2> /dev/console) 2>&1
  mkdir ${WORKINGDIR} >(${LOGGER} -i -t "${LOGTAG}" -s 2> /dev/console) 2>&1
fi

# Establish logging to write to the logfile, syslog, and the console
exec > >(tee "${LOGFILE}" | "${LOGGER}" -i -t "${LOGTAG}" -s 2> /dev/console) 2>&1

# Create the link to the logfile
touch ${LOGFILE}
ln -s -f ${LOGFILE} ${LOGLINK}

# Change to the working directory
cd ${WORKINGDIR}

# Create the log file and write out the parameters
echo "Entering SystemPrep script -- ${SCRIPTNAME}"
echo "Writing SystemPrep Parameters to log file..."
for param in "${SYSTEMPREPPARAMS[@]}"; do echo "   ${param}" ; done

# Download the master script
SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}
if [[ "true" = ${SOURCEISS3BUCKET,,} ]]; then
    echo "Downloading master script from S3 bucket using AWS Tools -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
    hash aws 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Try to get 'aws' in the path
    KEY=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{$1=$2=$3=""; print substr($0,4)}' OFS="/")
    aws s3 cp s3://${KEY} ${SCRIPTFULLPATH} --source-region ${AWSREGION} || \
        echo "Could not download file using AWS Tools. Check the url, the instance role, and whether 'aws' is in path. Quitting..."
    if [[ ! -e "${SCRIPTFULLPATH}" ]]; then
        exit 1
    fi
else
    echo "Downloading master script from web host -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
    curl -L -O -s -S ${SYSTEMPREPMASTERSCRIPTSOURCE} || \
        wget --quiet ${SYSTEMPREPMASTERSCRIPTSOURCE}
    if [[ ! -e "${SCRIPTFULLPATH}" ]]; then
        echo "Could not download file via 'curl' or 'wget'."
        echo "Check the url and whether at least one of them is in the path. Quitting..."
        exit 1
    fi
fi

# Convert the parameter list to a string
# The string will be converted to a python dictionary by the master script
PARAMSTRING=$( IFS=$' '; echo "${SYSTEMPREPPARAMS[*]}" )

# Temporarily suppress rsyslog rate limiting
if [[ -e /etc/rsyslog.conf ]]; then
    echo "Temporarily disabling rsyslog rate limiting"
    RSYSLOGFLAG=1
    # Replace or append the $SystemLogRateLimitInterval parameter
    grep -q '^$SystemLogRateLimitInterval' /etc/rsyslog.conf && \
        sed -i.bak -e \
        "s/^$SystemLogRateLimitInterval.*/$SystemLogRateLimitInterval 0/" \
        /etc/rsyslog.conf || \
        sed -i.bak "$ a\$SystemLogRateLimitInterval 0" /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi
# Temporarily suppress journald rate limiting
if [[ -e /etc/systemd/journald.conf ]]; then
    echo "Temporarily disabling journald rate limiting"
    JOURNALDFLAG=1
    # Replace or append the RateLimitInterval parameter
    grep -q '^RateLimitInterval' /etc/systemd/journald.conf && \
        sed -i.bak -e \
        "s/^RateLimitInterval.*/RateLimitInterval=0/" \
        /etc/rsyslog.conf || \
        sed -i.bak "$ a\RateLimitInterval=0" /etc/systemd/journald.conf
    echo "Restarting systemd-journald..."
    systemctl restart systemd-journald.service
fi

# Execute the master script
echo "Running the SystemPrep master script -- ${SCRIPTFULLPATH}"
python ${SCRIPTFULLPATH} ${PARAMSTRING}
result = $?  # Capture the exit status of the script

# Restore prior rsyslog config
if [[ -n "${RSYSLOGFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 2
    echo "Re-storing previous rsyslog configuration"
    mv -f /etc/rsyslog.conf.bak /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi
# Restore prior journald config
if [[ -n "${JOURNALDFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 2
    echo "Re-storing previous journald configuration"
    mv -f /etc/systemd/journald.conf.bak /etc/systemd/journald.conf
    echo "Restarting systemd-journald..."
    systemctl restart systemd-journald.service
fi

# Cleanup
echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}"
rm -f ${SCRIPTFULLPATH}

# Report success or failure
if [[ $result -eq 0 ]]; then
    echo "SUCCESS: SystemPrep Master script completed successfully!"
else
    echo "ERROR: There was an error executing the SystemPrep Master script!"
    echo "Check the log file at: ${LOGLINK}"
fi

# Exit
echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}"
