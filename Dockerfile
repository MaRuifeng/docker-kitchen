# Dockerfile for Chef recipe kitchen test environment setup
#
# VERSION 0.1
# AUTHOR  Ruifeng Ma (ruifengm@sg.ibm.com)
# LAST MODIFIED 2017-May-02

# This file creates a container of ubuntu nature that runs 
# Ruby and Java services to support kitchen test.
#
# Actual tests are run on dedicated cloud servers via the SSH driver.
# 
# NOTE: image built from this Dockerfile is only a base image without any actual recipes and
#       test cases, it needs to be used by Dockerfile.exec to add executional context

# Pull base image from authorized source 
# FROM sla-dtr.sby.ibm.com/gts-docker-library/ubuntu:14.04
FROM ibmjava:jre
MAINTAINER Ruifeng Ma "ruifengm@sg.ibm.com"

# Ensure the package repository is up to date
# RUN echo "deb http://archive.ubuntu.com/ubuntu precise main universe" > /etc/apt/sources.list
RUN apt-get update -y && \
    apt-get upgrade -y

# Set the env variable DEBIAN_FRONTEND to noninteractive such that no user prompts will be given during package installation process
ENV DEBIAN_FRONTEND noninteractive

# Install Nginx server
RUN \
    # apt-get install -y software-properties-common && \
    # add-apt-repository -y ppa:nginx/stable && \
    # apt-get update && \
    apt-get install -y nginx && \
    apt-get clean -y && \
    # echo "\ndaemon off;" >> /etc/nginx/nginx.conf && \
    chown -R www-data:www-data /var/lib/nginx

# Upstart and DBus have issues inside docker. We work around in order to install firefox.
RUN dpkg-divert --local --rename --add /sbin/initctl && ln -sf /bin/true /sbin/initctl

# Install OS package dependencies required by RVM, and some other useful tools
# and empty the application lists afterwards
RUN apt-get -y install libgdbm-dev libncurses5-dev automake libtool bison libffi-dev libpq-dev sudo && \
    apt-get -y install pwgen curl git && \
    apt-get clean -y && \
    rm -rf /var/lib/apt/lists/*

# Enable passwordless sudo for users under the "sudo" group
RUN sed -i.bkp -e 's/%sudo\s\+ALL=(ALL\(:ALL\)\?)\s\+ALL/%sudo ALL=NOPASSWD:ALL/g' /etc/sudoers

# Install sshpass for username/password based authentication
RUN apt-get update -y && \
    apt-get -y install sshpass && \
    apt-get clean -y

# Copy initial set up scripts
COPY setup.sh /src/
COPY Gemfile /src/

# Expose HTTP port
EXPOSE 80

# Create user, install ruby and required gems
RUN ["/bin/bash", "/src/setup.sh"]

# This is not an executional container, just starting a bash shell
CMD /bin/bash