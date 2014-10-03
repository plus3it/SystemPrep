#!/usr/bin/env bash
set -ex

#User variables
SYSTEMPREPMASTERSCRIPTURL="https://systemprep.s3.amazonaws.com/MasterScripts/systemprep-linuxmaster.py"
PARAMS=( "SaltStates=Highstate" 
         "NoReboot=False" )

#System variables
SCRIPTNAME=$0
WORKINGDIR=/usr/tmp
LOGDIR=/var/log
TIMESTAMP=$(date -u +"%Y%m%d_%H%M_%S")
LOGFILE=${LOGDIR}/systemprep-log-${TIMESTAMP}.txt

if [[ ! -d "${LOGDIR}" ]] ; then mkdir ${LOGDIR} ; fi
if [[ ! -d "${WORKINGDIR}" ]] ; then mkdir ${WORKINGDIR} ; fi
cd ${WORKINGDIR}
echo "Entering SystemPrep script -- ${SCRIPTNAME}" &> ${LOGFILE}
echo "Writing SystemPrep Parameters to log file..." &>> ${LOGFILE}
for key in "${!SYSTEMPREPPARAMS[@]}"; do echo "   ${key} = ${SYSTEMPREPPARAMS["$key"]}" &>> ${LOGFILE} ; done

SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTURL} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}

echo "Downloading the SystemPrep master script -- ${SYSTEMPREPMASTERSCRIPTURL}" &>> ${LOGFILE}
curl -O -s ${SYSTEMPREPMASTERSCRIPTURL} &>> ${LOGFILE}

echo "Running the SystemPrep master script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
PARAMSTRING=$( IFS=$' '; echo "${PARAMS[*]}" )
sh ${SCRIPTFULLPATH} $PARAMSTRING &>> ${LOGFILE}

echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
rm -f ${SCRIPTFULLPATH} &>> ${LOGFILE}

echo "Exiting SystemPrep script -- ${SCRIPTNAME}" &>> ${LOGFILE}
