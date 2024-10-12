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
  # Please ensure that `python` command refers to Python 2.7.18 to avoid compatibility issues.
  # If you are using asdf, make sure to install and set Python 2.7.18 with the following commands:
  #
  # asdf install python 2.7.18
  # asdf local python 2.7.18
  # pip install virtualenv
  python -m virtualenv $VIRTUALENV_PATH
  source $VIRTUALENV_PATH/bin/activate

  # Make sure openssl@1.1 is installed
  brew install openssl@1.1

  pip install Twisted==15.5
  LDFLAGS="-L$(brew --prefix openssl@1.1)/lib" CFLAGS="-I$(brew --prefix openssl@1.1)/include" pip install cryptography
  pip install autobahntestsuite

  echo "Environment succesfully set up in $VIRTUALENV_PATH."
fi
