# This Berksfile helps resolve dependencies of all cookbooks 
# to undergo the kitchen test.
#
# 1) The cookbooks should be pre-loaded from their various sources
# 2) Apply 'berks install' to resolve dependencies listed in the metadata.rb file of the cookbooks to the cache
# 3) The resolved dependencies can then be copied from the cache location (.berkshelf/cookbooks)
# 
# Author: ruifengm@sg.ibm.com
# Date: 2-Jun-2017

# [Chef Doc] A source defines where Berkshelf should look for cookbooks. Not relevant here, but we just keep it.
source "https://supermarket.chef.io"

# [Chef Doc] The metadata keyword causes Berkshelf to process the local cookbook metadata. 
# [Chef Doc] The Berksfile needs to be placed in the root of the cookbook, next to metadata.rb when used. 
# metadata

# [Chef Doc] The cookbook keyword allows the user to define where a cookbook is installed from, or to set additional version constraints.
# The Berksfile should be placed within the cookbooks folder
# List out all cookbooks for Berkshelf to manage and check dependencies
Dir[File.expand_path('../*', __FILE__)].each do |path|
  File.directory?(path) ? cookbook(File.basename(path), path: path) : nil
end
cookbook "yum" # not sure why it won't be graphed in the Berksfile.lock from the dependency specified in the metadata.rb of policy_linux_mongodb, so had to specifically put here...

# [Chef Doc] Adding cookbooks to a group is useful should you wish to exclude certain cookbooks from upload or vendoring.
# Cookbooks which can be exempted from Berks check
# Below cookbooks are retrieved from ccssd-resources with multiple versions and they can be excluded from the check.
group :exempt do
  # cookbook "logrotate"
  # cookbook "poise"
  # cookbook "sudo"
  # cookbook "windows"
  # cookbook "yum"
end
