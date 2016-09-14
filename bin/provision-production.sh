#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
bash "$SCRIPT_DIR/pre-provision.sh production"
ansible-playbook -i "$SCRIPT_DIR/../hosts" $SCRIPT_DIR/../pre-provisioning/playbook.yml
