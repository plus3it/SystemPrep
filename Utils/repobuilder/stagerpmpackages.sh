#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "stage_rpm_packages" -s 2> /dev/console) 2>&1

BUCKETNAME=${1:-systemprep-repo}

BUILDER_DEPS=(
    "yum-utils"
    "createrepo"
)

SALT_DEPS=( 
    "PyYAML"
    "audit-libs-python"
    "hwdata"
#    "libcgroup"
    "libselinux-python"
    "libsemanage-python"
#    "libyaml"
#    "m2crypto"
#    "openpgm"
    "pciutils"
    "policycoreutils"
    "policycoreutils-python"
    "python-babel"
    "python-backports"
    "python-backports-ssl_match_hostname"
    "python-chardet"
    "python-cherrypy"
    "python-crypto"
    "python-futures"
    "python-jinja2"
    "python-libcloud"
    "python-libs"
    "python-markupsafe"
    "python-msgpack"
    "python-ordereddict"
    "python-pycurl"
    "python-requests"
    "python-setuptools"
    "python-six"
    "python-timelib"
    "python-tornado"
    "python-urllib3"
    "python-zmq"
    "salt"
    "salt-api"
    "salt-cloud"
    "salt-master"
    "salt-minion"
    "salt-ssh"
    "salt-syndic"
    "selinux-policy"
    "selinux-policy-targeted"
    "setools-libs"
    "setools-libs-python"
    "systemd-python"
    "unzip"
    "yum-utils"
    "zeromq"
)

SALT_RAET_DEPS=(
    "libsodium"
    "python-enum34"
    "python-importlib"
    "python-ioflo"
    "python-libnacl"
    "python-raet"
    "python-simplejson"
)

GPGKEY_CENTOS="RPM-GPG-KEY-CentOS-[0-9]"
GPGKEY_AMZN="RPM-GPG-KEY-amazon-ga"
GPGKEY_RHEL="RPM-GPG-KEY-redhat-release"

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
    OSVER="latest"  # $(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*') #e.g. 'OSVER=2014.7'
    DIST="amzn"
    ELVER="6"
    ;;
"CentOS"*"6."*)
    DIST="centos"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=6'
    ELVER="6"
    service ntpd start 2>&1 > /dev/null && echo "Started ntpd..." || echo "Failed to start ntpd..."
    SALT_DEPS+=( ${SALT_RAET_DEPS[@]} )
       ### ^^^Workaround for issue where localtime is misconfigured on CentOS6
    ;;
"CentOS"*"7."*)
    DIST="centos"
    OSVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1) #e.g. 'OSVER=7'
    ELVER="7"
    ;;
"Red Hat"*"6."*)
    DIST="rhel"
    OSVER="$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1)Server" #e.g. 'OSVER=6Server'
    ELVER="6"
    SALT_DEPS+=( ${SALT_RAET_DEPS[@]} )
    ;;
"Red Hat"*"7."*)
    DIST="rhel"
    OSVER="$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*' | cut -d'.' -f1)Server" #e.g. 'OSVER=7Server'
    ELVER="7"
    ;;
*)
    echo "Unsupported OS. Exiting"
    exit 1
    ;;
esac

# Install packages required to create the repo
yum -y install ${BUILDER_DEPS[@]}

# Establish variables
STAGING=$(echo ~/repo/staging)
ARCH="${HOSTTYPE}"
OSREPO=$(echo ~/repo/${DIST}/${OSVER}/${ARCH})
OSPACKAGES="${OSREPO}/packages"
OSBUCKET="${BUCKETNAME}/linux/${DIST}/${OSVER}/"
SALTREPO=$(echo ~/repo/saltstack/salt/el${ELVER}/${ARCH})
SALTREPOPACKAGES="${SALTREPO}/packages"
SALTREPOBUCKET="${BUCKETNAME}/linux/saltstack/salt/el${ELVER}/"
GPGKEY_SALTREPO="https://repo.saltstack.com/yum/redhat/${ELVER}/x86_64/latest/SALTSTACK-GPG-KEY.pub"

# Define SaltStack repo with the latest salt packages and dependencies that
# are not in the OS or epel repos
cat > /etc/yum.repos.d/saltstack.repo << HEREFILE
# Enable SaltStack package repository
[saltstack-repo]
name=SaltStack repo for RHEL/CentOS $ELVER
baseurl=https://repo.saltstack.com/yum/redhat/${ELVER}/\$basearch/latest
enabled=1
gpgcheck=1
gpgkey=https://repo.saltstack.com/yum/redhat/${ELVER}/\$basearch/latest/SALTSTACK-GPG-KEY.pub
HEREFILE

# Enable repos
yum-config-manager --enable "*"
for repo in "testing" "source" "debug" "contrib" "C6" "C7" "media" "fasttrack" "preview" "nosrc" "epel"
do
    yum-config-manager --disable "*${repo}*"
done

#Clean the yum cache
yum clean all

# Download packages to the staging directory
mkdir -p "${OSPACKAGES}" "${STAGING}" "${SALTREPOPACKAGES}"
yumdownloader --resolve --destdir "${STAGING}" --archlist="${ARCH}" ${SALT_DEPS[@]}

SALT_OS_DEPS=()
SALT_REPO_DEPS=()

for package in ${SALT_DEPS[@]}
do
    repo=$(repoquery -q --qf '%{repoid}' "${package}")
    case "${repo}" in
        "")
            ;;
        "saltstack-repo")
            SALT_REPO_DEPS+=( "${package}" )
            ;;
        *)
            SALT_OS_DEPS+=( "${package}" )
            ;;
    esac
done

# Move packages to the salt repo directory
for package in ${SALT_REPO_DEPS[@]}
do
    find "${STAGING}/" -type f | grep -i "${package}-[0-9]*" | xargs -i mv {} "${SALTREPOPACKAGES}"
done

# Move all other packages to the os repo directory
mv ${STAGING}/* "${OSPACKAGES}"

# Copy the GPG keys to the repo
GPGKEY="GPGKEY_${DIST^^}"
find /etc/pki/rpm-gpg/ -type f | grep -i "${!GPGKEY}" | xargs -i cp {} "${OSREPO}"
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
s3cmd sync ${SALTREPO} s3://${SALTREPOBUCKET}

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

echo "Finished staging the packages!"
