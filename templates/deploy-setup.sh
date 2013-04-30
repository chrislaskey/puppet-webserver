#!/usr/bin/env bash

# This file should only be executed by the puppetmaster.

this_file=`basename "$0"`
original_dir=`dirname "$0"`

project_name=$1
project_path="<%= local_websites_dir %>"
project_dir="${project_path}/${project_name}"
project_config_dir="${project_dir}/<%= project_config_dir %>"
mysql_root_envvars="/data/mysql/mysql_envvars.sh"

# option_example_one=
# option_example_two=
# parse_options () {
#	while getopts "o:t:" opt; do
#		case $opt in
#			o)
#				option_example_one=$OPTARG
#				;;
#			t)
#				option_example_two=$OPTARG
#				;;
#		esac
#	done
# } ; parse_options $@

set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

log () {
	printf "$*\n"
}

error () {
	log "ERROR: " "$*\n"
	exit 1
}

help () {
	echo "Usage is './${this_file} <project-name>'"
}

# Application functions

before_exit () {
	# Works like a finally statement
	# Code that must always be run goes here
	return
} ; trap before_exit EXIT

verify_root_privileges () {
	if [[ $EUID -ne 0 ]]; then
		fail "Requires root privileges."
	fi
}

verify_input () {
	if [[ -z ${project_name} ]] ; then
		help
		exit 1
	fi
}

verify_environment () {
	verify_root_privileges
	verify_input
}

# Configure code

_after_update_application_scripts () {
	# TODO: Once standardized, look into that project dir E.g.:
	# look into ${project_config_dir}/scripts/after-file-update.sh and execute 
	return 0
}

_reload_if_python_wsgi_app () {
	# Python applications running on Apache/mod_wsgi need to be reloaded after
	# files have been changed. By default WSGIScriptReloading is on, meaning
	# a reload will occur if .wsgi file is touched.
	wsgi_file=`ls -a | grep --color=never \.wsgi$`
	if [[ -n "$wsgi_file" ]]; then
		if ! touch "$wsgi_file"; then
			error "Found Python .wsgi file, but could not reload it with the touch command: '${wsgi_file}'"
		fi
	fi
}

_after_update_reload_scripts () {
	_reload_if_python_wsgi_app
}

configure_project () {
	cd "$project_dir"
	_after_update_application_scripts
	# _after_update_reload_scripts # TODO: Causing deploy script failure
	cd "$original_dir"
}

# Update database

_import_database_file () {
	file="$1"
	set +o nounset
	optional_db_name="$2"
	set -o nounset
	if [[ ! -f "$file" ]]; then
		error "Could not find file to import into mysql: '${file}'"
	fi

	# Note: there must be no space between -p and password.
	if ! mysql -u ${mysql_root_user} -p${mysql_root_password} ${optional_db_name} < $file; then
		error "Could not import mysql file: '${file}'"
	fi
}

_configure_database () {
	db_directory="$1"
	db_name=`head -n 1 "${db_directory}/name"`

	db_file="${db_directory}/database.sql"
	_import_database_file "$db_file"

	if ! mysql -u ${mysql_root_user} -p${mysql_root_password} ${db_name}; then
		error "Could not find database: '${db_name}'. Likely a misconfigured db file: '${db_file}'"
	fi
}

_configure_database_users () {
	db_directory="$1"
	db_name=`head -n 1 "${db_directory}/name"`

	users_file="${db_directory}/users.sql"
	_import_database_file "$users_file"
}

_load_database_data_if_needed () {
	# If a data file exists and the database is schema-less (empty),
	# import data.
	db_directory="$1"
	db_name=`head -n 1 "${db_directory}/name"`

	db_data_file="${db_directory}/data.sql"
	if [[ ! -f "$db_data_file" ]]; then
		return 0
	fi

	tables=`mysql -u ${mysql_root_user} -p${mysql_root_password} -Nse 'SHOW TABLES' ${db_name}`
	if [[ -z "$tables" ]]; then
		_import_database_file "$db_data_file" "$db_name"
		return 0
	fi
}

_load_database_schema_if_needed () {
	# If there was no data file and the database is still schema-less (empty)
	# then import the schema file if it exists.
	db_directory="$1"
	db_name=`head -n 1 "${db_directory}/name"`

	db_schema_file="${db_directory}/schema.sql"
	if [[ ! -f "$db_schema_file" ]]; then
		return 0
	fi

	tables=`mysql -u ${mysql_root_user} -p${mysql_root_password} -Nse 'SHOW TABLES' ${db_name}`
	if [[ -z "$tables" ]]; then
		_import_database_file "$db_schema_file" "$db_name"
		return 0
	fi
}

_update_database_schema_if_needed () {
	# TODO: Get database schema version
	# TODO: Then checkout the latest "${project_config_dir}/mysql/" dir,
	# ensuring the any needed upgrade/downgrade scripts are available.
	# Without this it may not be possible to downgrade from a high schema,
	# for example when the code is an old version and the DB is newest,
	# The old code version will not have latest upgrade/downgrade files.
	# TODO: Then check "${project_config_dir}/mysql/scheme-update*" or
	# "${project_config_dir}/mysql/scheme-downgrade* files.
	return 0
}

update_and_configure_mysql () {
	if [[ ! -f "${mysql_root_envvars}" ]]; then
		return 0
	fi

	source "$mysql_root_envvars"

	if [[ ! -d "${project_config_dir}" ]]; then
		return 0
	fi

	# MySQL files are stored in ${project_config_dir}/mysql* where mysql*
	# could be either: "mysql" or in the case of multiple databases:
	# "mysql-dbname-one mysql-dbname-two ..."
	# For statements return harmlessly when bash command returns non-zero.
	for i in `find "${project_config_dir}" -type d -maxdepth 1 | grep --color=never mysql`; do
		_configure_database "$i"
		_configure_database_users "$i"
		_load_database_data_if_needed "$i"
		_load_database_schema_if_needed "$i"
		_update_database_schema_if_needed "$i"
	done
}

# Application execution

verify_environment
configure_project
update_and_configure_mysql
