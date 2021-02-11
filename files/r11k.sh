#!/bin/bash
## File managed by puppet
#  * module: r11k
#  * file: r11k.sh

set -o errexit # exit on command failure
set -o pipefail # pipes fail when any command fails, not just the last one
set -o nounset # exit on use of undeclared var
#set -o xtrace

DEFAULT_REPO="."
DEFAULT_BASEDIR="environments"
DEFAULT_HOOKSDIR="/etc/r11k/hooks.d"
DEFAULT_ENVHOOKSDIR="/etc/r11k/env.hooks.d"
DEFAULT_PRODUCTION_BRANCH="production"

LOCK="fail"

function _help() {
	cat <<EOHELP
USAGE: $0 [options] [repo]

ARGUMENTS:

	[repo]                  Clone of the git repo to map in the basedir.
							Defaults to \`${DEFAULT_REPO}\`

OPTIONS:

	-b,--basedir            Target base directory.
							Defaults: \`${DEFAULT_BASEDIR}\`
	-c,--cachedir           Directory to use for caching the git repositories
							(Including the found submodules).
							Defaults to a subfolder \`.cache\` in the basedir.
	-k,--hooksdir           Directory with hooks to run after all branches have been
							deployed.
							Default: \`${DEFAULT_HOOKSDIR}\`
	-e,--envhooksdir        Directory with hooks to run after an environment had
							any changes.
							Default: \`${DEFAULT_ENVHOOKSDIR}\`
	-p,--production_branch  Branch name to use as production.
							This branch will be created as 'production' environment.
							Do NOT include 'production' in --include when using this option.
	-f,--flush_cache_cmd	Command to flush the puppet environment cache. Used only if set.
	-i,--include            Branch or regex of branches to map. You can repeat this
							option to include multiple branches/filters or provide
							a list separated by colon \`:\`.  Defaults to
							all found branches in the repository.
	-h,--help               Display this message and exit.
	-w,--no-wait            Don't wait for another r11k run to finish, but fail
							immediately if another run is detected.

ENVIRONMENT:

	R11K_BASEDIR                    Sets the default basedir to use.
	R11K_CACHEDIR                   Sets the default cache dir to use.
	R11K_HOOKSDIR                   Sets the default hooks dir to use.
	R11K_ENVHOOKSDIR                Sets the default environments hooks dir to use.
	R11K_PRODUCTION_BRANCH          Sets the branch to promote to production branch.
	R11K_FLUSH_PUPPET_CACHE_COMMAND Sets the command to flush the puppet environment cache.
	R11K_INCLUDES                   A colon separated list with branches/filters to use.

EOHELP
}

## getopt parsing
if `getopt -T >/dev/null 2>&1`; [ $? = 4 ]; then
  true # Enhanced getopt.
else
  echo "Could not find an enhanced \`getopt\`. You have $(getopt -V)"
  exit 69 # EX_UNABAILABLE
fi

## No options = show help + exit EX_USAGE
if GETOPT_TEMP="$( getopt --shell bash --name "$0" \
	-o b:c:k:e:p:f:i:hw \
	-l basedir:,cachedir:,hooksdir:,envhooksdir:,production_branch:,flush_cache_cmd:,include:,help,no-wait \
	-- "$@" )"; then
	eval set -- "${GETOPT_TEMP}"
else
	exit 64
fi;

declare -a CMD_INCLUDES=()
while [ $# -gt 0 ]; do
	case "${1}" in
		-b|--basedir)           R11K_BASEDIR="${2}"; shift 2;;
		-c|--cachedir)          R11K_CACHEDIR="${2}"; shift 2;;
		-k|--hooksdir)          R11K_HOOKSDIR="${2}"; shift 2;;
		-e|--envhooksdir)       R11K_ENVHOOKSDIR="${2}"; shift 2;;
		-p|--production_branch) R11K_PRODUCTION_BRANCH="${2}"; shift 2;;
		-f|--flush_cache_cmd)   R11K_FLUSH_PUPPET_CACHE_COMMAND="${2}"; shift 2;;
		-i|--include)           IFS=: read -ra NEW_INCLUDES <<<"${2}"
								CMD_INCLUDES+=("${NEW_INCLUDES[@]}");
								shift 2;;
		-h|--help)              _help; exit 0;;
		-w|--no-wait)           LOCK="wait"; shift;;
		--)                     shift; break;;
		*)                      break;;
	esac
done

REPO="${R11K_REPO-${DEFAULT_REPO}}"
BASEDIR="${R11K_BASEDIR-${DEFAULT_BASEDIR}}"
DEFAULT_CACHEDIR="${BASEDIR}/.cache"
CACHEDIR="${R11K_CACHEDIR-${DEFAULT_CACHEDIR}}"
HOOKSDIR="${R11K_HOOKSDIR-${DEFAULT_HOOKSDIR}}"
ENVHOOKSDIR="${R11K_ENVHOOKSDIR-${DEFAULT_ENVHOOKSDIR}}"
PRODUCTION_BRANCH="${R11K_PRODUCTION_BRANCH-${DEFAULT_PRODUCTION_BRANCH}}"
FLUSH_PUPPET_CACHE_COMMAND="${R11K_FLUSH_PUPPET_CACHE_COMMAND}"
INCLUDES=("${CMD_INCLUDES[@]:-${R11K_INCLUDES[@]:-}}")

if [ $# -gt 0 ]; then
	REPO="${1}"
	shift
fi

if [ $# -gt 0 ]; then
	echo "Unknown argument(s) left; aborting: $@" >&2
	exit 64
fi

exec 3>&1 # So we can output to stdout from within backticks

function ensure_directory {
	while [ ! -d "$1" ]; do
		if [ -e "$1" -a ! -d "$1" ]; then
			echo "\`$1\` already exists but is not a directory"
			exit 65 # EX_DATAERR
		elif [ ! -e "$1" ]; then
			# Possible race condition here, hence the `||true` and the while-loop
			mkdir -p "$1" || true
		fi
	done
}

function escape_repo {
	echo -n "$1" | perl -pe 's@([^a-zA-Z0-9-])@sprintf "_%02x", ord($1)@ge;'
}

function git_mirror {
	local repo="$1"
	local erepo="$( escape_repo "${repo}" )"
	if [ ! -d "${CACHEDIR}/${erepo}" ]; then
		echo "START Cloning '${repo}' into '${CACHEDIR}/${erepo}'" >&3
		if ! git clone --mirror "${repo}" "${CACHEDIR}/${erepo}"; then
			echo "Git clone failed!!!" >&3
			return 1
		fi
		echo "DONE Cloning '${repo}' into '${CACHEDIR}/${erepo}'" >&3
	fi
	echo "$CACHEDIR/$erepo"
	touch "$SCRATCH/refreshed"
	if ! grep -q "$erepo" "$SCRATCH/refreshed"; then
		echo "START Updating ${repo} into '${CACHEDIR}/${erepo}'" >&3
		(
			cd "${CACHEDIR}/${erepo}"
			if ! git remote update --prune >/dev/null; then
				echo "Git update failed!!!" >&3
				return 1
			fi
		)
		echo "$erepo" >> "$SCRATCH/refreshed"
		echo "DONE Updating ${repo} into '${CACHEDIR}/${erepo}'" >&3
	else
		echo "Repo ${repo} already updated during this r11k run." >&3
	fi
}

# We need to acquire a lock as soon as possible, but we need to create our
# $BASEDIR first.

ensure_directory "$BASEDIR"

LOCKFILE="${BASEDIR}/.lock"
if ( set -o noclobber; echo "$$" > "$LOCKFILE") 2> /dev/null; then
	SCRATCH="$( mktemp -d 2>/dev/null || mktemp -d -t 'r11k' )"
	function cleanup {
		rm -rf "$SCRATCH"
		rm "$LOCKFILE"
	}
	trap cleanup EXIT
else
	echo "Could not create \`${LOCKFILE}\`. Not running."
	exit 75 # TEMPERR
fi

ensure_directory "$CACHEDIR"

CACHEDIR="$( cd "$CACHEDIR"; pwd )" # make absolute path

MASTER_GIT_DIR="$( git_mirror "$REPO" )"

if [ -t 1 ]; then
	FONT_GREEN="$(echo -e "\x1b[32m")"
	FONT_GREEN_BOLD="$(echo -e "\x1b[32;1m")"
	FONT_RED="$(echo -e "\x1b[31m")"
	FONT_NORMAL="$(echo -e "\x1b[39;22;49m")"
else
	FONT_GREEN=""
	FONT_GREEN_BOLD=""
	FONT_RED=""
	FONT_NORMAL=""
fi

function do_submodules() {
	local branch="$1"
	local url lmirror mod
	git submodule init
	git submodule sync >/dev/null
	git submodule | awk '{print $2}' | while read mod; do
		echo "${FONT_GREEN}Checking out submodule ${FONT_NORMAL}${FONT_GREEN_BOLD}${branch}${FONT_NORMAL}${FONT_GREEN}/${mod}${FONT_NORMAL}"

		url="$( git config --get "submodule.${mod}.url" )"
		lmirror="$( git_mirror "${url}" )"
		if [ $? -ne 0 ]; then
			return 1
		fi

		follow_branch="$( git config -f .gitmodules --get "submodule.${mod}.branch" )"
		if [ -n "${follow_branch}" ]
		then
			handle_submodule_with_tracking_branch ${mod} ${follow_branch}
		else
			git submodule update --reference "${lmirror}" "${mod}"
		fi
	done
}

function do_submodules_with_tracking_branch() {
	local follow_branch mod
	git submodule | awk '{print $2}' | while read mod; do
		follow_branch="$( git config -f .gitmodules --get "submodule.${mod}.branch" || echo '')"
		if [ -n "${follow_branch}" ]
		then
			handle_submodule_with_tracking_branch ${mod} ${follow_branch}
		fi
	done
}

function handle_submodule_with_tracking_branch() {
	local url lmirror mod follow_branch repo_path
	mod=$1
	follow_branch=$2

	echo "${FONT_RED}Module '${mod}' has branch '${follow_branch}' configured. Check updates${FONT_NORMAL}"
	repo_path="$( git config -f .gitmodules --get "submodule.${mod}.path" )"
	url="$( git config --get "submodule.${mod}.url" )"
	echo "Using url: ${url}"
	lmirror="$( git_mirror "${url}" )"
	ret=$?
	if [ $ret -ne 0 ]; then
		echo "return code from 'git_mirror ${url}' was $ret !"
		return 1
	fi

	if [ -d "${repo_path}/.git" ]
	then
		echo "${repo_path} is a git repo. Updating."
		(
			cd ${repo_path}
			git fetch
			git checkout ${follow_branch}
			git reset --hard HEAD
			git pull
			commit=$(git rev-parse HEAD)
			echo "Now at git commit ${commit}"
		)
	else
		echo "${repo_path} is NOT a git repo. Recreating."
		rm -rf ${repo_path}
		git clone -b ${follow_branch} ${lmirror} ${repo_path}
		(
			cd ${repo_path}
			commit=$(git rev-parse HEAD)
			echo "Now at git commit ${commit}"
		)
	fi
	echo "ready with module: ${mod}"

}

function translate_branch_to_env() {
	if [ -n "${PRODUCTION_BRANCH}" -a "${1}" == "${PRODUCTION_BRANCH}" ]
	then
		echo 'production'
	else
		echo -n "$1" | perl -pe 's@/@__@g;s@([^a-zA-Z0-9_])@sprintf "_%02x", ord($1)@ge;'
	fi
}

function do_submodules_for_branch() {
	local branch="$1"
	local branch_envname="$(translate_branch_to_env "$branch")"
	local new_branch='false'
	echo "$branch_envname" >> "$SCRATCH/branches"
	echo "${FONT_GREEN_BOLD}Checking out branch ${branch} into ${branch_envname}${FONT_NORMAL}"

	# `git worktree` is not usable with submodules: the submodule URL is saved
	# in the $GIT_COMMON_DIR/config, which is common for all workdir's (git
	# v2.5.0)

	if [ ! -e "$BASEDIR/$branch_envname/.git" ]; then
		# Not a git repo, remove it, so it will be created below
		rm -rf "$BASEDIR/$branch_envname"
	fi
	if [ ! -e "$BASEDIR/$branch_envname" ]; then
		git clone --reference "$MASTER_GIT_DIR" --shared \
			-b "$branch" "$MASTER_GIT_DIR" "$BASEDIR/$branch_envname"
		let CHANGE_COUNTER+=1
		new_branch='true'
	fi
	cd "${BASEDIR}/${branch_envname}"
	git remote set-url origin "${MASTER_GIT_DIR}"
	git remote update --prune
	if [[ -z "$(git status --porcelain -uno)" ]] && [[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/${branch}")" ]] && [[ ${new_branch} == 'false' ]]
	then
		echo "${FONT_GREEN}Branch has no changes. ${FONT_NORMAL}${FONT_GREEN_BOLD}${branch}${FONT_NORMAL}"
		do_submodules_with_tracking_branch
	else
		echo "${FONT_GREEN}Branch is new or has changes! Updating. ${FONT_NORMAL}${FONT_GREEN_BOLD}${branch}${FONT_NORMAL}"
		git fetch origin "$branch"
		git reset --hard "origin/$branch"
		git clean -ffdx --exclude='/.resource_types/' # .resource_types is used by puppet to provide environment isolation (puppet generate types)
		if ! do_submodules $branch; then
			echo "${FONT_RED}Could not check out branch ${branch}, removing...${FONT_NORMAL}"
			cd "${BASEDIR}"
			rm -rf "${branch_envname}"
		fi
		let CHANGE_COUNTER+=1
	fi
}

function collect_branches() {
	local includes
	local tmpfilter="${SCRATCH}/filter_branches.txt"
	if [ ${#INCLUDES} -eq 0 ]; then
		GIT_DIR="$MASTER_GIT_DIR" git show-ref --heads | sed 's%.\{40\} refs/heads/%%'
	else
		for include in "${INCLUDES[@]}"; do
			GIT_DIR="$MASTER_GIT_DIR" git show-ref --heads | sed 's%.\{40\} refs/heads/%%' | \
				{ grep -e "^${include}\$" || true; } >> "$tmpfilter"
		done
		cat "${tmpfilter}" | sort -u
	fi
}

function run_hooks() {
	local hookdir="$1"
	shift
	local args="${@}"
	[ -d "${hookdir}" ] || return
	for SCRIPT in `ls "${hookdir}"`; do
		if [ -x ${hookdir}/${SCRIPT} ]; then
			set +e
			${hookdir}/${SCRIPT} ${args[@]}
			exitcode=$?
			set -e
			if [ $exitcode -gt 0 ]; then
				echo "script ${hookdir}/${SCRIPT} failed with exitcode ${exitcode}"
				exit 1;
			fi
		fi
	done
}

function clear_puppet_cache() {
	local env="$1"
	if [[ -f "${FLUSH_PUPPET_CACHE_COMMAND}" && -x $(realpath "${FLUSH_PUPPET_CACHE_COMMAND}") ]]; then
		${FLUSH_PUPPET_CACHE_COMMAND} ${env}
	fi
}

BRANCHES=( "$( collect_branches )" );
CHANGE_COUNTER=0

if [ ${#BRANCHES} -eq 0 ]; then
	echo "No branches found to checkout"
	exit 66;
fi;

echo "Branches to 'manage'"
echo '--------------------'
echo "${BRANCHES[@]}"
echo '--------------------'

# Map branches to environments
PREV_COUNTER="${CHANGE_COUNTER}"
while read branch; do
	echo "Start managing branch: ${branch}"
	do_submodules_for_branch "$branch"
	if [ $PREV_COUNTER -ne $CHANGE_COUNTER ]; then
		echo "${FONT_GREEN}Running environment hooks ${FONT_GREEN_BOLD}${branch}${FONT_NORMAL}"
		run_hooks "${ENVHOOKSDIR}" "$branch" "$( translate_branch_to_env "${branch}" )"
		clear_puppet_cache "$( translate_branch_to_env "${branch}" )"
		PREV_COUNTER="${CHANGE_COUNTER}"
	fi
	echo "Done managing branch: ${branch}"
done <<<"${BRANCHES[@]}"

# Cleanup old environments
while read dir; do
	if ! grep -q "${dir}$" "$SCRATCH/branches"; then
		echo "${FONT_GREEN_BOLD}Removing non-existant branch ${dir}${FONT_NORMAL}"
		rm -rf "$BASEDIR/$dir"
		clear_puppet_cache "$dir"
		let CHANGE_COUNTER+=1
	fi
done < <(cd "$BASEDIR"; ls -1)

# if CHANGE_COUNTER > 0, run the all the hooks found in $HOOKSDIR
if [ -d $HOOKSDIR ]; then
	if [ ${CHANGE_COUNTER} -gt 0 ]; then
		echo "${FONT_GREEN}Running post-deploy hooks${FONT_NORMAL}"
		run_hooks "${HOOKSDIR}"	
	fi
else
	echo "WARNING: HOOKSDIR ${HOOKSDIR} not found"
fi

# vim: set ts=4 sw=2 tw=0 noet :
