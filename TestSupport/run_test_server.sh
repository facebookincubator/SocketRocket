#
# Copyright (c) 2016-present, Facebook, Inc.
# All rights reserved.
#
# This source code is licensed under the license found in the
# LICENSE-examples file in the root directory of this source tree.
#

PYENV_PATH=$(pwd)/.env

echo $PYENV_PATH
if [ -d "$PYENV_PATH" ]; then 
  source $PYENV_PATH/bin/activate
  $PYENV_PATH/bin/wstest -m fuzzingserver -s TestSupport/autobahn_fuzzingserver.json
else
  echo "Python Virtualenv not set up. Please run './TestSupport/setup_env.sh .env' first."
fi

