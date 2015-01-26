#!/usr/bin/env bash
set -ex

#User variables
SYSTEMPREPMASTERSCRIPTSOURCE="https://url/to/masterscript-linux.py"
SYSTEMPREPPARAMS=( "Param1=Value1"
                   "Param2=Value2"
                   "Param3=Value3"
                   "Param4=Value4" )

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

#Convert the parameter list to a string
#The string will be converted to a python dictionary by the master script
PARAMSTRING=$( IFS=$' '; echo "${SYSTEMPREPPARAMS[*]}" )
echo "Running the SystemPrep master script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
python ${SCRIPTFULLPATH} ${PARAMSTRING} &>> ${LOGFILE}

echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}" >> ${LOGFILE}
rm -f ${SCRIPTFULLPATH} &>> ${LOGFILE}

echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}" &>> ${LOGFILE}
