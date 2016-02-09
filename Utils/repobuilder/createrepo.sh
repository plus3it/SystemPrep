#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "create_repo" -s 2> /dev/console) 2>&1

BUCKETNAME=${1:-systemprep-repo}  # What bucket contains the packages?

REPO_DIR="/root/${BUCKETNAME}"  # Where do we want to stage the repo?
ARCHIVE_DIR="${REPO_DIR}/archives"  # Where are we keeping zip archives?
PACKAGE_DIR="${REPO_DIR}/linux"  # Where are we staging the packages?
YUM_FILE_DIR="${PACKAGE_DIR}/yum.repos"  # Where do we want to save the yum repo files?
BUCKET_URL="s3://${BUCKETNAME}"  # What bucket contains the packages?
BASE_URL="https://s3.amazonaws.com/${BUCKETNAME}/linux"  # Common http path to the hosted packages

REPOS=(
    "AMZN"
    "CENTOS"
    "RHEL"
    "SALT_EL6"
    "SALT_EL7"
)

REPO_NAME_AMZN="${BUCKETNAME}-amzn"
REPO_BASEURL_AMZN="${BASE_URL}/amzn/latest/\$basearch/"
REPO_GPGKEY_AMZN="${BASE_URL}/amzn/latest/\$basearch/RPM-GPG-KEY-amazon-ga"

REPO_NAME_CENTOS="${BUCKETNAME}-centos"
REPO_BASEURL_CENTOS="${BASE_URL}/centos/\$releasever/\$basearch/"
REPO_GPGKEY_CENTOS="${BASE_URL}/centos/\$releasever/\$basearch/RPM-GPG-KEY-CentOS-\$releasever"

REPO_NAME_RHEL="${BUCKETNAME}-rhel"
REPO_BASEURL_RHEL="${BASE_URL}/rhel/\$releasever/\$basearch/"
REPO_GPGKEY_RHEL="${BASE_URL}/rhel/\$releasever/\$basearch/RPM-GPG-KEY-redhat-release"

REPO_NAME_SALT_EL6="${BUCKETNAME}-salt-el6"
REPO_BASEURL_SALT_EL6="${BASE_URL}/saltstack/salt/el6/\$basearch/"
REPO_GPGKEY_SALT_EL6="${BASE_URL}/saltstack/salt/el6/\$basearch/SALTSTACK-GPG-KEY.pub"

REPO_NAME_SALT_EL7="${BUCKETNAME}-salt-el7"
REPO_BASEURL_SALT_EL7="${BASE_URL}/saltstack/salt/el7/\$basearch/"
REPO_GPGKEY_SALT_EL7="${BASE_URL}/saltstack/salt/el7/\$basearch/SALTSTACK-GPG-KEY.pub"

BUILDER_DEPS=(
    "yum-utils"
    "createrepo"
)

PIP_INSTALLER="https://bootstrap.pypa.io/get-pip.py"

# Temporarily suppress rsyslog rate limiting
if [[ -e /etc/rsyslog.conf ]]
then
    echo "Temporarily disabling rsyslog rate limiting"
    RSYSLOGFLAG=1
    # Replace or append the $SystemLogRateLimitInterval parameter
    grep -q '^$SystemLogRateLimitInterval' /etc/rsyslog.conf && \
        sed -i.bak -e \
        's/^$SystemLogRateLimitInterval.*/$SystemLogRateLimitInterval 0/' \
        /etc/rsyslog.conf || \
        sed -i.bak "$ a\$SystemLogRateLimitInterval 0" /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi
# Temporarily suppress journald rate limiting
if [[ -e /etc/systemd/journald.conf ]]
then
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

# Make sure the certificates have been updated
yum -y upgrade ca-certificates

# Make sure the epel repo is not present
yum -y remove epel-release

# Manage distribution-specific dependencies
RELEASE=$(grep "release" /etc/system-release)
case "${RELEASE}" in
"Amazon"*)
    ;;
"CentOS"*6*)
    service ntpd start 2>&1 > /dev/null && echo "Started ntpd..." || echo "Failed to start ntpd..."
       ### ^^^Workaround for issue where localtime is misconfigured on CentOS6
    ;;
"CentOS"*7*)
    ;;
"Red Hat"*6*)
    ;;
"Red Hat"*7*)
    ;;
*)
    echo "Unsupported OS. Exiting"
    exit 1
    ;;
esac

# Install packages required to create the repo
yum -y install ${BUILDER_DEPS[@]}

# Install pip
curl ${PIP_INSTALLER} -o /tmp/get-pip.py
python /tmp/get-pip.py
hash pip 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Make sure pip is in path

# Upgrade setuptools
pip install --upgrade setuptools

# Install s3cmd
pip install --upgrade s3cmd
hash s3cmd 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Make sure s3cmd is in path

# Download the packages from the bucket
mkdir -p "${PACKAGE_DIR}" "${YUM_FILE_DIR}" "${ARCHIVE_DIR}"
s3cmd sync "${BUCKET_URL}/linux/" "${PACKAGE_DIR}/"
s3cmd sync "${BUCKET_URL}/archives/" "${ARCHIVE_DIR}/"

# Get a list of all directories containing a 'packages' directory
package_dirs=$(find ${PACKAGE_DIR} -name 'packages' -printf '%h\n' | sort -u)
# Create the repo metadata for each package_dir
for repo in ${package_dirs}; do
    createrepo -v --deltas --update "${repo}"
done

__print_repo_file() {
    # Function that prints out a yum repo file
    if [ $# -eq 3 ]; then
        name=$1
        baseurl=$2
        gpgkey=$3
    else
        printf "ERROR: __print_repo_file requires three arguments." 1>&2;
        exit 1
    fi
    printf "[${name}]\n"
    printf "name=${name}\n"
    printf "baseurl=${baseurl}\n"
    printf "gpgcheck=1\n"
    printf "gpgkey=${gpgkey}\n"
    printf "enabled=1\n"
    printf "skip_if_unavailable=1\n"
}

# Create the yum repo files
for repo in "${REPOS[@]}"; do
    repo_name="REPO_NAME_${repo}"
    repo_baseurl="REPO_BASEURL_${repo}"
    repo_gpgkey="REPO_GPGKEY_${repo}"
    __print_repo_file "${!repo_name}" "${!repo_baseurl}" "${!repo_gpgkey}" > "${YUM_FILE_DIR}/${!repo_name}.repo"
done

# Create a zip of the repo dir
cd ${REPO_DIR}
dir_basename="${PWD##*/}"
datestamp=$(date -u +"%Y%m%d")

# Create a delta zip archive, comparing new files to the last full zip archive
lastfull=$(find ${ARCHIVE_DIR} -type f | grep -i -e "${dir_basename}-linux-full-.*\.zip" | sort -r | head -1)
if [[ -n "${lastfull}" ]]
then
    zip -r "${lastfull}" . -DF --out "./archives/${dir_basename}-linux-delta-${datestamp}.zip" -x "archives/${dir_basename}-*.zip"
fi

# Now create a zip with all the current files
zip -r "./archives/${dir_basename}-linux-full-${datestamp}.zip" . -x "archives/${dir_basename}-*.zip"

# Sync the repo directory back to the S3 bucket
s3cmd sync "${PACKAGE_DIR}/" "${BUCKET_URL}/linux/" --delete-removed --delete-after
s3cmd sync "${ARCHIVE_DIR}/" "${BUCKET_URL}/archives/" --delete-removed --delete-after

# Restore prior rsyslog config
if [[ -n "${RSYSLOGFLAG}" ]]
then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 5
    echo "Re-storing previous rsyslog configuration"
    mv -f /etc/rsyslog.conf.bak /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi
# Restore prior journald config
if [[ -n "${JOURNALDFLAG}" ]]
then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 5
    echo "Re-storing previous journald configuration"
    mv -f /etc/systemd/journald.conf.bak /etc/systemd/journald.conf
    echo "Restarting systemd-journald..."
    systemctl restart systemd-journald.service
fi

echo "Finished creating the repo!"
