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
    # "pciutils"
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
    "yum-utils"
)

SALT_EPELDEPS=(
    # "openpgm"
    "python-msgpack"
    # "sshpass"
)

SALT_COPRZMQ_DEPS=(
    "python-zmq"
    "zeromq-4.0.4"
)

SALT_COPRSALT_DEPS=(
    "salt"
    "salt-master"
    "salt-minion"
)

GPGKEY_EPEL="RPM-GPG-KEY-EPEL-[0-9]"
GPGKEY_CENTOS="RPM-GPG-KEY-CentOS-[0-9]"
GPGKEY_AMZN="RPM-GPG-KEY-amazon-ga"
GPGKEY_RHEL="RPM-GPG-KEY-redhat-release"
GPGKEY_COPRZMQ="https://copr-be.cloud.fedoraproject.org/results/saltstack/salt/pubkey.gpg"
GPGKEY_COPRSALT="http://copr-be.cloud.fedoraproject.org/results/saltstack/zeromq4/pubkey.gpg"

# Manage distribution-specific dependencies
RELEASE=$(grep "release" /etc/issue)
case "${RELEASE}" in
"Amazon"*)
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*') #e.g. 'OSVER=2014.7'
    DIST="amzn"
    ;;
"CentOS"*)
    DIST="centos"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=6'
    ;;
"Red Hat"*6*)
    DIST="rhel"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=6'
    curl -O http://mirror.us.leaseweb.net/epel/6/i386/epel-release-6-8.noarch.rpm && \
    yum install epel-release-6-8.noarch.rpm -y
    ;;
"Red Hat"*7)
    DIST="rhel"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=7'
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
OSREPO=$(echo ~/repo/${DIST}/${OSVER}/${ARCH})
OSPACKAGES="${OSREPO}/packages"
OSBUCKET="systemprep-repo/${DIST}/${OSVER}/"
EPELVER=$(yum info epel-release | grep Version | awk -F ': ' '{print $2}')
EPELREPO=$(echo ~/repo/epel/${EPELVER}/${ARCH})
EPELPACKAGES="${EPELREPO}/packages"
EPELBUCKET="systemprep-repo/epel/${EPELVER}/"
COPRZMQREPO=$(echo ~/repo/saltstack/zeromq/epel-${EPELVER}/${ARCH})
COPRZMQPACKAGES="${COPRZMQREPO}/packages"
COPRZMQBUCKET="systemprep-repo/saltstack/zeromq/epel-${EPELVER}/"
COPRSALTREPO=$(echo ~/repo/saltstack/salt/epel-${EPELVER}/${ARCH})
COPRSALTPACKAGES="${COPRSALTREPO}/packages"
COPRSALTBUCKET="systemprep-repo/saltstack/salt/epel-${EPELVER}/"

#Define COPR repos with the latest salt packages and dependencies that aren't in epel
COPR_REPOS=(
    http://copr.fedoraproject.org/coprs/saltstack/salt/repo/epel-${EPELVER}/saltstack-salt-epel-${EPELVER}.repo
    http://copr.fedoraproject.org/coprs/saltstack/zeromq4/repo/epel-${EPELVER}/saltstack-zeromq4-epel-${EPELVER}.repo
)

#Download required repo files
cd /etc/yum.repos.d
for repo in "${COPR_REPOS[*]}"; do
    curl -O $repo
done

# Download packages to the staging directory
mkdir -p "${OSPACKAGES}" "${EPELPACKAGES}" "${STAGING}" "${COPRZMQPACKAGES}" "${COPRSALTPACKAGES}"
SALT_OSDEPS_STRING=$( IFS=$' '; echo "${SALT_OSDEPS[*]}" )
SALT_EPELDEPS_STRING=$( IFS=$' '; echo "${SALT_EPELDEPS[*]}" )
SALT_COPRZMQ_DEPS_STRING=$( IFS=$' '; echo "${SALT_COPRZMQ_DEPS[*]}" )
SALT_COPRSALT_DEPS_STRING=$( IFS=$' '; echo "${SALT_COPRSALT_DEPS[*]}" )
yumdownloader --resolve --destdir "${STAGING}" --archlist="${ARCH}" ${SALT_OSDEPS_STRING} ${SALT_EPELDEPS_STRING} ${SALT_COPRZMQ_DEPS_STRING} ${SALT_COPRSALT_DEPS_STRING}

# Move packages to the epel repo directory
for package in ${SALT_EPELDEPS_STRING}; do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${EPELPACKAGES}"
done

# Move packages to the coprzmq repo directory
for package in ${SALT_COPRZMQ_DEPS_STRING}; do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${COPRZMQPACKAGES}"
done

# Move packages to the coprsalt repo directory
for package in ${SALT_COPRSALT_DEPS_STRING}; do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${COPRSALTPACKAGES}"
done

# Move all other packages to the os repo directory
mv ${STAGING}/* "${OSPACKAGES}"

# Copy the GPG keys to the repo
GPGKEY="GPGKEY_${DIST^^}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${!GPGKEY}" | xargs -i cp {} "${OSREPO}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${GPGKEY_EPEL}" | xargs -i cp {} "${EPELREPO}"
curl -o "${COPRZMQREPO}/zeromq-gpgkey.gpg" "${GPGKEY_COPRZMQ}"
curl -o "${COPRSALTREPO}/salt-gpgkey.gpg" "${GPGKEY_COPRSALT}"

# Create the repo metadata
for repo in "${OSREPO}" "${EPELREPO}" "${COPRZMQREPO}" "${COPRSALTREPO}"; do
    createrepo -v --deltas "${repo}"
done

# Sync the repo to S3
yum -y install s3cmd
s3cmd sync ${OSREPO} s3://${OSBUCKET}
s3cmd sync ${EPELREPO} s3://${EPELBUCKET}
s3cmd sync ${COPRZMQREPO} s3://${COPRZMQBUCKET}
s3cmd sync ${COPRSALTREPO} s3://${COPRSALTBUCKET}

echo "Finished creating the repo!"
