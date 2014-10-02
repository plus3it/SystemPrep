#!/usr/bin/env bash
set -ex

#User variables
SYSTEMPREPMASTERSCRIPTURL="https://systemprep.s3.amazonaws.com/MasterScripts/systemprep-linuxmaster.py"
PARAMS=( "SaltStates=Highstate" 
         "NoReboot=False" )

#System variables
SCRIPTNAME=$0
WORKINGDIR=/usr/tmp/systemprep
TIMESTAMP=$(date -u +"%Y%m%d_%H%M_%S")
LOGFILE=/var/log/systemprep-log-${TIMESTAMP}.txt

if [[ ! -d "${WORKINGDIR}" ]] ; then mkdir ${WORKINGDIR} ; fi
cd ${WORKINGDIR}
echo "Entering SystemPrep script -- ${SCRIPTNAME}" &> ${LOGFILE}
echo "Writing SystemPrep Parameters to log file..." &>> ${LOGFILE}
for key in "${!SYSTEMPREPPARAMS[@]}"; do echo "   ${key} = ${SYSTEMPREPPARAMS["$key"]}" &>> ${LOGFILE} ; done

SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTURL} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}

echo "Downloading the SystemPrep script file -- ${SYSTEMPREPMASTERSCRIPTURL}" &>> ${LOGFILE}
curl -O -s ${SYSTEMPREPMASTERSCRIPTURL} &>> ${LOGFILE}

echo "Running the SystemPrep script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
PARAMSTRING=$( IFS=$' '; echo "${PARAMS[*]}" )
sh ${SCRIPTFULLPATH} $PARAMSTRING &>> ${LOGFILE}

echo "Exiting SystemPrep script -- ${SCRIPTNAME}" &>> ${LOGFILE}
