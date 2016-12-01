#!/bin/bash

set -o errexit # exit on command failure
set -o pipefail # pipes fail when any command fails, not just the last one
set -o nounset # exit on use of undeclared var
#set -o xtrace

if [ $# -gt 4 ]; then
  echo "Usage: $0 [<repo> [<basedir> [<cachedir>] [<hooksdir>]]]"
  echo "  repo defaults to \`.\`"
  echo "  basedir defaults to \`environments\`"
  echo "  cachedir defaults to \`\${basedir}/.cache\`"
  echo "  hooksdir defaults to \`/etc/r11k/hooks.d\`"
  exit 64 # EX_USAGE
fi

REPO="${1:-.}"
BASEDIR="${2:-environments}"
CACHEDIR="${3:-${BASEDIR}/.cache}"
HOOKSDIR="${4:-/etc/r11k/hooks.d}"
CHANGE_COUNTER=0

SCRATCH="$( mktemp -d 2>/dev/null || mktemp -d -t 'r11k' )"
function cleanup {
	rm -rf "$SCRATCH"
}
trap cleanup EXIT

exec 3>&1 # So we can output to stdout from within backticks

function ensure_directory {
	if [ -e "$1" -a ! -d "$1" ]; then
		echo "\`$1\` already exists but is not a directory"
		exit 65 # EX_DATAERR
	elif [ ! -e "$1" ]; then
		mkdir -p "$1"
	fi
}

function escape_repo {
	echo -n "$1" | perl -pe 's@([^a-zA-Z0-9-])@sprintf "_%02x", ord($1)@ge;'
}

function git_mirror {
	REPO="$1"
	EREPO="$( escape_repo "$REPO" )"
	if [ ! -d "$CACHEDIR/$EREPO" ]; then
		if ! git clone --mirror "$REPO" "$CACHEDIR/$EREPO"; then
			return 1
		fi
	fi
	echo "$CACHEDIR/$EREPO"
	touch "$SCRATCH/refreshed"
	if ! grep -q "$EREPO" "$SCRATCH/refreshed"; then
		echo "Updating $REPO" >&3
		(
			cd "$CACHEDIR/$EREPO"
			if ! git remote update --prune >/dev/null; then
				return 1
			fi
		)
		echo "$EREPO" >> "$SCRATCH/refreshed"
	fi
}

ensure_directory "$BASEDIR"
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

function do_submodules {
	git submodule init
	git submodule sync >/dev/null
	git submodule | awk '{print $2}' | while read mod; do
		echo "${FONT_GREEN}Checking out submodule ${FONT_NORMAL}${FONT_GREEN_BOLD}${branch}${FONT_NORMAL}${FONT_GREEN}/${mod}${FONT_NORMAL}"

		URL="$( git config --get "submodule.${mod}.url" )"
		LOCAL="$( git_mirror "${URL}" )"
		if [ $? -ne 0 ]; then
			return 1
		fi

		git submodule update --reference "${LOCAL}" "${mod}"
		(
			cd "${mod}"
			#do_submodules # recurse down
		)
	done
}

while read branch; do
	branch_envname="$(sed -e 's/\//__/g' <<<"$branch")"
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
	fi
	(
		cd "${BASEDIR}/${branch_envname}"
		git remote set-url origin "$MASTER_GIT_DIR"
		git fetch origin "$branch"
		git reset --hard "origin/$branch"
		if ! do_submodules; then
			echo "${FONT_RED}Could not check out branch ${branch}, removing...${FONT_NORMAL}"
			cd "${BASEDIR}"
			rm -rf "${branch_envname}"
		fi
	)
done < <(GIT_DIR="$MASTER_GIT_DIR" git show-ref --heads | sed 's%.\{40\} refs/heads/%%')

while read dir; do
	if ! grep -q "$dir" "$SCRATCH/branches"; then
		echo "${FONT_GREEN_BOLD}Removing non-existant branch ${dir}${FONT_NORMAL}"
		rm -rf "$BASEDIR/$dir"
    let CHANGE_COUNTER+=1
	fi
done < <(cd "$BASEDIR"; ls -1)

# if CHANGE_COUNTER > 0, run the all the hooks found in $HOOKSDIR
if [ -d $HOOKSDIR ]; then
  if [ ${CHANGE_COUNTER} -gt 0 ]; then
    for SCRIPT in `ls ${HOOKSDIR}`; do
      # run script
      ${HOOKSDIR}/${SCRIPT}
    done
  fi
else
  echo "HOOKSDIR ${HOOKSDIR} not found"
fi
