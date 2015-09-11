#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "stage_rpm_packages" -s 2> /dev/console) 2>&1

BUCKETNAME=${1:-systemprep-repo}

BUILDERDEPS=(
    "epel-release"
    "yum-utils"
    "createrepo"
)

SALT_OSDEPS=( 
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
    "python-chardet"
    "python-markupsafe"
    "python-requests"
    "python-six"
    "python-urllib3"
    "selinux-policy-targeted"
    "setools-libs"
    "setools-libs-python"
    "unzip"
    "yum-utils"
)

SALT_EPELDEPS=(
    "python-enum34"
#    "python-importlib"
    "python-libcloud"
    "python-msgpack"
    "libsodium"
)

SALT_REPO_DEPS=(
    "PyYAML-3.11"
#    "python-ioflo"
    "python-libnacl"
#    "python-raet"
    "python-timelib"
    "python-tornado-4.2.1"
    "python-zmq"
    "salt"
    "salt-api"
    "salt-cloud"
    "salt-master"
    "salt-minion"
    "salt-ssh"
    "salt-syndic"
)

GPGKEY_EPEL="RPM-GPG-KEY-EPEL-[0-9]"
GPGKEY_CENTOS="RPM-GPG-KEY-CentOS-[0-9]"
GPGKEY_AMZN="RPM-GPG-KEY-amazon-ga"
GPGKEY_RHEL="RPM-GPG-KEY-redhat-release"

EPEL6_RPM="https://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm"
EPEL7_RPM="https://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-5.noarch.rpm"
PIP_INSTALLER="https://bootstrap.pypa.io/get-pip.py"

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

# Make sure the certificates have been updated
yum -y upgrade ca-certificates

# Manage distribution-specific dependencies
RELEASE=$(grep "release" /etc/system-release)
case "${RELEASE}" in
"Amazon"*)
    OSVER="latest"  # $(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*') #e.g. 'OSVER=2014.7'
    DIST="amzn"
    SALT_EPELDEPS+=( "python-backports-ssl_match_hostname" )
    SALT_REPO_DEPS+=( "python-crypto-2.6.1" )
    SALT_OSDEPS+=( "python-jinja2" )
    SALT_OSDEPS+=( "python-ordereddict" )
    SALT_REPO_DEPS+=( "openpgm-5.2.122" )
    SALT_REPO_DEPS+=( "python-cherrypy" )
    SALT_REPO_DEPS+=( "python-futures-3.0.3" )
    SALT_REPO_DEPS+=( "zeromq-4.0.5" )
    ;;
"CentOS"*"6."*)
    DIST="centos"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=6'
    service ntpd start 2>&1 > /dev/null && echo "Started ntpd..." || echo "Failed to start ntpd..."
       ### ^^^Workaround for issue where localtime is misconfigured on CentOS6
    SALT_OSDEPS+=( "python-backports-ssl_match_hostname" )
    SALT_REPO_DEPS+=( "python-crypto-2.6.1" )
    SALT_OSDEPS+=( "python-jinja2" )
    SALT_OSDEPS+=( "python-ordereddict" )
    SALT_REPO_DEPS+=( "openpgm-5.2.122" )
    SALT_REPO_DEPS+=( "python-cherrypy" )
    SALT_REPO_DEPS+=( "python-futures-3.0.3" )
    SALT_REPO_DEPS+=( "zeromq-4.0.5" )
    ;;
"CentOS"*"7."*)
    DIST="centos"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=7'
    SALT_OSDEPS+=( "python-backports-ssl_match_hostname" )
    SALT_OSDEPS+=( "systemd-python" )
    SALT_OSDEPS+=( "python-crypto-2.6.1" )
    SALT_REPO_DEPS+=( "python-jinja2" )
    SALT_EPELDEPS+=( "python-ordereddict" )
    SALT_EPELDEPS+=( "openpgm-5.2.122" )
    SALT_EPELDEPS+=( "python-cherrypy" )
    SALT_EPELDEPS+=( "python-futures-3.0.3" )
    SALT_EPELDEPS+=( "zeromq-4.0.5" )
    ;;
"Red Hat"*"6."*)
    DIST="rhel"
    OSVER="$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1)Server" #e.g. 'OSVER=6Server'
    curl -O "${EPEL6_RPM}" && \
    yum -y install epel-release-6-8.noarch.rpm
    SALT_EPELDEPS+=( "python-backports-ssl_match_hostname" )
    SALT_REPO_DEPS+=( "python-crypto-2.6.1" )
    SALT_OSDEPS+=( "python-jinja2" )
    SALT_OSDEPS+=( "python-ordereddict" )
    SALT_REPO_DEPS+=( "openpgm-5.2.122" )
    SALT_REPO_DEPS+=( "python-cherrypy" )
    SALT_REPO_DEPS+=( "python-futures-3.0.3" )
    SALT_REPO_DEPS+=( "zeromq-4.0.5" )
    ;;
"Red Hat"*"7."*)
    DIST="rhel"
    OSVER="$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1)Server" #e.g. 'OSVER=7Server'
    curl -O "${EPEL7_RPM}" && \
    yum -y install epel-release-7-5.noarch.rpm
    SALT_OSDEPS+=( "python-backports-ssl_match_hostname" )
    SALT_OSDEPS+=( "systemd-python" )
    SALT_EPELDEPS+=( "python-crypto-2.6.1" )
    SALT_REPO_DEPS+=( "python-jinja2" )
    SALT_EPELDEPS+=( "python-ordereddict" )
    SALT_EPELDEPS+=( "openpgm-5.2.122" )
    SALT_EPELDEPS+=( "python-cherrypy" )
    SALT_EPELDEPS+=( "python-futures-3.0.3" )
    SALT_EPELDEPS+=( "zeromq-4.0.5" )
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
OSBUCKET="${BUCKETNAME}/linux/${DIST}/${OSVER}/"
EPELVER=$(rpm -qa |grep epel-release | cut -d'-' -f3)
EPELREPO=$(echo ~/repo/epel/${EPELVER}/${ARCH})
EPELPACKAGES="${EPELREPO}/packages"
EPELBUCKET="${BUCKETNAME}/linux/epel/${EPELVER}/"
SALTREPO=$(echo ~/repo/saltstack/salt/epel-${EPELVER}/${ARCH})
SALTREPOPACKAGES="${SALTREPO}/packages"
SALTREPOBUCKET="${BUCKETNAME}/linux/saltstack/salt/epel-${EPELVER}/"
GPGKEY_SALTREPO="https://repo.saltstack.com/yum/rhel${EPELVER}/SALTSTACK-GPG-KEY.pub"

# Define SaltStack repo with the latest salt packages and dependencies that
# are not in the OS or epel repos
cat > /etc/yum.repos.d/saltstack.repo << HEREFILE
# Enable SaltStack package repository
[saltstack-repo]
name=SaltStack repo for RHEL/CentOS $EPELVER
baseurl=https://repo.saltstack.com/yum/rhel$EPELVER
enabled=1
gpgcheck=1
gpgkey=https://repo.saltstack.com/yum/rhel$EPELVER/SALTSTACK-GPG-KEY.pub
HEREFILE

# Enable repos
yum-config-manager --enable "*"
for repo in "testing" "source" "debug" "contrib" "C6" "media" "fasttrack" "preview" "nosrc"; do
    yum-config-manager --disable "*${repo}*"
done

#Clean the yum cache
yum clean all

# Download packages to the staging directory
mkdir -p "${OSPACKAGES}" "${EPELPACKAGES}" "${STAGING}" "${SALTREPOPACKAGES}"
SALT_OSDEPS_STRING=$( IFS=$' '; echo "${SALT_OSDEPS[*]}" )
SALT_EPELDEPS_STRING=$( IFS=$' '; echo "${SALT_EPELDEPS[*]}" )
SALT_REPO_DEPS_STRING=$( IFS=$' '; echo "${SALT_REPO_DEPS[*]}" )
yumdownloader --resolve --destdir "${STAGING}" --archlist="${ARCH}" ${SALT_OSDEPS_STRING} ${SALT_EPELDEPS_STRING} ${SALT_REPO_DEPS_STRING}

# Move packages to the epel repo directory
for package in ${SALT_EPELDEPS_STRING}; do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${EPELPACKAGES}"
done

# Move packages to the salt repo directory
for package in ${SALT_REPO_DEPS_STRING}; do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${SALTREPOPACKAGES}"
done

# Move all other packages to the os repo directory
mv ${STAGING}/* "${OSPACKAGES}"

# Copy the GPG keys to the repo
GPGKEY="GPGKEY_${DIST^^}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${!GPGKEY}" | xargs -i cp {} "${OSREPO}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${GPGKEY_EPEL}" | xargs -i cp {} "${EPELREPO}"
curl -o "${SALTREPO}/SALTSTACK-GPG-KEY.pub" "${GPGKEY_SALTREPO}"

# Install pip
curl ${PIP_INSTALLER} -o /tmp/get-pip.py
python /tmp/get-pip.py
hash pip 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Make sure pip is in path

# Upgrade setuptools
pip install --upgrade setuptools

# Install s3cmd
pip install --upgrade s3cmd
hash s3cmd 2> /dev/null || PATH="${PATH}:/usr/local/bin"  # Make sure s3cmd is in path

# Sync the packages to S3
s3cmd sync ${OSREPO} s3://${OSBUCKET}
s3cmd sync ${EPELREPO} s3://${EPELBUCKET}
s3cmd sync ${SALTREPO} s3://${SALTREPOBUCKET}

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
    systemctl restart systemd-journald.service
fi

echo "Finished staging the packages!"
