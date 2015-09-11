#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "create_yum_repo_definitions" -s 2> /dev/console) 2>&1

BUCKETNAME=${1:-systemprep-repo}  # What bucket contains the packages?
S3_BASE_URL=${2:-https://s3.amazonaws.com}  # What's the url to s3?
PIP_INSTALLER=${3:-https://bootstrap.pypa.io/get-pip.py}  # URL to the pip installer
PIP_INDEX_URL=${4:-https://pypi.python.org/simple}  # pip --index-url parameter


REPO_DIR="/root/${BUCKETNAME}"  # Where do we want to stage the repo?
PACKAGE_DIR="${REPO_DIR}/linux"  # Where are we staging the packages?
YUM_FILE_DIR="${PACKAGE_DIR}/yum.repos"  # Where do we want to save the yum repo files?
BUCKET_URL="s3://${BUCKETNAME}"  # What bucket contains the packages?
BASE_URL="${S3_BASE_URL}/${BUCKETNAME}/linux"  # Common http path to the hosted packages

REPOS=(
    "AMZN"
    "CENTOS"
    "RHEL"
    "EPEL6"
    "EPEL7"
    "SALT_EPEL6"
    "SALT_EPEL7"
)

REPO_NAME_AMZN="${BUCKETNAME}-amzn-packages"
REPO_BASEURL_AMZN="${BASE_URL}/amzn/latest/\$basearch/"
REPO_GPGKEY_AMZN="${BASE_URL}/amzn/latest/\$basearch/RPM-GPG-KEY-amazon-ga"

REPO_NAME_CENTOS="${BUCKETNAME}-centos-packages"
REPO_BASEURL_CENTOS="${BASE_URL}/centos/\$releasever/\$basearch/"
REPO_GPGKEY_CENTOS="${BASE_URL}/centos/\$releasever/\$basearch/RPM-GPG-KEY-CentOS-\$releasever"

REPO_NAME_RHEL="${BUCKETNAME}-rhel-packages"
REPO_BASEURL_RHEL="${BASE_URL}/rhel/\$releasever/\$basearch/"
REPO_GPGKEY_RHEL="${BASE_URL}/rhel/\$releasever/\$basearch/RPM-GPG-KEY-redhat-release"

REPO_NAME_EPEL6="${BUCKETNAME}-epel6-packages"
REPO_BASEURL_EPEL6="${BASE_URL}/epel/6/\$basearch/"
REPO_GPGKEY_EPEL6="${BASE_URL}/epel/6/\$basearch/RPM-GPG-KEY-EPEL-6"

REPO_NAME_EPEL7="${BUCKETNAME}-epel7-packages"
REPO_BASEURL_EPEL7="${BASE_URL}/epel/7/\$basearch/"
REPO_GPGKEY_EPEL7="${BASE_URL}/epel/7/\$basearch/RPM-GPG-KEY-EPEL-7"

REPO_NAME_SALT_EPEL6="${BUCKETNAME}-salt-epel6-packages"
REPO_BASEURL_SALT_EPEL6="${BASE_URL}/saltstack/salt/epel-6/\$basearch/"
REPO_GPGKEY_SALT_EPEL6="${BASE_URL}/saltstack/salt/epel-6/\$basearch/SALTSTACK-GPG-KEY.pub"

REPO_NAME_SALT_EPEL7="${BUCKETNAME}-salt-epel7-packages"
REPO_BASEURL_SALT_EPEL7="${BASE_URL}/saltstack/salt/epel-7/\$basearch/"
REPO_GPGKEY_SALT_EPEL7="${BASE_URL}/saltstack/salt/epel-7/\$basearch/SALTSTACK-GPG-KEY.pub"



# Manage distribution-specific dependencies
RELEASE=$(grep "release" /etc/system-release)
case "${RELEASE}" in
"Amazon"*)
    ;;
"CentOS"*"6."*)
    service ntpd start 2>&1 > /dev/null && echo "Started ntpd..." || echo "Failed to start ntpd..."
       ### ^^^Workaround for issue where localtime is misconfigured on CentOS6
    ;;
"CentOS"*"7."*)
    ;;
"Red Hat"*"6."*)
    ;;
"Red Hat"*"7."*)
    ;;
*)
    echo "Unsupported OS. Exiting"
    exit 1
    ;;
esac

# Install pip
curl ${PIP_INSTALLER} -o /tmp/get-pip.py
python /tmp/get-pip.py
hash pip 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Make sure pip is in path

# Upgrade setuptools
pip install --upgrade setuptools

# Install s3cmd
pip install s3cmd --upgrade --allow-all-external --index-url ${PIP_INDEX_URL}
hash s3cmd 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Make sure s3cmd is in path

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

# Create directories
mkdir -p "${YUM_FILE_DIR}"

# Create the yum repo files
for repo in "${REPOS[@]}"; do
    repo_name="REPO_NAME_${repo}"
    repo_baseurl="REPO_BASEURL_${repo}"
    repo_gpgkey="REPO_GPGKEY_${repo}"
    __print_repo_file "${!repo_name}" "${!repo_baseurl}" "${!repo_gpgkey}" > "${YUM_FILE_DIR}/${!repo_name}.repo"
done

# Sync the repo directory back to the S3 bucket
s3cmd sync "${REPO_DIR}/" "${BUCKET_URL}"

echo "Finished creating the yum repo definitions!"
