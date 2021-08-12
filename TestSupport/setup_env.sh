#
# Copyright (c) 2016-present, Facebook, Inc.
# All rights reserved.
#
# This source code is licensed under the license found in the
# LICENSE-examples file in the root directory of this source tree.
#

VIRTUALENV_PATH=$1

if [ -d "$VIRTUALENV_PATH" ]; then 
	echo "Virtual Env already installed"
elif [ -z "$VIRTUALENV_PATH" ]; then
  echo "Usage: ./setup_env.sh <folder path>"
else
  mkdir $VIRTUALENV_PATH

  pushd $VIRTUALENV_PATH  
  
  curl -L -o virtualenv.pyz https://bootstrap.pypa.io/virtualenv.pyz
  
  popd

  python $VIRTUALENV_PATH/virtualenv.pyz $VIRTUALENV_PATH

  source $VIRTUALENV_PATH/bin/activate
	pip install autobahntestsuite
  
  echo "Environment succesfully set up in $VIRTUALENV_PATH."
fi
