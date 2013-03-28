About
================================================================================

A custom puppet module for deploying websites to Ubuntu webservers. This module
is a meta-module, combining many projects such as deployment, backup, and
Puppet configuration scripts under one umbrella module.

Default arguments for 0.8.0 include:

		$project_name = $title,
		$server_name = "",
		$project_type = "",
		$server_alias = "",
		$webserver = "apache",
		$webserver_ports = "80", # Can specify multiples using a list: ["80", "8080"]
		$additional_webserver_config = "",
		$websites_dir = "/data/websites",
		$backup = True,
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

Deploy Script
-------------

This module includes a project deployment shell script that:

	- Transfers files intelligently from a mix of live-data backups and
	  git repository files.
	- Sets up PHP and Python environments, including `setup.sh` and `setup.sh`
	  scripts.
	- Creates MySQL database, including database creation, user creation,
	  schema checks, and data importing.

Future revisions will include post-install smoke tests and SQLite support.

# Server Filesystem #

Available projects are stored on the puppet server in the following configuration:

	available-websites/my-project
	available-websites/my-project/files/ # Git repository or flat files
	available-websites/my-project/backup/
	available-websites/my-project/backup/latest/
	available-websites/my-project/backup/automated-backup-2013-01-01.tar.gz
	available-websites/my-project/backup/automated-backup-2012-01-01.tar.gz

Inside the `my-project/files` directory should be a current group of files
and/or a git repository of files.

The backup script will create the `backup/`, put the latest files in
`backup/latest`, and create archives based on a round-robin backup scheme and
Puppet parameters passed to the class.

# Project Filesystem #

The project files should include a `.config` directory. This contains meta
information about the project, including information on how to deploy. It may
contains directories such as:

	.config/
	.config/mysql-appusers/
	.config/mysql-appdata/
	.config/scripts/

Where a `mysql-*` directory includes the filels:

	.config/mysql-appusers/database.sql
	.config/mysql-appusers/name
	.config/mysql-appusers/schema.sql
	.config/mysql-appusers/users.sql

**Note:** If there is only one database, then the dir can simply be called
`mysql`.

The `scripts/` directory stores pre-deploy, post-deploy, and post-deploy smoke
test scripts.

Backup Script
-------------

A custom puppet-compatable push-based round-robin automated file backup system
is included. See the
[round-robin-backup.py](https://github.com/chrislaskey/round-robin-backup.py)
github repository for more information on the backup script, and see above for backup
related passable class parameters in Puppet.

Also includes a `pre-backup.sh` script for creating live-data information
backups, such as MySQL database backups, before the round robin backup is run.

License
================================================================================

All code written by me is released under MIT license. See the attached
license.txt file for more information, including commentary on license choice.
