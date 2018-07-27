# Kitchen Test

[Kithcen](https://kitchen.ci/docs/getting-started) is a test harness that executes and verifies infrastructure code on one or more platforms in isolation. It's primarily being used to test Chef cookbooks. 

This project contains a customized kitchen test framework running inside a docker container for SLA Chef cookbooks and recipes.

* Trigger test execution on dedicated endpoint servers via either SSH or WinRM
* Collect test results in JSON, process and feed them into reporting tools (save results, manage RTC defects for failed tests, send out Email and Slack notifications and construct consolidated HTML reports)

Containerization makes this test framework portable and reliable for CI with configurations persisted in source control. Initially direct [kitchen test steps](https://docs.chef.io/ctl_kitchen.html#kitchen-test) were invoked inside the container, and later they were replaced by a stantd-alone jar developed separately. This test jar provides better orchestration and multi-thread execution. It invokes VSphere APIs to manage the VMware endpoints used for test. 

## Getting Started
This framework is solely used in continuous integration via a dedicated build server (e.g. Jenkins). 

### Prerequisites
* A Linux server with Docker (>= v1.10) installed
* Chef recipes to be tested
* Dedicated endpoint servers on SoftLayer (or any other VM provider) of different platforms (Linux/Windows etc.)

## Build & Deployment
The `kitchen_build_deploy_jenkins.sh` script is used in a Jenkins job to build up the test container and run it. 


## Authors
* **[Ruifeng Ma](mrfflyer@gmail.com)** - *Initial work*

## Organization
IBM
