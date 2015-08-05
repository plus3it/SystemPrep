#!/usr/bin/env bash
set -e

#User variables
SOURCEISS3BUCKET="True"
AWSREGION="us-east-1"
AWSCLI_URL="https://s3.amazonaws.com/aws-cli/awscli-bundle.zip"
ROOT_CERT_URL=""
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

# Install root certs, if the root cert url is provided
if [[ -n "${ROOT_CERT_URL}" ]]; then

    #######################################################
    # Are we EL-compatible and do we have 6.5+ behaviour?
    #######################################################
    GetMode() {
        UPDATETRUST="/usr/bin/update-ca-trust"
        CERTUTIL="/usr/bin/certutil"
        if [ -x ${UPDATETRUST} ]
        then
            echo "6.5"
        elif [ -x ${CERTUTIL} ]
        then
            echo "6.0"
        else
            echo "Cannot determine CA update-method. Aborting."
            exit 1
        fi
    }

    #########################################################
    # Try to fetch all CA .cer files from our root_cert_url
    #########################################################
    FetchCAs() {

        if [ $# -ne 2 ]; then
            echo "FetchCAs requires two parameters."
            echo "  \$1, 'url', is a url hosting the root CA certificates."
            echo "  \$2, 'cert_dir', is a directory in which to save the certificates."
            exit 1
        fi

        URL="${1}"
        FETCH_CERT_DIR="${2}"
        WGET="/usr/bin/wget"

        # Create a working directory
        if [ -d "${FETCH_CERT_DIR}" ]
        then
            echo "'${FETCH_CERT_DIR}' already exists. Recreating for safety."
            mv "${FETCH_CERT_DIR}" "${FETCH_CERT_DIR}".bak || \
            ( echo "Couldn't move '${FETCH_CERT_DIR}'. Aborting..." && exit 1 )
        fi

        install -d -m 0700 -o root -g root "${FETCH_CERT_DIR}" || \
        ( echo "Could not create '${FETCH_CERT_DIR}'. Aborting..." && exit 1 )

        # Make sure wget is available
        if [ ! -x ${WGET} ]
        then
            echo "The wget utility not found. Attempting to install..."
            yum -y install wget || \
            ( echo "Could not install 'wget', which is required to download the certs. Aborting..." && exit 1 )
        fi

        echo "Attempting to download the root CA certs..."
        ${WGET} -r -l1 -nd -np -A.cer -P "${FETCH_CERT_DIR}" --quiet $URL || \
        ( echo "Could not download certs via 'wget'. Check the url. Quitting..." && \
          exit 1 )
    }

    ######################################
    # Update CA Trust
    ######################################
    UpdateTrust() {

        if [ $# -ne 2 ]; then
            echo "UpdateTrust requires two parameters."
            echo "  \$1, 'mode', is either '6.0' or '6.5', as determined by the 'GetMode' function."
            echo "  \$2, 'cert_dir', is a directory that contains the root certificates."
            exit 1
        fi

        MODE="${1}"
        UPDATE_CERT_DIR="${2}"

        if [[ "6.5" == "${MODE}" ]]; then
            # Make sure the cert dir exists
            cert_dir="/etc/pki/ca-trust/source/anchors"
            install -d -m 0755 -o root -g root "${cert_dir}"

            echo "Copying certs to $cert_dir..."
            (cd "${UPDATE_CERT_DIR}" ; find . -print | cpio -vpd "${cert_dir}" )

            echo "Enabling 'update-ca-trust'..."
            update-ca-trust force-enable

            echo "Extracting root certificates..."
            update-ca-trust extract && echo "Certs updated successfully." || \
            ( echo "ERROR: Failed to update certs." && exit 1 )
        elif [[ "6.0" == "${MODE}" ]]; then
            CADIR="/etc/pki/IC-CAs"
            if [ ! -d ${CADIR} ]
            then
                install -d -m 0755 ${CADIR}
            fi

            echo "Copying certs to ${CADIR}..."
            ( cd "${UPDATE_CERT_DIR}" ; find . -print | cpio -vpd "${CADIR}" )

            for ADDCER in $(find ${CADIR} -type f -name "*.cer" -o -name "*.CER")
            do
                echo "Adding \"${ADDCER}\" to system CA trust-list"
                ${CERTUTIL} -A -t u,u,u -d . -i "${ADDCER}" || \
                ( echo "ERROR: Failed to update certs." && exit 1 )
            done
        else
            echo "Unknown 'mode'. 'mode' must be '6.5' or '6.0'."
            exit 1
        fi
    }

    FetchCAs "${ROOT_CERT_URL}" "${WORKINGDIR}/certs"
    UpdateTrust "$(GetMode)" "${WORKINGDIR}/certs"

    # Configure the ENV so the awscli sees the updated certs
    export AWS_CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt
fi


# Install the aws cli, if a url to the install bundle is provided
AWS="/usr/local/bin/aws"
if [[ -n "${AWSCLI_URL}" ]]; then
    AWSCLI_FILENAME=$(echo ${AWSCLI_URL} | awk -F'/' '{ print ( $(NF) ) }')
    AWSCLI_FULLPATH=${WORKINGDIR}/${AWSCLI_FILENAME}
    cd ${WORKINGDIR}
    echo "Downloading aws cli -- ${AWSCLI_URL}"
    curl -L -O -s -S ${AWSCLI_URL} || \
        wget --quiet ${AWSCLI_URL} || \
            ( echo "Could not download file via 'curl' or 'wget'. Check the url and whether at least one of them is in the path. Quitting..." && exit 1 )
    hash unzip 2> /dev/null || \
        yum -y install unzip || \
            ( echo "Could not install unzip, which is required to install the awscli. Quitting..." && exit 1 )
    echo "Unzipping aws cli -- ${AWSCLI_FULLPATH}"
    unzip $AWSCLI_FULLPATH || ( echo "Could not unzip file. Quitting..." && exit 1 )
    echo "Installing aws cli -- ${WORKINGDIR}/awscli-bundle/install"
    ${WORKINGDIR}/awscli-bundle/install -i /opt/awscli -b $AWS || \
        ( echo "Could not install awscli. Quitting..." && exit 1 )
fi

# Download the master script
SCRIPTFILENAME=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print ( $(NF) ) }')
SCRIPTFULLPATH=${WORKINGDIR}/${SCRIPTFILENAME}
if [[ "true" = ${SOURCEISS3BUCKET,,} ]]; then
    echo "Downloading master script from S3 bucket using AWS Tools -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
    BUCKET=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'.' '{ print substr($1,9)}' OFS="/")
    KEY=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{$1=$2=$3=""; print substr($0,4)}' OFS="/")
    $AWS s3 cp s3://${BUCKET}/${KEY} ${SCRIPTFULLPATH} --region ${AWSREGION} || \
        ( BUCKET=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{ print $4 }' OFS="/") ; \
          KEY=$(echo ${SYSTEMPREPMASTERSCRIPTSOURCE} | awk -F'/' '{$1=$2=$3=$4=""; print substr($0,5)}' OFS="/") ; \
          $AWS s3 cp s3://${BUCKET}/${KEY} ${SCRIPTFULLPATH} --region ${AWSREGION} ) || \
              ( echo "Could not download file using AWS Tools. Check the url, and the instance role. Quitting..." && exit 1 )
else
    echo "Downloading master script from web host -- ${SYSTEMPREPMASTERSCRIPTSOURCE}"
    curl -L -O -s -S ${SYSTEMPREPMASTERSCRIPTSOURCE} || \
        wget --quiet ${SYSTEMPREPMASTERSCRIPTSOURCE} || \
            ( echo "Could not download file via 'curl' or 'wget'. Check the url and whether at least one of them is in the path. Quitting..." && exit 1 )
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
python ${SCRIPTFULLPATH} ${PARAMSTRING} || \
    error_result=$?  # Error, capture the exit code

# Restore prior rsyslog config
if [[ -n "${RSYSLOGFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 50
    echo "Re-storing previous rsyslog configuration"
    mv -f /etc/rsyslog.conf.bak /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi
# Restore prior journald config
if [[ -n "${JOURNALDFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 50
    echo "Re-storing previous journald configuration"
    mv -f /etc/systemd/journald.conf.bak /etc/systemd/journald.conf
    echo "Restarting systemd-journald..."
    systemctl restart systemd-journald.service
fi

# Report success or failure
if [[ -n $error_result ]]; then
    echo "ERROR: There was an error executing the SystemPrep Master script!"
    echo "Check the log file at: ${LOGLINK}"
    echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}"
    exit $error_result
else
    echo "SUCCESS: SystemPrep Master script completed successfully!"
    # Cleanup
    echo "Deleting the SystemPrep master script -- ${SCRIPTFULLPATH}"
    rm -f ${SCRIPTFULLPATH}
    echo "Exiting SystemPrep bootstrap script -- ${SCRIPTNAME}"
    exit 0
fi
