#!/bin/bash

set -o errexit # exit on command failure
set -o pipefail # pipes fail when any command fails, not just the last one
set -o nounset # exit on use of undeclared var
#set -o xtrace

if [ $# -gt 3 ]; then
	echo "Usage: $0 [<repo> [<basedir> [<cachedir>]]]"
	echo "  repo defaults to \`.\`"
	echo "  basedir defaults to \`environments\`"
	echo "  cachedir defaults to \`\${basedir}/.cache\`"
	exit 64 # EX_USAGE
fi

REPO="${1:-.}"
BASEDIR="${2:-environments}"
CACHEDIR="${3:-${BASEDIR}/.cache}"

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
		git clone --mirror "$REPO" "$CACHEDIR/$EREPO"
	fi
	echo "$CACHEDIR/$EREPO"
	touch "$SCRATCH/refreshed"
	if ! grep -q "$EREPO" "$SCRATCH/refreshed"; then
		echo "Updating $REPO" >&3
		(
			cd "$CACHEDIR/$EREPO"
			git remote update --prune >/dev/null
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
	FONT_NORMAL="$(echo -e "\x1b[39;49m")"
else
	FONT_GREEN=""
	FONT_NORMAL=""
fi

function do_submodules {
	git submodule init
	git submodule sync >/dev/null
	git submodule | awk '{print $2}' | while read mod; do
		URL="$( git config --get "submodule.$mod.url" )"
		LOCAL="$( git_mirror "$URL" )"
		echo "${FONT_GREEN}Checking out submodule $branch/$mod${FONT_NORMAL}"
		git submodule update --reference "$LOCAL" "$mod"
		(
			cd "$mod"
			#do_submodules # recurse down
		)
	done
}

GIT_DIR="$MASTER_GIT_DIR" git show-ref --heads |
	sed 's%.\{40\} refs/heads/%%' | # strip of hash and refs/heads/ prefix
	while read branch; do
	echo "$branch" >> "$SCRATCH/branches"
	echo "${FONT_GREEN}Checking out branch $branch${FONT_NORMAL}"

	# `git worktree` is not usable with submodules: the submodule URL is saved
	# in the $GIT_COMMON_DIR/config, which is common for all workdir's (git
	# v2.5.0)

	if [ ! -e "$BASEDIR/$branch/.git" ]; then
		# Not a git repo, remove it, so it will be created below
		rm -rf "$BASEDIR/$branch"
	fi
	if [ ! -e "$BASEDIR/$branch" ]; then
		git clone --reference "$MASTER_GIT_DIR" --shared \
			-b "$branch" "$MASTER_GIT_DIR" "$BASEDIR/$branch"
	fi
	(
		cd "$BASEDIR/$branch"
		git remote set-url origin "$MASTER_GIT_DIR"
		git fetch origin "$branch"
		git reset --hard "origin/$branch"
		do_submodules
	)
done

( cd "$BASEDIR"; ls -1 ) | while read dir; do
	if ! grep -q "$dir" "$SCRATCH/branches"; then
		echo "Removing non-existant branch $dir"
		rm -rf "$BASEDIR/$dir"
	fi
done
