#!/bin/bash

echo 'export PATH="/usr/local/opt/postgresql@16/bin:$PATH"' >> ~/.zshrc
echo 'export LDFLAGS="-L/usr/local/opt/postgresql@16/lib"' >> ~/.zshrc
echo 'export CPPFLAGS="-I/usr/local/opt/postgresql@16/include"' >> ~/.zshrc
echo 'export PKG_CONFIG_PATH="/usr/local/opt/postgresql@16/lib/pkgconfig"' >> ~/.zshrc

source ~/.zshrc
