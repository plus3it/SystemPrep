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
AWS=$(which aws)
CURL=$(which curl)
WGET=$(which wget)
LOGGER=$(which logger)
TIMESTAMP=$(date -u +"%Y%m%d_%H%M_%S")
WORKINGDIR=/usr/tmp
LOGDIR=/var/log
LOGTAG=systemprep
LOGFILE="${LOGDIR}/${LOGTAG}-${TIMESTAMP}.log"
LOGLINK="${LOGDIR}/${LOGTAG}.log"

# Validate logger exists
if [[ (! -x ${LOGGER}) || (-z "${LOGGER}") ]]; then
	echo "Can't find 'logger' in path. Quitting..." > /dev/console 2>&1
	exit
fi

# Validate log directory exists
if [[ ! -d ${LOGDIR} ]]; then
  echo "Creating ${LOGDIR} directory." >(${LOGGER} -t "${LOGTAG}" -s 2> /dev/console) 2>&1
  mkdir ${LOGDIR} >(${LOGGER} -t "${LOGTAG}" -s 2> /dev/console) 2>&1
fi

# Validate working directory exists
if [[ ! -d ${WORKINGDIR} ]]; then
  echo "Creating ${WORKINGDIR} directory" >(${LOGGER} -t "${LOGTAG}" -s 2> /dev/console) 2>&1
  mkdir ${WORKINGDIR} >(${LOGGER} -t "${LOGTAG}" -s 2> /dev/console) 2>&1
fi

# Establish logging to write to the logfile, syslog, and the console
exec > >(tee "${LOGFILE}" | "${LOGGER}" -t "${LOGTAG}" -s 2> /dev/console) 2>&1

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
    if [[ (-x ${AWS}) && (! -z ${AWS}) ]]; then
        echo "Using AWS Tools to download from S3 Bucket -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
        KEY=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{$1=$2=$3=""; print substr($0,4)}' OFS="/")
        ${AWS} s3 cp s3://${KEY} ${SCRIPTFULLPATH} --source-region ${AWSREGION}
    else
        echo "Missing 'aws' in path. Could not download file. Quitting..."
        exit
    fi
else
    if [[ (-x ${CURL}) && (! -z ${CURL}) ]]; then
        echo "Using 'curl' to download from web host -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
        ${CURL} -L -O -s -S ${SYSTEMPREPMASTERSCRIPTSOURCE}
    elif [[ (-x ${WGET}) && (! -z ${WGET}) ]]; then
        echo "Using 'wget' to download from web host -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
        ${WGET} --quiet ${SYSTEMPREPMASTERSCRIPTSOURCE}
    else
        echo "Missing 'curl' or 'wget' in path. Could not download file. Quitting..."
        exit
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

# Execute the master script
SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}
echo "Running the SystemPrep master script -- ${SCRIPTFULLPATH}"
python ${SCRIPTFULLPATH} ${PARAMSTRING}

# Restore prior rsyslog config
if [[ -n "${RSYSLOGFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 2
    echo "Re-storing previous rsyslog configuration"
    mv -f /etc/rsyslog.conf.bak /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi

# Cleanup
echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}"
rm -f ${SCRIPTFULLPATH}

# Exit
echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}"
