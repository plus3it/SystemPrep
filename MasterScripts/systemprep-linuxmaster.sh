#!/usr/bin/env bash 
set -ex

####################################################################################
#Master Script that calls subscripts to be deployed to new Linux VMs
####################################################################################

#System variables
SCRIPTNAME=$0
WORKINGDIR=/usr/tmp/systemprep
READYFILE=/var/run/system-is-ready
SCRIPTSTART="++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
SCRIPTEND="--------------------------------------------------------------------------------"

if [[ ! -d "${WORKINGDIR}" ]] ; then mkdir ${WORKINGDIR} ; fi
cd ${WORKINGDIR}

echo "${SCRIPTSTART}"
echo "Entering script -- ${SCRIPTNAME}"
echo "Writing Parameters to log file..."
for PARAM in "${@}" ; do echo "   ${PARAM}" ; ${!PARAM} ; done

if [[ -e ${READYFILE} ]] ; then rm -f ${READYFILE} ; fi

/bin/date > ${READYFILE}

echo "Exiting SystemPrep script -- ${SCRIPTNAME}"
echo "${SCRIPTEND}"
