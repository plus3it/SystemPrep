#!/usr/bin/env bash 
set -ex

####################################################################################
#Master Script that calls subscripts to be deployed to new Linux VMs
####################################################################################

if [[ -e /var/run/vm-is-ready ]]; then rm -f /var/run/vm-is-ready; fi

/bin/date > /var/run/vm-is-ready
