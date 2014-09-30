#!/usr/bin/env bash
set -ex

SYSTEMPREPMASTERSCRIPTURL="https://systemprep.s3.amazonaws.com/MasterScripts/systemprep-linuxmaster.sh"
declare -A SYSTEMPREPPARAMS=( ["SaltStates"]="Highstate" 
                              ["NoReboot"]="False" )
                              
WORKINGDIR=/var/tmp/systemprep
TIMESTAMP=$(date -u +"%Y%m%d_%H%M_%S")
LOGFILE=${WORKINGDIR}/systemprep-log-${TIMESTAMP}.txt

mkdir ${WORKINGDIR}
cd ${WORKINGDIR}
echo "Entering SystemPrep Bootstrap script..." > ${LOGFILE}
echo "Writing SystemPrep Parameters to log file..." >> ${LOGFILE}
for key in "${!SYSTEMPREPPARAMS[@]}"; do echo "   ${key} = ${SYSTEMPREPPARAMS["$key"]}" >> ${LOGFILE} ; done

SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTURL} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}

echo "Downloading the SystemPrep script file -- ${SYSTEMPREPMASTERSCRIPTURL}" >> ${LOGFILE}
curl -O -s ${SYSTEMPREPMASTERSCRIPTURL}

echo "Running the SystemPrep script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
sh ${SCRIPTFULLPATH}
