About
================================================================================

A custom puppet module for managing per-project webserver configurations.
Currently supports Apache.

Default arguments for 1.0.0 include:

		$project_name = $title,
		$server_name = "",
		$project_type = "",
		$server_alias = "",
		$webserver = "apache",
		$webserver_ports = "80", # Can specify multiples using a list: ["80", "8080"]
		$additional_webserver_config = "",
		$local_websites_dir = "/data/websites",

The webserver parameter currently supports Apache configurations for
`Apache+PHP_Fastcgi` and `Apache+Mod_WSGI`.

**Note** This module used to be called `puppet-website`. That module was
a meta-module, containing code related to project deployment, configuration and
backup. This functionality has been split into these three distinct puppet
modules:

[puppet-deploy](http://github.com/chrislaskey/puppet-deploy)
[puppet-webserver](http://github.com/chrislaskey/puppet-webserver)
[puppet-backup](http://github.com/chrislaskey/puppet-backup)

License
================================================================================

All code written by me is released under MIT license. See the attached
license.txt file for more information, including commentary on license choice.
