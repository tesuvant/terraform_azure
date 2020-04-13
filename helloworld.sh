#!/bin/bash -eux

#sudo /bin/bash -l -c '
cat << EOF >> /etc/bash.bashrc
export HTTP_PROXY=http://myproxy.foo.bar:3128
export HTTPS_PROXY=http://myproxy.foo.bar:3128
export NO_PROXY=.domain.com,.domain.org
export http_proxy=http://myproxy.foo.bar:3128
export https_proxy=http://myproxy.foo.bar:3128
export no_proxy=.domain.com,.domain.org
EOF
