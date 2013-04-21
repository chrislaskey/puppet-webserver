#!/usr/bin/env bash

# This file should only be executed by the puppetmaster.

# If .config/mysql exists in project
#	If database-backup dir exists
#		if git repo exists, get git archive (no .git dir). Deploy. Then rm temporary deploy file.
#		else, ssh/tar dir
#	Execute .config/mysql file based on table version.

# Note: When executing remote ssh <host> '<command>', single quotes mean
# variables are evaluated on the remote host. Double quotes means variables
# are evaluated before executing remote ssh command, in current machine's
# local bash variable scope.

# TODO: Clean up project file permissions using blanket www-data chown for all project files via deploy script.
# Then finer grained individual file control using application specific post-hooks called by deploy script.
# NOTE: is this still needed now that git pulls with www-data as local file owner?

this_file=`basename "$0"`
original_dir=`dirname "$0"`
echo $original_dir

project_name=$1
project_path="<%= local_websites_dir %>"
project_dir="${project_path}/${project_name}"
project_config_dir="${project_dir}/<%= project_config_dir %>"
project_is_new="false"
mysql_root_envvars="/data/mysql/mysql_envvars.sh"
tmpdir="${project_dir}-tmp"

remote_user="<%= remote_user %>"
remote_host="<%= remote_host %>"
remote_path="<%= remote_websites_dir %>"
remote_dir="${remote_path}/${project_name}"
code_dir="${remote_dir}/files"
backup_dir="${remote_dir}/backup/latest"

deploy_user="deploy"

git_remote="${remote_user}@${remote_host}:${code_dir}"
git_code_branch="live"
git_file_backup_branch="master"

post_deploy_file_user="www-data"
post_deploy_file_group="www-data"

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
	if [[ -d "$tmpdir" ]]; then
		rm -r "$tmpdir"
	fi
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

# Environment setup

# The programming logic for this section is:
# Exit early if none of the project directories exist on remote location.
#	May also signal connection issues. Better to quit early and prevent
#	unstable states by going further and erroring out later.
# If project dir is empty or does not exist on the local computer.
#	Mark as new project.
#	Create project dir.
confirm_remote_connection_works () {
	if ! sudo -u "$deploy_user" ssh "$remote_host" "/bin/true"; then
		error "Could not create remote connection over ssh. Make sure local user '${deploy_user}' has a SSH key and SSH config for '${remote_host}'. If using Puppet the SSH key setup requires multiple runs. Execute 'puppet agent --test' on both the Puppet master and this client a few times before troubleshooting."
	fi
}

confirm_remote_connection_ssh_key () {
	if ! sudo -u "$deploy_user" ssh "$remote_host" "/bin/true"; then
		error "Could not create remote connection over ssh. Make sure local user '${deploy_user}' has a SSH key and SSH config for '${remote_host}'. If using Puppet the SSH key setup requires multiple runs. Execute 'puppet agent --test' on both the Puppet master and this client a few times before troubleshooting."
	fi
}

confirm_remote_project_exists () {
	if ! sudo -u "$deploy_user" ssh "$remote_host" "test -d ${remote_dir}"; then
		error "Could not find any record of project on remote server, '${remote_host}' 'test -d ${remote_dir}'. If directory does exist on remote server, make sure all files are owned by user '${remote_user}'"
	fi
}

check_if_project_is_new () {
	if [[ -n `ls -A "${project_dir}"` ]] ; then
		project_is_new="true"
	fi
}

create_project_directory() {
	mkdir -p "$project_dir"
	chown -R "$deploy_user":"$deploy_user" "$project_dir"
}

## Import backup files

# Backup-files directory is a backup of all live production files, including
# the files that are not included in the code's git repository (for example
# user-uploaded .pdf files). Backup schedule is handled with a cron-job and
# stored using a git repository on the remote server (see puppetmaster).
#
# When importing backup files it is important to not include the backup
# system's git repository. It is a backup repository, and should only be
# managed and tracked on the remote server - in essence it's a rsync on a
# schedule, but instead of multiple separate timestamped and zipped files
# git is used to provide one single interface.
#
# If the project has a git repository for code changes, these will be
# imported on top of these back up files in the next section, effectively
# leaving only the files that are not tracked in the code repository.

# The programming logic for this section is:
# If project is new to this server and ./backup dir exists, then:
#	If git repo exists on the remote, copy files, omitting the .git directory
#	Else, copy files using rsync

_transfer_exisiting_backup_files_with_rsync_or_create_backup_dir () {
	if sudo -u "$deploy_user" ssh "$remote_host" "test ! -d ${backup_dir} && mkdir -p ${backup_dir}"; then
		log "NOTICE" "Created remote backup directory, ssh '$remote_host' 'test ! -d ${backup_dir} && mkdir -p ${backup_dir}'."
	fi

	if ! sudo -u "$deploy_user" rsync -az "${remote_host}:${backup_dir}/" "$project_dir"; then
		error "Could not import backup files from remote directory, rsync -a '${remote_host}:${backup_dir}/' '$project_dir'."
	fi
}

import_backup_files_if_new () {
	if [[ "$project_is_new" == "true" ]]; then
		return 0
	fi
	_transfer_exisiting_backup_files_with_rsync_or_create_backup_dir
}

# Update code

# This section updates the code used on the website. Primarily used for
# projects where code is kept in a git repository and updated independently
# from user generated site content (like uploaded PDF files). This section
# works with file backups to created a fully working application. User data
# sections being pulled from ./backups should be ommitted from the code
# repository using .gitignore.
#
# In the absence of file backups this will clone, configure, and pull in
# the latest code from the remote server.
#
# In the future this will support rollback upon testing failures.
#
# If code dir exists
#	if git, setup repository and git pull
#	else, ssh/tar dir

_git_clone_repository () {
	if [[ -d "${project_dir}/.git" ]] ; then
		log "Notice: " "Repository already setup. Skipping remote git clone."
		return 0
	fi

	# Can't clone into an existing directory. Clone to temp, transfer .git
	# dir, then checkout latest files into working directory.
	cd "$project_path" # Fixes obscure git bug where git must be able to read cwd in order to `git clone` even if the target is elsewhere
	if ! sudo -u "$deploy_user" git clone -b $git_code_branch $git_remote "$tmpdir"; then
		error "Could not clone remote code repository, git clone -b $git_code_branch $git_remote '$tmpdir'"
	fi
	cd "$original_dir"

	if ! mv "${tmpdir}/.git" "${project_dir}/.git"; then
		error "Could not move git directory from temporary git clone to project directory, '${tmpdir}/.git' '${project_dir}/.git'."
	fi

	if ! rm -r "$tmpdir"; then
		error "Could not rm temporary git clone directory, rm '$tmpdir'."
	fi

	cd "$project_dir"
	if ! sudo -u "$deploy_user" git checkout -- .; then
		error "Could not checkout git files into working directory after setting up git clone, 'git checkout -- .'."
	fi
	cd "$original_dir"
}

_git_configure_remote () {
	# Git remote "origin" will be properly set during git clone. This function allows renaming
	# of git remote branch address if the remote fqdn changes.
	# Note: -n flag uses cached version of git remote, saving a server check.
	set +o nounset
	current_remote=`git remote show -n origin | grep "Fetch URL" | awk -F': ' '{print $2}'`
	set -o nounset

	if [[ "$current_remote" != "$git_remote" ]]; then
		log "Notice:" "Updating git remote. Current remote does not match specified git remote: '${current_remote}' '${git_remote}'"

		if ! git remote rm origin; then
			error "Could not remove old git remote branch origin."
		fi

		if ! sudo -u "$deploy_user" git remote add -t $git_code_branch --tags origin $git_remote; then
			error "Could not add new git remote branch origin."
		fi
	fi
}

_git_update_from_remote () {
	# The fetch then reset strategy accomplishes the same as a git pull, but
	# unlike git pull will not fail if files have been updated on the client.
	# Instead, these unauthorized changes will be thrown away and updated
	# with the latest files from the git repository.
	# See: http://stackoverflow.com/questions/1125968/force-git-to-overwrite-local-files-on-pull
	if ! sudo -u "$deploy_user" git fetch --all; then
		error "Could not fetch git live branch from remote. Make sure remote repository has branch: '${git_code_branch}'."
	fi

	if ! sudo -u "$deploy_user" git reset --hard "origin/$git_code_branch"; then
		error "Could not reset git branch to latest remote branch."
	fi
}

_git_checkout_version () {
	# TODO: Add in version, e.g. "${git_code_branch}~1"
	# NOTE: Do not checkout ${git_code_branch}~0. Make sure to just do $git_code_branch if 0.
	if ! sudo -u "$deploy_user" git checkout $git_code_branch; then
		error "Could not checkout git live branch locally, branch: '${git_code_branch}'."
	fi
}

_update_code_with_git () {
	_git_clone_repository
	cd "$project_dir"
	_git_configure_remote
	_git_update_from_remote
	_git_checkout_version
	cd "$original_dir"
}

_transfer_code_with_rsync () {
	if ! sudo -u "$deploy_user" rsync -a "${remote_host}:${code_dir}/" "$project_dir"; then
		error "Could not export code from remote directory, rsync -a '${remote_host}:${code_dir}/' '$project_dir'."
	fi
}

_update_code_with_rsync_only_if_needed () {
	if [[ -z `ls -A "${project_dir}"` ]]; then
		# Only import new files if there was no backup transferred.
		_transfer_code_with_rsync
	fi
}

update_project () {
	if sudo -u "$deploy_user" ssh "$remote_host" "test -d ${code_dir}/.git"; then
		_update_code_with_git
	else
		_update_code_with_rsync_only_if_needed
	fi
}

# Configure code

_set_default_file_ownership () {
	if ! chown -R "${post_deploy_file_user}:${post_deploy_file_group}" "$project_dir"; then
		error "Could not switch file ownership from deploy user to post deploy user:group: '${deploy_user}' to '${post_deploy_file_user}:${post_deploy_file_group}'"
	fi
}

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
	_set_default_file_ownership
	# TODO: Add a boolean variable to track if either file backup or update pulled in files. Then execute if true.
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
confirm_remote_connection_works
confirm_remote_project_exists
check_if_project_is_new
create_project_directory
import_backup_files_if_new
update_project
configure_project
update_and_configure_mysql
