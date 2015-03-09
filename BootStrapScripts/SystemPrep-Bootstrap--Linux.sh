#!/usr/bin/env bash
set -ex

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
LOGFILE="${LOGDIR}/${LOGTAG}-${TIMESTAMP}.log" # use double quotes to expand the variables immediately
LOGCMD="${LOGGER} -t ${LOGTAG}" 
TEELOG='tee -a ${LOGFILE} | ${LOGCMD}' # use single quotes to delay expansion until invocation

# Validate logger exists
if [[ (! -x ${LOGGER}) || (-z "${LOGGER}") ]]; then
	echo "Can't find 'logger' in path. Quitting..."
	exit
fi

# Validate log directory exists
if [[ ! -d ${LOGDIR} ]]; then
  echo "Creating ${LOGDIR} directory." 2>&1 | ${LOGCMD}
  mkdir ${LOGDIR} 2>&1 | ${LOGCMD}
fi

# Validate working directory exists
if [[ ! -d ${WORKINGDIR} ]]; then
  echo "Creating ${WORKINGDIR} directory" 2>&1 | ${LOGCMD}
  mkdir ${WORKINGDIR} 2>&1 | ${LOGCMD}
fi

# Change to the working directory
cd ${WORKINGDIR}

# Create the log file and write out the parameters
echo "Entering SystemPrep script -- ${SCRIPTNAME}" 2>&1 | ${TEELOG}
echo "Writing SystemPrep Parameters to log file..." 2>&1 | ${TEELOG}
for param in "${SYSTEMPREPPARAMS[@]}"; do echo "   ${param}" 2>&1 | ${TEELOG} ; done

# Download the master script
SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}
if [[ "true" = ${SOURCEISS3BUCKET,,} ]]; then
    if [[ (-x ${AWS}) && (! -z ${AWS}) ]]; then
        echo "Using AWS Tools to download from S3 Bucket -- ${SYSTEMPREPMASTERSCRIPTSOURCE}" 2>&1 | ${TEELOG}
        KEY=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{$1=$2=$3=""; print substr($0,4)}' OFS="/")
        ${AWS} s3 cp s3://${KEY} ${SCRIPTFULLPATH} --source-region ${AWSREGION}
    else
        echo "Missing 'aws' in path. Could not download file. Quitting..." 2>&1 | ${TEELOG}
        exit
else
    if [[ (-x ${CURL}) && (! -z ${CURL}) ]]; then
        echo "Using 'curl' to download from web host -- ${SYSTEMPREPMASTERSCRIPTSOURCE}" 2>&1 | ${TEELOG}
        ${CURL} -O -s -S ${SYSTEMPREPMASTERSCRIPTSOURCE} 2>&1 | ${TEELOG}
    elif [[ (-x ${WGET}) && (! -z ${WGET}) ]]; then
        echo "Using 'wget' to download from web host -- ${SYSTEMPREPMASTERSCRIPTSOURCE}" 2>&1 | ${TEELOG}
        ${WGET} -O -s ${SYSTEMPREPMASTERSCRIPTSOURCE} 2>&1 | ${TEELOG}
    else
        echo "Missing 'curl' or 'wget' in path. Could not download file. Quitting..." 2>&1 | ${TEELOG}
        exit
fi

# Convert the parameter list to a string
# The string will be converted to a python dictionary by the master script
PARAMSTRING=$( IFS=$' '; echo "${SYSTEMPREPPARAMS[*]}" )

# Execute the master script
SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}
echo "Running the SystemPrep master script -- ${SCRIPTFULLPATH}" $>> ${LOGFILE}
python ${SCRIPTFULLPATH} ${PARAMSTRING} &>> ${LOGFILE}

# Cleanup
echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}" $>> ${LOGFILE}
rm -f ${SCRIPTFULLPATH} &>> ${LOGFILE}

# Exit
echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}" &>> ${LOGFILE}
