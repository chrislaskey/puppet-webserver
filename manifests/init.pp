define website (
	$project_name = $title,
	$server_name = "",
	$project_type = "",
	$server_alias = "",
	$webserver = "apache",
	$webserver_ports = "80", # Can specify multiples using a list: ["80", "8080"]
	$additional_webserver_config = "",
	$remote_websites_dir = "/data/available-websites",
	$remote_host = "compnet-nexus.bu.edu",
	$remote_user = "deploy",
	$local_websites_dir = "/data/websites",
	$project_config_dir = ".config",
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
) {

	# Class variables
	# ==========================================================================

	$project_path = "${local_websites_dir}/${project_name}"

	# Transfer project code
	# ==========================================================================

	if ! defined( File[$local_websites_dir] ){
		file { $local_websites_dir:
			ensure => "directory",
			owner => "www-data",
			group => "www-data",
			mode => "0775",
		}
	}

	# Deploy webserver configuration
	# ==========================================================================

	if $webserver == "apache" {

		if $project_type == "" {
			fail("The 'project_type' attribute can not be empty if using Apache webserver. Check website definitions in nodes.pp.")
		}

		if $server_name == "" {
			fail("The 'server_name' attribute can not be empty if using Apache webserver. Check website definitions in nodes.pp.")
		}

		$apache_config_available_dir = "/etc/apache2/sites-available/${project_name}"
		$apache_config_enabled_dir = "/etc/apache2/sites-enabled/${project_name}"

		case $project_type {
			"python": {
				$site_wsgi_file = "${project_path}/${project_name}.wsgi"
				$virtualenv_site_packages = "${project_path}/.meta/virtualenv/lib/python2.7/site-packages"
			}
			"php": {

			}
		}

		file { $apache_config_available_dir:
			ensure => "present",
			content => template("website/apache-site-${project_type}"),
			owner => "root",
			group => "root",
			mode => "0644",
			notify => [
				Exec["apache2-config-reloader-${project_name}"],
			],
		}

		file { $apache_config_enabled_dir:
			ensure => "link",
			target => $apache_config_available_dir,
			require => [
				File[$apache_config_available_dir],
			],
			notify => [
				Exec["apache2-config-reloader-${project_name}"],
				Exec["${project_name}-deploy.sh"],
			],
		}

		if ! defined(File["/etc/apache2/sites-enabled/000-default"]) {
			file { "/etc/apache2/sites-enabled/000-default":
				ensure => "absent",
			}
		}

		exec { "apache2-config-reloader-${project_name}":
			command => "service apache2 reload",
			path => "/bin:/sbin:/usr/bin:/usr/sbin",
			user => "root",
			group => "root",
			logoutput => "on_failure",
			refreshonly => "true",
			subscribe => [
				File[$apache_config_enabled_dir],
			],
			require => [
				File["/etc/apache2/sites-enabled/000-default"],
			],
		}

	}

	# Website deployment and configuration
	# ==========================================================================

	if ! defined( File["${local_websites_dir}/deploy.sh"] ) {
		file { "${local_websites_dir}/deploy.sh":
			ensure => "present",
			content => template("website/deploy-project.sh"),
			owner => "root",
			group => "root",
			mode => "0700",
			require => [
				File["${local_websites_dir}"],
			],
		}
	}

	exec { "${project_name}-deploy.sh":
		command => "${local_websites_dir}/deploy.sh ${project_name}",
		path => "/bin:/sbin:/usr/bin:/usr/sbin",
		user => "root",
		group => "root",
		logoutput => "on_failure",
	}

	if $backup == True {

		if ! defined( File["/data/puppet/pre-backup"] ) {
			file { "/data/puppet/pre-backup":
				ensure => "directory",
				owner => "root",
				group => "root",
				mode => "0700",
			}
		}

		if ! defined( File["/data/puppet/pre-backup/pre-backup.sh"] ) {
			file { "/data/puppet/pre-backup/pre-backup.sh":
				ensure => "present",
				source => "puppet:///modules/website/pre-backup.sh",
				owner => "root",
				group => "root",
				mode => "0700",
			}
		}

		if ! defined( File["/data/puppet/backup"] ) {
			file { "/data/puppet/backup":
				ensure => "present",
				source => "puppet:///modules/website/backup", # The 'files' dir is omitted
				recurse => true, # Transfer directory files too
				purge => true, # Remove client files not found on puppetmaster dir
				force => true, # Remove client dirs not found on puppetmaster dir
				owner => "root",
				group => "root",
				mode => "0700",
				require => [
					File["/data/puppet"],
				],
			}
		}

		cron { "${project_name}-backup-cron":
			command => "/data/puppet/pre-backup/pre-backup.sh -p ${project_path}; /data/puppet/backup/roundrobinbackup.py ${project_path}/ ${backup_user}@${backup_remote_server}:${backup_remote_dir}/${project_name}/backup --ssh-port ${backup_remote_ssh_port} --ssh-identity-file /home/${backup_user}/.ssh/${backup_remote_server} --days ${backup_days} --weeks ${backup_weeks} --months ${backup_months} --years ${backup_years} --exclude .git*",
			user => root,
			minute => $backup_cron_minute,
			hour => $backup_cron_hour,
			weekday => $backup_cron_weekday,
			monthday => $backup_cron_monthday,
			month => $backup_cron_month,
			require => [
				File["/data/puppet/backup"],
			],
		}
	}

}
