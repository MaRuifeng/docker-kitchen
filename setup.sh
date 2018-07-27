#!/bin/bash

##########################################################################################
# Kitchen test set up for SLA in a docker container
#  - Create user and group
#  - Install Ruby and gems

# Author:
#  Ruifeng Ma <ruifengm@sg.ibm.com>
# Date:
#  2017-May-04
##########################################################################################

# Add chef user and generate a random password with 6 characters that includes at least one capital letter and number
CHEF_PASSWORD=`pwgen -c -n -1 6`
echo "<pwd>"User: chef Password: $CHEF_PASSWORD"<pwd>"
CHEF_DOCKER_ENCRYPYTED_PASSWORD=`perl -e 'print crypt('"$CHEF_PASSWORD"', "aa"),"\n"'`
useradd -m -d /home/chef -p $CHEF_DOCKER_ENCRYPYTED_PASSWORD chef
# sed -Ei 's/adm:x:4:/cobalt:x:4:cobalt/' /etc/group
# sed -i '$i cobalt:x:4:cobalt/' /etc/group
adduser chef sudo

# Set the default shell as bash for chef user
chsh -s /bin/bash chef

# Create chef user directory and copy required files
mkdir /home/chef/kitchen
cd /src/ && cp -rf .[a-zA-Z]* [a-zA-Z]* /home/chef/kitchen
chown -R chef /home/chef/

# Clear the src folder
rm -rf /src/*

# Store the user's password to its home directory
echo $CHEF_PASSWORD > /home/chef/userpwd.txt

# RVM, Ruby and application code installation needs to be performed by the chef user
su chef <<'EOF'
cd
echo $(id)

# Install RVM, use RVM to install Ruby version 2.3.1, and then install required gems
cd /home/chef/kitchen
echo "Installing RVM..."
# gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3
# In case direct key reception does not work due to network issue, use below two commands to download and import
curl -#LO https://rvm.io/mpapis.asc
gpg --import mpapis.asc
curl -sSL https://get.rvm.io | bash -s -- --version 1.27.0
source /home/chef/.rvm/scripts/rvm
source /home/chef/.profile
echo $(rvm -v)
echo "RVM installation completed."
echo "Installing Ruby (version 2.3.1) ..."
echo $PATH
rvm install 2.3.1
rvm use 2.3.1 --default
echo $(ruby -v)
echo "Ruby (version 2.3.1) installation completed."
cd /home/chef/kitchen
gem install bundler -v '1.13.6'
bundle install
EOF
