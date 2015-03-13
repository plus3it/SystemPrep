#!/usr/bin/env bash
set -ex

exec > >(logger -i -t "systemprep-buildrepo" -s 2> /dev/console) 2>&1

BUILDERDEPS=(
    "epel-release"
    "yum-utils"
    "createrepo"
)

SALTDEPS=( 
    "PyYAML"
    "audit-libs-python"
    "libcgroup"
    "libselinux-python"
    "libsemanage-python"
    "libyaml"
    "m2crypto"
    "openpgm"
    "pciutils"
    "policycoreutils-python"
    "python-babel"
    "python-backports"
    "python-backports-ssl_match_hostname"
    "python-chardet"
    "python-crypto"
    "python-jinja2"
    "python-msgpack"
    "python-ordereddict"
    "python-requests"
    "python-six"
    "python-urllib3"
    "python-zmq"
    "salt"
    "salt-master"
    "salt-minion"
    "setools-libs"
    "setools-libs-python"
    "sshpass"
    "zeromq3"
)

GPGKEY_CENTOS="RPM-GPG-KEY-CentOS-[0-9]"
GPGKEY_EPEL="RPM-GPG-KEY-EPEL-[0-9]"
GPGKEY_AMZN="RPM-GPG-KEY-amazon-ga"
GPGKEY_RHEL="RPM-GPG-KEY-redhat-release"

RELEASE=$(grep "release" /etc/issue)
RELEASEVER=$(echo ${RELEASE} | grep -o '[0-9]*\.[0-9]*')
ARCH="${HOSTTYPE}"

if [[ $(echo ${RELEASE} | grep "Amazon") ]]; then
    DIST="amzn"
elif [[ $(echo ${RELEASE} | grep "CentOS") ]]; then
    DIST="centos"
elif [[ $(echo ${RELEASE} | grep "Red Hat.*6") ]]; then
    DIST="rhel"
    curl -O http://mirror.us.leaseweb.net/epel/6/i386/epel-release-6-8.noarch.rpm && \
    yum install epel-release-6-8.noarch.rpm -y
elif [[ $(echo ${RELEASE} | grep "Red Hat.*7") ]]; then
    DIST="rhel"
    curl -O http://mirror.sfo12.us.leaseweb.net/epel/7/x86_64/e/epel-release-7-5.noarch.rpm && \
    yum install epel-release-7-5.noarch.rpm -y
fi

GPGKEY="GPGKEY_${DIST^^}"
REPO=$(echo ~/repo/${DIST}/${RELEASEVER}/${ARCH})
PACKAGES="${REPO}/packages"
BUCKET="systemprep-repo/${DIST}/${RELEASEVER}/${ARCH}/"

mkdir -p "${PACKAGES}"

BUILDERDEPS_STRING=$( IFS=$' '; echo "${BUILDERDEPS[*]}" )
yum -y install ${BUILDERDEPS_STRING}
yum-config-manager --enable epel

SALTDEPS_STRING=$( IFS=$' '; echo "${SALTDEPS[*]}" )
yumdownloader --resolve --destdir "${PACKAGES}" --archlist="${ARCH}" ${SALTDEPS_STRING}

for key in "${!GPGKEY}" "${GPGKEY_EPEL}";do
    find /etc/pki/rpm-gpg/ -type f | grep -i "${key}" | xargs -i cp {} "${REPO}"
done

createrepo -v --deltas "${REPO}"

yum -y install s3cmd

s3cmd sync ${REPO} s3://${BUCKET}
