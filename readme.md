About
================================================================================

A custom puppet module for managing websites on Ubuntu webservers. This module
is a meta-module, combining many projects such as webserver configuration under
one umbrella module.

**Note** The deploying of files from a remote server, and website specific
setup and configuration has been removed in version 0.9.0. See the
[puppet-deploy](https://github.com/chrislaskey/puppet-deploy) module for that functionality.

**Note** The round robin backup of files from a remote server, and website
specific setup and configuration has been removed in version 0.10.0. See the
[puppet-backup](https://github.com/chrislaskey/puppet-backup) module for that functionality.

Default arguments for 0.10.0 include:

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

Module Roadmap
-------

The various functionalities of this meta module will be broken off into their
own puppet modules.

The website file transfer and website configuration was split off
into puppet-deploy in version 0.9.0.

The round-robin backup functionality was split off into puppet-backup in
version 0.10.0.

The webserver functionality is scheduled to be split off into a new puppet
module in version 0.11.0.

After version 0.11.0 this module will either be entirely deprecated or become
a meta-wrapper containing only calls to other puppet modules.

License
================================================================================

All code written by me is released under MIT license. See the attached
license.txt file for more information, including commentary on license choice.
