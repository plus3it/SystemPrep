#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "systemprep-stagepackages" -s 2> /dev/console) 2>&1

BUILDERDEPS=(
    "epel-release"
    "yum-utils"
    "createrepo"
    "python-pip"
)

SALT_OSDEPS=( 
    "PyYAML"
    "audit-libs-python"
    "hwdata"
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
    "python-markupsafe"
    "python-ordereddict"
    "python-requests"
    "python-six"
    "python-urllib3"
    "setools-libs"
    "setools-libs-python"
    "systemd-python"
    "yum-utils"
)

SALT_EPELDEPS=(
    "python-msgpack"
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
GPGKEY_COPRZMQ="http://copr-be.cloud.fedoraproject.org/results/saltstack/zeromq4/pubkey.gpg"
GPGKEY_COPRSALT="https://copr-be.cloud.fedoraproject.org/results/saltstack/salt/pubkey.gpg"

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
    systemctl restart  systemd-journald.service
fi

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
    yum -y install epel-release-6-8.noarch.rpm
    ;;
"Red Hat"*7*)
    DIST="rhel"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=7'
    curl -O http://mirror.sfo12.us.leaseweb.net/epel/7/x86_64/e/epel-release-7-5.noarch.rpm && \
    yum -y install epel-release-7-5.noarch.rpm
    ;;
*)
    echo "Unsupported OS. Exiting"
    exit 1
    ;;
esac

# Install packages required to create the repo
BUILDERDEPS_STRING=$( IFS=$' '; echo "${BUILDERDEPS[*]}" )
yum -y install ${BUILDERDEPS_STRING}

# Establish variables
STAGING=$(echo ~/repo/staging)
ARCH="${HOSTTYPE}"
OSREPO=$(echo ~/repo/${DIST}/${OSVER}/${ARCH})
OSPACKAGES="${OSREPO}/packages"
OSBUCKET="systemprep-repo/${DIST}/${OSVER}/"
EPELVER=$(rpm -qa |grep epel-release | cut -d'-' -f3)
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
for repo in "${COPR_REPOS[@]}"; do
    curl -O $repo
done

# Enable repos
yum-config-manager --enable "*"
for repo in "testing" "source" "debug" "contrib" "C6" "media" "fasttrack" "preview" "nosrc"; do
    yum-config-manager --disable "*${repo}*"
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

# Sync the packages to S3
pip install --upgrade s3cmd
hash s3cmd 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Modify PATH for Amazon Linux 2015.03
s3cmd sync ${OSREPO} s3://${OSBUCKET}
s3cmd sync ${EPELREPO} s3://${EPELBUCKET}
s3cmd sync ${COPRZMQREPO} s3://${COPRZMQBUCKET}
s3cmd sync ${COPRSALTREPO} s3://${COPRSALTBUCKET}

# Restore prior rsyslog config
if [[ -n "${RSYSLOGFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 5
    echo "Re-storing previous rsyslog configuration"
    mv -f /etc/rsyslog.conf.bak /etc/rsyslog.conf
    echo "Restarting rsyslog..."
    service rsyslog restart
fi
# Restore prior journald config
if [[ -n "${JOURNALDFLAG}" ]]; then
    # Sleep to let the logger catch up with the output of the python script...
    sleep 5
    echo "Re-storing previous journald configuration"
    mv -f /etc/systemd/journald.conf.bak /etc/systemd/journald.conf
    echo "Restarting systemd-journald..."
    systemctl restart  systemd-journald.service
fi

echo "Finished staging the packages!"
