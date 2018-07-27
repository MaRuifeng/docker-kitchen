#!/bin/bash -e

##########################################################################################
# Kitchen test for SLA in a docker container
#  - Run tests via SSH driver on remote endpoint servers
#  - Report results via RTC, HTML page, Email and Slack

# Author:
#  Ruifeng Ma <ruifengm@sg.ibm.com>
# Date:
#  2017-May-04
##########################################################################################

## Check build name
build_regex=".*(ivt_[0-9]+\.[0-9]|Development)\.[0-9]{8}-[0-9]{4}\.[0-9]+$"
[[ $APP_BUILD =~ $build_regex ]] || (echo -e "Given build name $APP_BUILD is invalid"'!' && exit 1)

## Check test phase
test_phase_regex="^(bvt|ivt)$"
[[ $TEST_PHASE =~ $test_phase_regex ]] || (echo -e "Given test phase $TEST_PHASE is invalid"'!' && exit 1)

## Check endpoint platform
shopt -s nocasematch
edpt_platform_regex="^(windows|linux|aix|suse|ubuntu)$"
[[ $ENDPOINT_PLATFORM =~ $edpt_platform_regex ]] || (echo -e "Given server platform $ENDPOINT_PLATFORM is invalid"'!' && exit 1)
shopt -u nocasematch

## Check SSH private key to be used
if [[ -f /home/chef/kitchen/id_rsa ]]; then
	[[ ! -d /home/chef/.ssh ]] && mkdir -p /home/chef/.ssh
	cp -r /home/chef/kitchen/id_rsa /home/chef/.ssh/id_rsa
else
	echo -e "No SSH private key found"'!' && exit 1
fi

export COOKBOOK_PATH="/home/chef/kitchen/cookbooks"
export RAW_REPORT_PATH="/home/chef/ccssd-test/$APP_BUILD/$TEST_PHASE/kitchen-result/$ENDPOINT_PLATFORM/json-reports"
export LOG_PATH="/home/chef/ccssd-test/$APP_BUILD/$TEST_PHASE/kitchen-result/$ENDPOINT_PLATFORM/logs"
export HTML_REPORT_PATH="/home/chef/ccssd-test/$APP_BUILD/$TEST_PHASE/kitchen-result/$ENDPOINT_PLATFORM"
export TEST_JAR=$(find /home/chef/kitchen -name "KitchenTestAutomation*.jar")
export REPORT_JAR=$(find /home/chef/kitchen -name "KitchenReport*.jar")
export SSH_KEY_PATH="/home/chef/.ssh/id_rsa"

# Grant user chef file permissions
chown -R chef:chef /home/chef/

# Modify the etc/hosts file with additional host/ip pairs
echo -e "\n\n" >> /etc/hosts
cat /home/chef/kitchen/host.info >> /etc/hosts

## Run kitchen
su chef <<'EOF'
cd
PATH=/opt/ibm/java/jre/bin:$PATH
echo "Java home:$JAVA_HOME"
echo "Java version:"
echo $(java -version)
echo "PATH=/opt/ibm/java/jre/bin:$PATH" >> .bashrc
source /home/chef/.rvm/scripts/rvm
echo "Ruby version:"
echo $(ruby -v)
echo "source /home/chef/.rvm/scripts/rvm" >> .bashrc

mkdir kitchen_report_logs
mkdir -p $RAW_REPORT_PATH
mkdir -p $LOG_PATH
mkdir -p $HTML_REPORT_PATH

cd /home/chef/kitchen
echo "Installing/updating gems..."
bundle install
echo "Running kitchen..."
# Originally used kitchen test commands here, later replaced with below jar for better orchestration.
java -jar $TEST_JAR $COOKBOOK_PATH $RAW_REPORT_PATH $LOG_PATH $SSH_KEY_PATH

echo "Reporting..."
java -jar $REPORT_JAR $RAW_REPORT_PATH $LOG_PATH $HTML_REPORT_PATH $APP_BUILD $ENDPOINT_PLATFORM
erb /home/chef/kitchen/kitchen_nginx.conf.erb > /home/chef/kitchen/kitchen_nginx.conf
EOF

## Copy kitchen html results to the default Nginx content folder
# cp -rf /home/chef/ccssd-test/$APP_BUILD/$TEST_PHASE/kitchen-result/* /usr/share/nginx/html

## Start Nginx server
# using global directive 'daemon off' to 
# ensure the docker container does not halt after Nginx spawns its processes
echo "Starting Nginx server with customized configuration..."
/usr/sbin/nginx -g 'daemon off;' -c /home/chef/kitchen/kitchen_nginx.conf
