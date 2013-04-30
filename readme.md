About
================================================================================

A custom puppet module for managing websites on Ubuntu webservers. This module
is a meta-module, combining many projects such as backup and
webserver configuration under one umbrella module.

**Note** The deploying of files from a remote server, and website specific
setup and configuration has been removed in version 0.9.0. See the
puppet-deploy module for that functionality.

Default arguments for 0.9.0 include:

		$project_name = $title,
		$server_name = "",
		$project_type = "",
		$server_alias = "",
		$webserver = "apache",
		$webserver_ports = "80", # Can specify multiples using a list: ["80", "8080"]
		$additional_webserver_config = "",
		$local_websites_dir = "/data/websites",
		$backup = true,
		$backup_remote_server = $puppetmaster_fqdn,
		$backup_remote_dir = "/data/available-websites",
		$backup_user = "deploy",
		$backup_remote_ssh_port = "2222",
		$backup_days = '6',
		$backup_weeks = '5',
		$backup_months = '6',
		$backup_years = '20',
		$backup_cron_minute = '0',
		$backup_cron_hour = 2, # Can be individual: [2,12,15] or ranged: [2-4,10-14]
		$backup_cron_weekday = '*',
		$backup_cron_monthday = '*',
		$backup_cron_month = '*',

The webserver parameter currently supports Apache configurations for
`Apache+PHP_Fastcgi` and `Apache+Mod_WSGI`.

Backup Script
-------------

A custom puppet-compatable push-based round-robin automated file backup system
is included. See the
[round-robin-backup.py](https://github.com/chrislaskey/round-robin-backup.py)
github repository for more information on the backup script, and see above for backup
related passable class parameters in Puppet.

Also includes a `pre-backup.sh` script for creating live-data information
backups, such as MySQL database backups, before the round robin backup is run.

Module Roadmap
-------

The various functionalities of this meta module will be broken off into their
own puppet modules. The website file transfer and website configuration has
already been split off into puppet-deploy. The backup will receive similar
treatment, as will the webserver functionality. This module will either be
entirely deprecated, or a meta-wrapper containing only calls to sub modules.
There is no set timeline for these changes.

License
================================================================================

All code written by me is released under MIT license. See the attached
license.txt file for more information, including commentary on license choice.
