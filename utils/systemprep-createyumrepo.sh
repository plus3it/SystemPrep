#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "systemprep-createyumfiles" -s 2> /dev/console) 2>&1

REPO_DIR="/root/systemprep-repo"  # Where do we want to stage the repo?
YUM_FILE_DIR="${REPO_DIR}/yum.repos"  # Where do we want to save the yum repo files?
BUCKET_URL="s3://systemprep-repo"  # What bucket contains the packages?
BASE_URL="https://s3.amazonaws.com/systemprep-repo"  # Common http path to the hosted packages

REPOS=(
    "AMZN"
    "CENTOS"
    "RHEL"
    "EPEL6"
    "EPEL7"
    "SALT_EPEL6"
    "SALT_EPEL7"
    "ZMQ_EPEL6"
    "ZMQ_EPEL7"
)

REPO_NAME_AMZN="systemprep-amzn-packages"
REPO_BASEURL_AMZN="${BASE_URL}/amzn/\$releasever/\$basearch/"
REPO_GPGKEY_AMZN="${BASE_URL}/amzn/\$releasever/\$basearch/RPM-GPG-KEY-amazon-ga"

REPO_NAME_CENTOS="systemprep-centos-packages"
REPO_BASEURL_CENTOS="${BASE_URL}/centos/\$releasever/\$basearch/"
REPO_GPGKEY_CENTOS="${BASE_URL}/centos/\$releasever/\$basearch/RPM-GPG-KEY-CentOS-\$releasever"

REPO_NAME_RHEL="systemprep-rhel-packages"
REPO_BASEURL_RHEL="${BASE_URL}/rhel/\$releasever/\$basearch/"
REPO_GPGKEY_RHEL="${BASE_URL}/rhel/\$releasever/\$basearch/RPM-GPG-KEY-redhat-release"

REPO_NAME_EPEL6="systemprep-epel6-packages"
REPO_BASEURL_EPEL6="${BASE_URL}/epel/6/\$basearch/"
REPO_GPGKEY_EPEL6="${BASE_URL}/epel/6/\$basearch/RPM-GPG-KEY-EPEL-6"

REPO_NAME_EPEL7="systemprep-epel7-packages"
REPO_BASEURL_EPEL7="${BASE_URL}/epel/7/\$basearch/"
REPO_GPGKEY_EPEL7="${BASE_URL}/epel/7/\$basearch/RPM-GPG-KEY-EPEL-7"

REPO_NAME_SALT_EPEL6="systemprep-salt-epel6-packages"
REPO_BASEURL_SALT_EPEL6="${BASE_URL}/saltstack/salt/epel-6/\$basearch/"
REPO_GPGKEY_SALT_EPEL6="${BASE_URL}/saltstack/salt/epel-6/\$basearch/salt-gpgkey.gpg"

REPO_NAME_SALT_EPEL7="systemprep-salt-epel7-packages"
REPO_BASEURL_SALT_EPEL7="${BASE_URL}/saltstack/salt/epel-7/\$basearch/"
REPO_GPGKEY_SALT_EPEL7="${BASE_URL}/saltstack/salt/epel-7/\$basearch/salt-gpgkey.gpg"

REPO_NAME_ZMQ_EPEL6="systemprep-zmq-epel6-packages"
REPO_BASEURL_ZMQ_EPEL6="${BASE_URL}/saltstack/zmq/epel-6/\$basearch/"
REPO_GPGKEY_ZMQ_EPEL6="${BASE_URL}/saltstack/zmq/epel-6/\$basearch/zmq-gpgkey.gpg"

REPO_NAME_ZMQ_EPEL7="systemprep-zmq-epel7-packages"
REPO_BASEURL_ZMQ_EPEL7="${BASE_URL}/saltstack/zmq/epel-7/\$basearch/"
REPO_GPGKEY_ZMQ_EPEL7="${BASE_URL}/saltstack/zmq/epel-7/\$basearch/zmq-gpgkey.gpg"

BUILDERDEPS=(
    "epel-release"
    "yum-utils"
    "createrepo"
)

# Manage distribution-specific dependencies
if [[ -e /etc/redhat-release ]]; then
    RELEASE=$(grep "release" /etc/redhat-release)
elif [[ -e /etc/system-release ]]; then
    RELEASE=$(grep "release" /etc/system-release)
else
    echo "Don't know how to determine the 'release' string for this OS!"
    exit 1
fi
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
    curl -O http://mirror.us.leaseweb.net/epel/6/i386/epel-release-6-8.noarch.rpm && \
    yum install epel-release-6-8.noarch.rpm -y
    ;;
"Red Hat"*7*)
    curl -O http://mirror.sfo12.us.leaseweb.net/epel/7/x86_64/e/epel-release-7-5.noarch.rpm && \
    yum install epel-release-7-5.noarch.rpm -y
    ;;
*)
    echo "Unsupported OS. Exiting"
    exit 1
    ;;
esac

# Install packages required to create the repo
BUILDERDEPS_STRING=$( IFS=$' '; echo "${BUILDERDEPS[*]}" )
yum -y install ${BUILDERDEPS_STRING}

# Install s3cmd
yum-config-manager --enable epel
yum -y install python-pip  # Couldn't install python-pip with the builderdeps because it's in epel
pip install --upgrade s3cmd
hash s3cmd 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Modify PATH for Amazon Linux 2015.03

# Download the packages from the bucket
mkdir -p "${REPO_DIR}" "${YUM_FILE_DIR}"
s3cmd sync "${BUCKET_URL}" "${REPO_DIR}"

# Get a list of all directories containing a 'packages' directory
package_dirs=$(find ${REPO_DIR} -name 'packages' -printf '%h\n' | sort -u)
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
for f in "${dir_basename}-full-*.zip"; do  # There should only ever be one matching file
    # Create a delta zip with just the changes
    zip -r "${f}" . -DF --out "${dir_basename}-delta-${datestamp}.zip"
    rm -f "${f}"
    break
done
# Now create a zip with all the current files
zip -r "${dir_basename}-full-${datestamp}.zip" .

# Sync the repo directory back to the S3 bucket
s3cmd sync "${REPO_DIR}/" "${BUCKET_URL}" --delete-removed

echo "Finished creating the repo!"
