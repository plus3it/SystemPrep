#!/bin/sh
#
# Description:
#   This script is intended to help an administrator manage the tasks around
#   joining an instance to the domain using the SystemPrep capability. In
#   addition to the domain join itself, this script features the ability to
#   configure ssh access and sudo privileges for domain users and domain
#   groups.
#
# Usage:
#   See `systemprep-joindomain.sh -h`.
#
#################################################################
__SCRIPTPATH=$(readlink -f ${0})
__SCRIPTDIR=$(dirname ${__SCRIPTPATH})
__SCRIPTNAME=$(basename ${__SCRIPTPATH})

# Define default values
VERBOSE=
DELIM=":"
IFS="${DELIM}" read -r -a ALLOWED_SSH_USERS \
    <<< "${SYSTEMPREP_ALLOWED_SSH_USERS}"
IFS="${DELIM}" read -r -a ALLOWED_SUDO_USERS \
    <<< "${SYSTEMPREP_ALLOWED_SUDO_USERS}"
IFS="${DELIM}" read -r -a ALLOWED_SSH_GROUPS \
    <<< "${SYSTEMPREP_ALLOWED_SSH_GROUPS}"
IFS="${DELIM}" read -r -a ALLOWED_SUDO_GROUPS \
    <<< "${SYSTEMPREP_ALLOWED_SUDO_GROUPS}"
IFS="${DELIM}" read -r -a REVOKED_SSH_USERS \
    <<< "${SYSTEMPREP_REVOKED_SSH_USERS}"
IFS="${DELIM}" read -r -a REVOKED_SUDO_USERS \
    <<< "${SYSTEMPREP_REVOKED_SUDO_USERS}"
IFS="${DELIM}" read -r -a REVOKED_SSH_GROUPS \
    <<< "${SYSTEMPREP_REVOKED_SSH_GROUPS}"
IFS="${DELIM}" read -r -a REVOKED_SUDO_GROUPS \
    <<< "${SYSTEMPREP_REVOKED_SUDO_GROUPS}"


# Define helper functions
print_usage()
{
    cat << EOT

  This script will use the capability provided by the systemprep framework to
  join a system to the domain and grant or revoke ssh-login and sudo
  privileges for specified domain users or domain groups.

  Parameters may be passed as short-form or long-form arguments, or they may
  be exported as environment variables. Command line arguments take precedence
  over environment variables.

  Usage: ${__SCRIPTNAME} [options]

  Options:
  -s|--allowed-ssh-users|\$SYSTEMPREP_ALLOWED_SSH_USERS
      Colon-separated list of domain users to grant remote ssh login
      privileges.
  -S|--allowed-sudo-users|\$SYSTEMPREP_ALLOWED_SUDO_USERS
      Colon-separated list of domain users to grant passwordless sudo
      privileges. These users will also be able to login via ssh.
  -g|--allowed-ssh-groups|\$SYSTEMPREP_ALLOWED_SSH_GROUPS
      Colon-separated list of domain groups to grant remote ssh login
      privileges.
  -G|--allowed-sudo-groups|\$SYSTEMPREP_ALLOWED_SUDO_GROUPS
      Colon-separated list of domain groups to grant passwordless sudo
      privileges. These groups will also be able to login via ssh.
  -r|--revoked-ssh-users|\$SYSTEMPREP_REVOKED_SSH_USERS
      Colon-separated list of domain users from whom to revoke remote ssh
      login privileges.
  -R|--revoked-sudo-users|\$SYSTEMPREP_REVOKED_SUDO_USERS
      Colon-separated list of domain users from whom to revoke
      passwordless sudo privileges. These users will also not be authorized
      for ssh login.
  -x|--revoked-ssh-groups|\$SYSTEMPREP_REVOKED_SSH_GROUPS
      Colon-separated list of domain groups from whom to revoke remote ssh
      login privileges.
  -X|--revoked-sudo-groups|\$SYSTEMPREP_REVOKED_SUDO_GROUPS
      Colon-separated list of domain groups from whom to revoke
      passwordless sudo privileges. These users will also not be authorized
      for ssh login.
  -h|--help
      Display this message.
  -v|--verbose
      Display verbose output

EOT
}  # ----------  end of function print_usage  ----------


log()
{
    if [[ "$1" != "-v" ]]
    then
        logger -i -t "${__SCRIPTNAME}" -s -- "$1" 2> /dev/console
        echo "$1"
    elif [[ -n "${VERBOSE}" ]]
    then
        log "$2"
    fi
}  # ----------  end of function log  ----------


die()
{
    [[ -n "$1" ]] && log "$1" >&2
    log "ERROR: ${__SCRIPTNAME} failed"'!' >&2
    exit 1
}  # ----------  end of function die  ----------


lower()
{
    echo "${1}" | tr '[:upper:]' '[:lower:]'
}  # ----------  end of function lower  ----------


create_user_group()
{
    local USER="${1}"
    local GRPCFG="/etc/group"
    if [[ $(grep -q "^${USER}.*${USER}" "${GRPCFG}")$? -eq 0 ]]
    then
        log "No change: '${USER}' already configured with a local group"
    else
        groupadd -f "${USER}" || return 1
        sed -i 's/^'"${USER}"':.*:.*:/&'"${USER}"'/' "${GRPCFG}" || return 1
        log "Changed: configured local group for '${USER}'"
    fi
}  # ----------  end of function create_user_group  ----------


remove_user_group()
{
    local USER="${1}"
    local GRPCFG="/etc/group"
    if [[ $(grep -q "^${USER}" "${GRPCFG}")$? -ne 0 ]]
    then
        log "No change: '${USER}' has no local group"
    else
        groupdel "${USER}" || return 1
        log "Changed: removed local group for '${USER}'"
    fi
}  # ----------  end of function remove_user_group  ----------


grant_ssh_login()
{
    local GROUP="${1}"
    local SSHCFG="/etc/ssh/sshd_config"
    if [[ $(grep -q "^AllowGroups" "${SSHCFG}")$? -ne 0 ]]
    then
        if [[ $(grep -q "^Match" "${SSHCFG}")$? -eq 0 ]]
        then
            # Insert AllowGroups before the Match section
            sed -i 's/^Match.*/AllowGroups\n\n&/' "${SSHCFG}"
        else
            # Append AllowGroups to the end of the file
            printf '\nAllowGroups\n' >> "${SSHCFG}"
        fi
    fi
    if [[ $(grep -q "^AllowGroups.*${GROUP}" ${SSHCFG})$? -eq 0 ]]
    then
        log "No change: '${GROUP}' already in SSH AllowGroups directive"
    else
        sed -i 's/AllowGroups.*$/& '"${GROUP}"'/' "${SSHCFG}" || return 1
        log "Changed: granted SSH access to '${GROUP}'"
    fi
}  # ----------  end of function grant_ssh_login  ----------


revoke_ssh_login()
{
    local GROUP="${1}"
    local SSHCFG="/etc/ssh/sshd_config"
    if [[ $(grep -q "^AllowGroups.*${GROUP}" "${SSHCFG}")$? -ne 0 ]]
    then
        log "No change: '${GROUP}' not in SSH AllowGroups directive"
    else
        sed -i "{
            /^AllowGroups.*${GROUP}/s/ ${GROUP}//
        }" "${SSHCFG}" || return 1
        log "Changed: revoked SSH access from '${GROUP}'"
    fi
}  # ----------  end of function revoke_ssh_login  ----------


grant_sudo_root()
{
    local GROUP="${1}"
    local SUDOFILE="/etc/sudoers.d/group_${GROUP}"
    if [[ -f "${SUDOFILE}" ]]
    then
        log "No change: '${GROUP}' already has sudo access"
    else
        printf '%%%s\tALL=(root)\tNOPASSWD:ALL\n' "${GROUP}" > "${SUDOFILE}" \
            || return 1
        log "Changed: granted sudo access to '${GROUP}'"
    fi
}  # ----------  end of function grant_sudo  ----------


revoke_sudo()
{
    local GROUP="${1}"
    local SUDOFILE="/etc/sudoers.d/group_${GROUP}"
    if [[ -f "${SUDOFILE}" ]]
    then
        rm -f "${SUDOFILE}" || return 1
        log "Changed: revoked sudo access from '${GROUP}'"
    else
        log "No change: '${GROUP}' has no sudo access"
    fi
}  # ----------  end of function revoke_sudo  ----------


# Parse command-line parameters
SHORTOPTS="hvs:S:g:G:r:R:x:X:"
LONGOPTS=(
    "help,verbose,allowed-ssh-users:,allowed-sudo-users:,allowed-ssh-groups:,"
    "allowed-sudo-groups:,revoked-ssh-users:,revoked-sudo-users:,"
    "revoked-ssh-groups:,revoked-sudo-groups:")
LONGOPTS_STRING=$(IFS=$''; echo "${LONGOPTS[*]}")
ARGS=$(getopt \
    --options "${SHORTOPTS}" \
    --longoptions "${LONGOPTS_STRING}" \
    --name "${__SCRIPTNAME}" \
    -- "$@")

if [[ $? -ne 0 ]]
then
    # Bad arguments.
    print_usage
    exit 1
fi

eval set -- "${ARGS}"

while [ true ]
do
    # When adding options to the case statement, also update print_usage(),
    # SHORTOPTS and LONGOPTS.
    case "${1}" in
        -s|--allowed-ssh-users)
            shift
            IFS="${DELIM}" read -r -a ALLOWED_SSH_USERS <<< "${1}"
            ;;
        -S|--allowed-sudo-users)
            shift
            IFS="${DELIM}" read -r -a ALLOWED_SUDO_USERS <<< "${1}"
            ;;
        -g|--allowed-ssh-groups)
            shift
            IFS="${DELIM}" read -r -a ALLOWED_SSH_GROUPS <<< "${1}"
            ;;
        -G|--allowed-sudo-groups)
            shift
            IFS="${DELIM}" read -r -a ALLOWED_SUDO_GROUPS <<< "${1}"
            ;;
        -r|--revoked-ssh-users)
            shift
            IFS="${DELIM}" read -r -a REVOKED_SSH_USERS <<< "${1}"
            ;;
        -R|--revoked-sudo-users)
            shift
            IFS="${DELIM}" read -r -a REVOKED_SUDO_USERS <<< "${1}"
            ;;
        -x|--revoked-ssh-groups)
            shift
            IFS="${DELIM}" read -r -a REVOKED_SSH_GROUPS <<< "${1}"
            ;;
        -X|--revoked-sudo-groups)
            shift
            IFS="${DELIM}" read -r -a REVOKED_SUDO_GROUPS <<< "${1}"
            ;;
        -v|--verbose)
            VERBOSE="true"
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            print_usage
            die "ERROR: Unhandled option parsing error."
            ;;
    esac
    shift
done


# Begin work
JOIN_STATUS=$(/opt/pbis/bin/pbis-status 2> /dev/null | \
                awk '/^[[:space:]]+Status:/{print $2}' )

log "Executing the join-domain formula..."
salt-call --local --retcode-passthrough state.sls join-domain || \
    die "Error running the join-domain formula"

log "Completed the join-domain formula"

for token in "${ALLOWED_SSH_USERS[@]}"
do
    if [[ -n "${token}" ]]
    then
        create_user_group $(lower "${token}") || \
            die "Error creating a local group for user '${token}'"
        grant_ssh_login $(lower "${token}") || \
            die "Error granting ssh access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${ALLOWED_SUDO_USERS[@]}"
do
    if [[ -n "${token}" ]]
    then
        create_user_group $(lower "${token}") || \
            die "Error creating a local group for user '${token}'"
        grant_ssh_login $(lower "${token}") || \
            die "Error granting ssh access for '${token}'"
        grant_sudo_root $(lower "${token}") || \
            die "Error granting sudo access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${ALLOWED_SSH_GROUPS[@]}"
do
    if [[ -n "${token}" ]]
    then
        grant_ssh_login $(lower "${token}") || \
            die "Error granting ssh access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${ALLOWED_SUDO_GROUPS[@]}"
do
    if [[ -n "${token}" ]]
    then
        grant_ssh_login $(lower "${token}") || \
            die "Error granting ssh access for '${token}'"
        grant_sudo_root $(lower "${token}") || \
            die "Error granting sudo access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${REVOKED_SSH_USERS[@]}"
do
    if [[ -n "${token}" ]]
    then
        remove_user_group $(lower "${token}") || \
            die "Error removing local group for user '${token}'"
        revoke_ssh_login $(lower "${token}") || \
            die "Error revoking ssh access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${REVOKED_SUDO_USERS[@]}"
do
    if [[ -n "${token}" ]]
    then
        remove_user_group $(lower "${token}") || \
            die "Error removing local group for user '${token}'"
        revoke_ssh_login $(lower "${token}") || \
            die "Error revoking ssh access for '${token}'"
        revoke_sudo $(lower "${token}") || \
            die "Error revoking sudo access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${REVOKED_SSH_GROUPS[@]}"
do
    if [[ -n "${token}" ]]
    then
        revoke_ssh_login $(lower "${token}") || \
            die "Error revoking ssh access for '${token}'"
        SSHRESTART="1"
    fi
done

for token in "${REVOKED_SUDO_GROUPS[@]}"
do
    if [[ -n "${token}" ]]
    then
        revoke_ssh_login $(lower "${token}") || \
            die "Error revoking ssh access for '${token}'"
        revoke_sudo $(lower "${token}") || \
            die "Error revoking sudo access for '${token}'"
        SSHRESTART="1"
    fi
done

if [[ -n "${SSHRESTART}" ]]
then
    service sshd restart > /dev/null 2>&1 || die "Error restarting sshd"
fi

log "Completed ${__SCRIPTNAME}."

if [[ "${JOIN_STATUS}" != "Online" ]]
then
    log "System requires a reboot as it was just joined to the domain."
fi
