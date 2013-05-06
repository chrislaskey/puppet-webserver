define website (
	$project_name = $title,
	$server_name = "",
	$project_type = "",
	$server_alias = "",
	$webserver = "apache",
	$webserver_ports = "80", # Can specify multiples using a list: ["80", "8080"]
	$additional_webserver_config = "",
	$local_websites_dir = "/data/websites",
) {

	# Class variables
	# ==========================================================================

	$project_path = "${local_websites_dir}/${project_name}"

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
}
