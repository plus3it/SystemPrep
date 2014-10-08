#!/usr/bin/env bash
set -ex

#User variables
SYSTEMPREPMASTERSCRIPTSOURCE="https://systemprep.s3.amazonaws.com/MasterScripts/systemprep-linuxmaster.py"
SYSTEMPREPPARAMS=( "SaltStates=Highstate"
                   "NoReboot=False" )

#System variables
SCRIPTNAME=$0
WORKINGDIR=/usr/tmp
LOGDIR=/var/log
TIMESTAMP=$(date -u +"%Y%m%d_%H%M_%S")
LOGFILE=${LOGDIR}/systemprep-${TIMESTAMP}.log

if [[ ! -d "${LOGDIR}" ]] ; then mkdir ${LOGDIR} ; fi
if [[ ! -d "${WORKINGDIR}" ]] ; then mkdir ${WORKINGDIR} ; fi
cd ${WORKINGDIR}
echo "Entering SystemPrep script -- ${SCRIPTNAME}" &> ${LOGFILE}
echo "Writing SystemPrep Parameters to log file..." &>> ${LOGFILE}
for param in "${SYSTEMPREPPARAMS[@]}"; do echo "   ${param}" &>> ${LOGFILE} ; done

SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}

echo "Downloading the SystemPrep master script -- ${SYSTEMPREPMASTERSCRIPTSOURCE}" &>> ${LOGFILE}
curl -O -s ${SYSTEMPREPMASTERSCRIPTSOURCE} &>> ${LOGFILE}

echo "Running the SystemPrep master script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
PARAMSTRING=$( IFS=$' '; echo "${SYSTEMPREPPARAMS[*]}" )
python ${SCRIPTFULLPATH} ${PARAMSTRING} &>> ${LOGFILE}

echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
rm -f ${SCRIPTFULLPATH} &>> ${LOGFILE}

echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}" &>> ${LOGFILE}
