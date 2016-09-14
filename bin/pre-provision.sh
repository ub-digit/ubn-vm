#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Set stage if argument provided
if [ $# -gt 0 ]; then
  bash "$SCRIPT_DIR/set-stage.sh" $1
  # Exit if stage configuration does not exist
  rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
fi
ansible-playbook -i "localhost," -c local $SCRIPT_DIR/../pre-provisioning/playbook.yml
