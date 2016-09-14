#!/bin/bash
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# No arguments supplied, print current stage config file
if [ $# -eq 0 ] && [ -f "$SCRIPT_DIR/../ubnext_stages.config.yml" ]; then
  readlink -f "$SCRIPT_DIR/../ubnext_stages.config.yml"
  exit 0
fi

if [ -f "$SCRIPT_DIR/../ubnext_stages.config.yml" ]; then
  unlink "$SCRIPT_DIR/../ubnext_stages.config.yml"
fi

if [ -f "$SCRIPT_DIR/../stages/ubnext_stages.$1.config.yml" ]; then
  cd "$SCRIPT_DIR/.." && ln -s "stages/ubnext_stages.$1.config.yml" ubnext_stages.config.yml
else
  echo "Error: invalid stage \"$1\""
  exit 1
fi
