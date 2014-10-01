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

#declare -A SCRIPTSTOEXECUTE
SCRIPTSTOEXECUTE=( "https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/SystemPrep-LinuxSaltInstall.sh" )
SCRIPT0PARAMETERS=( "SALTWORKINGDIR=${WORKINGDIR}/systemcontent/linux/salt"
                    "SALTCONTENTURL=https://systemprep.s3.amazonaws.com/SystemContent/Linux/Salt/salt-content.zip"
                    "FORMULASTOINCLUDE=( 'https://salt-formulas.s3.amazonaws.com/ash-windows-formula-latest.zip' )" 
                    "FORMULATERMINATIONSTRING=( '-latest' )" 
                    "SALTSTATES=Highstate" )
                                        
                                        #Array of hashtables (key-value dictionaries). Each hashtable has two keys, ScriptUrl and Parameters. 


if [[ ! -d "${WORKINGDIR}" ]] ; then mkdir ${WORKINGDIR} ; fi

echo "${SCRIPTSTART}"
echo "Entering script -- ${SCRIPTNAME}"
echo "Printing parameters..."
for PARAM in "${@}" ; do echo "   ${PARAM}" ; ${!PARAM} ; done
echo "SaltStates = ${SaltStates}"
echo "NoReboot = ${NoReboot}"

if [[ -e ${READYFILE} ]] ; then rm -f ${READYFILE} ; fi

cd ${WORKINGDIR}
index=0
for SCRIPT in ${SCRIPTSTOEXECUTE} ; do
    curl -O -s ${SCRIPT}
    SCRIPTFILENAME=$(echo ${SCRIPT} | awk -F'/' '{ print ( $(NF) ) }')
    SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPT}
    PARAMSTRING=$( IFS=$' '; echo "${SCRIPT$(index)PARAMETERS[*]}" )
    sh ./${SCRIPTFILENAME} $PARAMSTRING
    index=(( $index + 1 ))
done
uyyhu 
/bin/date > ${READYFILE}

echo "Exiting SystemPrep script -- ${SCRIPTNAME}"
echo "${SCRIPTEND}"
