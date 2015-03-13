#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "systemprep-buildrepo" -s 2> /dev/console) 2>&1

BUILDERDEPS=(
    "epel-release"
    "yum-utils"
    "createrepo"
)

SALT_OSDEPS=( 
    "PyYAML"
    "audit-libs-python"
    "libcgroup"
    "libselinux-python"
    "libsemanage-python"
    "libyaml"
    "m2crypto"
    "pciutils"
    "policycoreutils-python"
    "python-babel"
    "python-backports"
    "python-backports-ssl_match_hostname"
    "python-chardet"
    "python-crypto"
    "python-jinja2"
    "python-ordereddict"
    "python-requests"
    "python-six"
    "python-urllib3"
    "setools-libs"
    "setools-libs-python"
)

SALT_EPELDEPS=(
    "openpgm"
    "python-msgpack"
    "python-zmq"
    "salt"
    "salt-master"
    "salt-minion"
    "sshpass"
    "zeromq3"
)

GPGKEY_EPEL="RPM-GPG-KEY-EPEL-[0-9]"
GPGKEY_CENTOS="RPM-GPG-KEY-CentOS-[0-9]"
GPGKEY_AMZN="RPM-GPG-KEY-amazon-ga"
GPGKEY_RHEL="RPM-GPG-KEY-redhat-release"

# Manage distribution-specific dependencies
RELEASE=$(grep "release" /etc/issue)
case "${RELEASE}" in
"Amazon"*)
    DIST="amzn"
    ;;
"CentOS"*)
    DIST="centos"
    ;;
"Red Hat"*6*)
    DIST="rhel"
    curl -O http://mirror.us.leaseweb.net/epel/6/i386/epel-release-6-8.noarch.rpm && \
    yum install epel-release-6-8.noarch.rpm -y
    ;;
"Red Hat"*7)
    DIST="rhel"
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
yum-config-manager --enable epel

# Establish variables
STAGING=$(echo ~/repo/staging)
ARCH="${HOSTTYPE}"
OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*')
OSREPO=$(echo ~/repo/${DIST}/${OSVER}/${ARCH})
OSPACKAGES="${OSREPO}/packages"
OSBUCKET="systemprep-repo/${DIST}/${OSVER}/${ARCH}/"
EPELVER=$(yum info epel-release | grep Version | awk -F ': ' '{print $2}')
EPELREPO=$(echo ~/repo/epel/${EPELVER}/${ARCH})
EPELPACKAGES="${EPELREPO}/packages"
EPELBUCKET="systemprep-repo/epel/${EPELVER}/${ARCH}/"

# Download packages to the staging directory
mkdir -p "${OSPACKAGES}" "${EPELPACKAGES}" "${STAGING}"
SALT_OSDEPS_STRING=$( IFS=$' '; echo "${SALT_OSDEPS[*]}" )
SALT_EPELDEPS_STRING=$( IFS=$' '; echo "${SALT_EPELDEPS[*]}" )
yumdownloader --resolve --destdir "${STAGING}" --archlist="${ARCH}" ${SALT_OSDEPS_STRING} ${SALT_EPELDEPS_STRING}

# Move packages to the epel repo directory
for package in ${SALT_EPELDEPS_STRING}; do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${EPELPACKAGES}"
done

# Move all other packages to the os repo directory
mv ${STAGING}/* "${OSPACKAGES}"

# Copy the GPG keys to the repo
GPGKEY="GPGKEY_${DIST^^}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${!GPGKEY}" | xargs -i cp {} "${OSREPO}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${GPGKEY_EPEL}" | xargs -i cp {} "${EPELREPO}"

# Create the repo metadata
createrepo -v --deltas "${OSREPO}"
createrepo -v --deltas "${EPELREPO}"

# Sync the repo to S3
yum -y install s3cmd
s3cmd sync ${OSREPO} s3://${OSBUCKET}
s3cmd sync ${EPELREPO} s3://${OSBUCKET}
