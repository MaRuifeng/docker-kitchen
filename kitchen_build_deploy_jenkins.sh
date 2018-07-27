#!/bin/bash -e

##########################################################################################
# SLA Chef Policy Cookbooks - kitchen test build & deploy
# 1. Build docker images with proper version tag and push to DTR
#    Note: this build script is primarily written for Jenkins use (https://itaas-build.sby.ibm.com:9443/),
#          and it takes git resources and environment variables from preceding steps.
# 2. Package deployment scripts/files into a tar ball
# 3. Transfer the tar ball to the designated server
# 4. Deploy the required containers via SSH
# 
# Note: this script is used by Jenkins job CCSSD-KitchenTest only

# Author:
#  Ruifeng Ma <ruifengm@sg.ibm.com>
# Date:
#  2017-May-05
##########################################################################################

export DTR_HOST='DTR_HOST'
export DTR_ORG='DTR_ORG'
export DTR_USER=${ARTIFACTORY_DTR_USER}
export DTR_PASS=${ARTIFACTORY_DTR_PASS}

export ELK_HOSTNAME='sla-bvt-elk-sjc01.sdad.sl.dst.ibm.com'
export ELK_IP='10.91.201.197'

export PATH=$PATH:/usr/local/rvm/gems/ruby-2.2.2/bin:/usr/local/rvm/gems/ruby-2.2.2@global/bin:/usr/local/rvm/rubies/ruby-2.2.2/bin:/usr/local/bin:/usr/local/sbin:/usr/local/rvm/bin
export GEM_PATH="/usr/local/rvm/gems/ruby-2.2.2:/usr/local/rvm/gems/ruby-2.2.2@global"

################## Environment Variable Setup (Start) ##################
rm -f job.properties
if [ -z ${BUILD_VERSION_IN} ]; then
    echo -e "No BUILD_VERSION_IN provided! It's needed to build image, run test and report." && exit 1
else
    BUILD_REGEX=".*(ivt_[0-9]+\.[0-9]|Development)\.[0-9]{8}-[0-9]{4}\.[0-9]+$"
    [[ $BUILD_VERSION_IN =~ $BUILD_REGEX ]] || (echo -e "Given build version $BUILD_VERSION_IN is invalid"'!' && exit 1)
    export BUILD_VERSION=${ENDPOINT_PLATFORM}.${BUILD_VERSION_IN}
    echo "BUILD_VERSION="${BUILD_VERSION_IN} >> job.properties
fi

echo "TARGET_SERVER_IP="${TARGET_SERVER_IP} >> job.properties
echo "ENDPOINT_PLATFORM="${ENDPOINT_PLATFORM} >> job.properties
################## Environment Variable Setup (End) ##################

################## Load Cookbooks (Start) ##################
cd $WORKSPACE
export ACSE_COOKBOOK_DIR="acse-chef-cookbooks-fork"

if [ "$RELOAD_COOKBOOKS" == true ]; then
    export BRANCH_SPRINT=$COOKBOOK_BRANCH
    export GIT_TOKEN=${GitHubToken} # for user bpmbuild@sg.ibm.com
    # !!!!! Number of projects limited to 100 per page for GitHub APIs (https://developer.github.com/v3/#pagination) !!!!!
    export API_FORKED_PRJ="https://github.ibm.com/api/v3/user/repos?page=[PAGE_NUM]&per_page=100"
    
    echo -e "Retrieving all forked ACSE cookbook projects..."
    # Set up directory and initialize git
    rm -rf $ACSE_COOKBOOK_DIR
    mkdir -p "$ACSE_COOKBOOK_DIR"
    cd "$ACSE_COOKBOOK_DIR"

    git init
    git config --global user.name "bpmbuild"
    git config --global user.email bpmbuild@sg.ibm.com

    # Retrieve all forked cookbook projects
    forkedPrjList=""
    i=1
    while true
    do 
        api=${API_FORKED_PRJ/\[PAGE_NUM\]/$i}
        echo -e $api
        output=$(curl -H "Authorization: token $GIT_TOKEN" "$api" | jq -r '.[]')
        temp=$(echo "$output" | jq -r 'select(.owner.login == "bpmbuild") | .ssh_url')
        forkedPrjList="$forkedPrjList $temp" # concatenate multiple API outputs
        [[ ! -z $output ]] || break # check if output empty
        i=$(( i+1 ))
    done 

    for prj in ${forkedPrjList[@]}
    do
        if [ ! -z $prj ] # not null
        then        
            # Get project name
            PROJ_NAME=${prj##*/} # remove the loggest string part maching the pattern from the beginning
            PROJ_NAME=${PROJ_NAME%.git} # remove the shortest string part matching the pattern from the end

            # Load project
            if [[ $PROJ_NAME =~ (${ENDPOINT_PLATFORM}|.*ingredients.*) ]]; then
                echo -e "Cloning ${prj} ..."
                git -c core.askpass=true clone $prj # clone projects
                cd "$PROJ_NAME"
                # get full SHA1 hash of latest commit of the given branch
                flag=true
                # git branch -r | grep "\borigin/${BRANCH_SPRINT}$" || flag=false
                git rev-parse refs/remotes/origin/"$BRANCH_SPRINT"^{object} || flag=false
                if [ $flag = false ]; then
                    echo -e "No branch $BRANCH_SPRINT found for project $prj. Removing it..."
                    cd ..
                    rm -rf "$PROJ_NAME"
                else
                    CUR_COMMIT=$(git rev-parse refs/remotes/origin/"$BRANCH_SPRINT"^{commit}) || flag=false 
                    if [ $flag = false ]; then
                        echo -e "No commit found in branch $BRANCH_SPRINT for project $prj. Removing it..."
                        cd ..
                        rm -rf "$PROJ_NAME"
                    else 
                        git checkout -f $CUR_COMMIT
                        cd ..
                    fi
                fi
            fi
        fi
    done
    echo -e "All forked cookbook projects retrieved."
else
    echo -e "The requester chose not to reload the cookbooks from their repositories. Cached copies will be packaged into the image."
fi
################## Load Cookbooks (End) ##################

################## Resolve cookbook dependencies using Berkshelf (Start) ##################
cd $WORKSPACE
rm -rf ${ACSE_COOKBOOK_DIR}/Berksfile* 
cp kitchen_test/Berksfile ${ACSE_COOKBOOK_DIR}

echo -e "Checking if Berkshelf and Chef ruby gems are installed ... Install them if not."
if [ $(gem query -i -n berkshelf) != true ]; then
    gem install berkshelf --no-ri --no-rdoc
fi
if [ $(gem query -i -n chef) != true ]; then
    gem install chef --no-ri --no-rdoc
fi

cd ${ACSE_COOKBOOK_DIR}
# uninstall gems (used by other jobs) with version conflicts  >> consider docker
gem uninstall -i /usr/local/rvm/gems/ruby-2.2.2 chef-config --version '12.16.42' || true
gem uninstall -i /usr/local/rvm/gems/ruby-2.2.2 chef-config --version '12.10.24' || true
echo -e "Running berks install..."
berks install --except exempt 2>&1 >/dev/null  # redirect stderr to stdout, and stdout to null
echo -e "Running berks list to get all dependency information..."
berks_list=$(berks list)
echo -e "Copying resolved dependencies to the target location..."
find $WORKSPACE"/kitchen_test/cookbooks" -maxdepth 1 -mindepth 1 -type d -exec rm -r {} \;
berk_cache_dirs=(/home/jenkins/.berkshelf/cookbooks/*)
for dir in "${berk_cache_dirs[@]}" 
do 
    if [ -d "$dir" ]; then
        regex=${dir##*/}
        name_regex=${regex%%-[0-9]*}
        version_regex=${regex##*-}
        if [[ "$berks_list" =~ "$name_regex" && "$berks_list" =~ "$version_regex" ]]; then
            cp -r "$dir" $WORKSPACE"/kitchen_test/cookbooks/"
        fi
    fi
done

echo -e "Stripping version number from the cookbook names..."
cd $WORKSPACE"/kitchen_test/cookbooks/"
cookbook_dirs=(*/)
for dir in "${cookbook_dirs[@]}" 
do 
    if [ -d "$dir" ]; then
        new_dir_name=${dir%%-[0-9]*}
        mv "$dir" "$new_dir_name"
    fi
done

################## Resolve cookbook dependencies using Berkshelf (End) ##################

################## Build Images (Start) ##################
cd $WORKSPACE
# Get cookbooks to be tested
cp -r ${ACSE_COOKBOOK_DIR}/* kitchen_test/cookbooks/

# Get SSH private key to be used
scp root@${TARGET_SERVER_IP}:/root/.ssh/id_rsa kitchen_test/

echo -e "Building kitchen test docker image..."
cd $WORKSPACE/kitchen_test

# Build and push base kitchen test image
# docker login -u $DTR_USER -p $DTR_PASS $DTR_HOST
# docker build -t "sla-kitchen-base" ./
# docker tag sla-kitchen-base $DTR_HOST/$DTR_ORG/sla-kitchen-base
# docker login -u $DTR_USER -p $DTR_PASS $DTR_HOST
# docker push $DTR_HOST/$DTR_ORG/sla-kitchen-base
# docker logout $DTR_HOST

# Build and push executional kitchen test image
docker login -u $DTR_USER -p $DTR_PASS $DTR_HOST
docker build -t $DTR_HOST/$DTR_ORG/sla-kitchen:$BUILD_VERSION -f Dockerfile.exec ./
docker login -u $DTR_USER -p $DTR_PASS $DTR_HOST
docker push $DTR_HOST/$DTR_ORG/sla-kitchen:$BUILD_VERSION
docker logout $DTR_HOST

# Delete loaded policy cookbooks
find $WORKSPACE"/kitchen_test/cookbooks" -maxdepth 1 -mindepth 1 -type d -exec rm -r {} \;
################## Build Image (End) ##################

################## Deploy via SSH (Start) ##################

export RELEASE=$BUILD_VERSION

ssh -o "StrictHostKeyChecking no" root@${TARGET_SERVER_IP} <<EOF
echo -e "SSH Shell currently running on \$(hostname)."

################## SVL Private Network Authentication (Start) ##################
# Note this is only a temporary solution because 
#  1) The connection can only sustain for a limited time period (a few hours)
#  2) Actual human IBM w3id is being used 
# A more stable connection mechanism like cable box should be used 
# if [ $ENDPOINT_PLATFORM = "aix" ]; then
#     echo "Logging into SVL BSO firewall..."
#     login_msg=\$(eval "{ echo ruifengm@sg.ibm.com; sleep 2; echo $SVLPass; sleep 2; }" | telnet 9.30.121.100)
#     [[ \$login_msg =~ "SPN Authentication Successful" ]] || (echo "SVL authentication failed." && exit 1)
# fi
################## SVL Private Network Authentication (End) ##################

# Pull docker images
echo -e "Pulling new $RELEASE sla-kitchen image from DTR..."
docker login -u $DTR_USER -p $DTR_PASS $DTR_HOST
docker pull $DTR_HOST/$DTR_ORG/sla-kitchen:$RELEASE

# Stop and remove running sla-kitchen container
echo -e "Removing old running sla-kitchen container..."
docker rm -f sla-kitchen-$ENDPOINT_PLATFORM
docker network disconnect bridge sla-kitchen-$ENDPOINT_PLATFORM -f

# Create data volumes if not existing
docker volume ls | grep '\bsla-test-auto-data\b' || docker volume create sla-test-auto-data
docker volume ls | grep '\bsla-test-auto-log\b' || docker volume create sla-test-auto-log

# Re-create and start up
echo "Starting new sla-kitchen container..."
# docker run --name sla-kitchen-$ENDPOINT_PLATFORM \
# --add-host ${ELK_HOSTNAME}:${ELK_IP} --log-driver=gelf \
# --log-opt gelf-address=udp://${ELK_HOSTNAME}:12201 --log-opt tag="kitchen" \
# -v sla-test-auto-data:/home/chef/ccssd-test \
# -v sla-test-auto-log:/home/chef/kitchen_report_logs \
# --env APP_BUILD=$BUILD_VERSION_IN --env TEST_PHASE=bvt \
# --env ENDPOINT_PLATFORM=$ENDPOINT_PLATFORM -d -P $DTR_HOST/$DTR_ORG/sla-kitchen:$RELEASE

docker run --name sla-kitchen-$ENDPOINT_PLATFORM \
--add-host ${ELK_HOSTNAME}:${ELK_IP} --log-driver=syslog \
--log-opt syslog-address=tcp://${ELK_HOSTNAME}:5000 --log-opt tag="sla-kitchen-$ENDPOINT_PLATFORM" \
-e "TZ=Asia/Singapore" \
-v sla-test-auto-data:/home/chef/ccssd-test \
-v sla-test-auto-log:/home/chef/kitchen_report_logs \
--env APP_BUILD=$BUILD_VERSION_IN --env TEST_PHASE=bvt \
--env ENDPOINT_PLATFORM=$ENDPOINT_PLATFORM -d -P $DTR_HOST/$DTR_ORG/sla-kitchen:$RELEASE

# Useful command to read docker log
echo -e "To view container stdout log             -  docker logs --tail=all sla-kitchen-$ENDPOINT_PLATFORM"
echo -e "To view container stdout log live        -  docker logs -f sla-kitchen-$ENDPOINT_PLATFORM"
EOF
################## Deploy via SSH (End) ##################