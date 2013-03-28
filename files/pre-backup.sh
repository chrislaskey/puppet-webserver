#!/usr/bin/env bash

this_file=`basename "$0"`

project_path=
parse_options () {
	while getopts "p:" opt; do
		case $opt in
			p)
				project_path=$OPTARG
				;;
		esac
	done
} ; parse_options $@

mysql_root_envvars="/data/mysql/mysql_envvars.sh"
project_config_dir=".config"
project_config_path="${project_path}/${project_config_dir}"

set -o nounset
set -o errtrace
set -o errexit
set -o pipefail

# Utility functions

log () {
	printf "$*\n"
}

error () {
	log "ERROR: " "$*\n"
	exit 1
}

help () {
	echo "Usage is './${this_file} -p <project-path>'"
}

# Environment functions

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
	if [[ -z ${project_path} ]] ; then
		help
		exit 1
	fi
}

verify_environment () {
	verify_root_privileges
	verify_input
}

# Application functions

confirm_config_dir_exists () {
	if [[ ! -d "$project_config_path" ]]; then
		log "No config directory found, exiting ${this_file} script without error: '${project_config_path}'."
	fi
}

# MySQL Backup Functions

_execute_mysql_dump () {
	database="$1"
	output_file="$2"
	if ! touch "$output_file"; then
		error "Could not create mysql dump output file '${output_file}' for database '${database}'."
	fi

	if [[ ! -f "${mysql_root_envvars}" ]]; then
		error "Could not backup mysql database, MySQL root variables could not be sourced '${mysql_root_envvars}'."
	fi
	source "$mysql_root_envvars"
	
	mysql_connection_options="-u ${mysql_root_user} -p${mysql_root_password}"
	mysql_dump_options="--add-drop-table --extended-insert --quick --set-charset"
	if ! mysqldump $mysql_connection_options $mysql_dump_options $database > "$output_file"; then
		error "Failed to create mysqldump: '$mysql_connection_options $mysql_dump_options $database > $output_file'."
	fi
}

_backup_mysql_database () {
	db_directory="$1"
	db_name=`head -n 1 "${db_directory}/name"`
	db_output_file="${db_directory}/data.sql"
	_execute_mysql_dump "$db_name" "$db_output_file"
}

create_backups_of_any_mysql_databases () {
	for dir in `find "${project_config_path}" -maxdepth 1 -type d | grep --color=never mysql*`; do
		_backup_mysql_database "$dir"
	done
}

# Application execution

verify_environment
confirm_config_dir_exists
create_backups_of_any_mysql_databases

# TODO: create sqlite backups
