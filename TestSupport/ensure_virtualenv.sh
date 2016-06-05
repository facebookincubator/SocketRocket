#
# Copyright 2012 Square Inc.
# Portions Copyright (c) 2016-present, Facebook, Inc.
# All rights reserved.
#
# This source code is licensed under the license found in the
# LICENSE-examples file in the root directory of this source tree.
#

VIRTUALENV_PATH=$1

if [ -d "$VIRTUALENV_PATH" ]; then 
	echo "Virtual Env already installed"
else
	python extern/virtualenv/virtualenv.py $VIRTUALENV_PATH
	source $VIRTUALENV_PATH/bin/activate
	pushd TestSupport/sr-testharness/
  env LDFLAGS="-L$(brew --prefix openssl)/lib" CFLAGS="-I$(brew --prefix openssl)/include" pip install cryptography
	python setup.py develop
	popd
fi
