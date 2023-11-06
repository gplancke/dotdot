#!/bin/bash

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

DELIM="|"
DOTFILE_LOCATION="$HOME/.dotdot"
STORAGE_LOCATION="$HERE"

function write_dotfile_location {
	echo "$1" > "$DOTFILE_LOCATION"
}
function read_dotfile_location {
	echo $(cat "$DOTFILE_LOCATION" | head -n 1)
}
function expand_read_line {
	echo "$(eval echo $1)"
}

function register {
	# First we check if we have info about where to store the registered files
	if [ ! -f "$DOTFILE_LOCATION" ]; then
		mkdir -p "$(dirname "$DOTFILE_LOCATION")"
		touch "$DOTFILE_LOCATION"
	fi

	STORAGE_LOCATION=$(read_dotfile_location)
	if [ -z "$STORAGE_LOCATION" ]; then
		read -r -p "Where do you want to store the registered files? (default: $HERE): " LOCATION
		STORAGE_LOCATION=$(expand_read_line "$LOCATION")
		STORAGE_LOCATION="${STORAGE_LOCATION:-$HERE}"
		write_dotfile_location $STORAGE_LOCATION
	fi

	STORE="$STORAGE_LOCATION/files"
	REGISTER="$STORAGE_LOCATION/register.txt"

	echo "Registering files in $STORE"
	mkdir -p $STORE
	touch "$REGISTER"

	local file="$1"
	local realFileToTrack=$(readlink -f $file)
	local fileToTrack="${realFileToTrack//$HOME\/}"

	if [ "$realFileToTrack" = "$fileToTrack" ]; then
		echo "File is not in home directory, cannot track it"
	else
		local srcDirName="$(dirname $fileToTrack)"
		local srcFileName="$(basename $fileToTrack)"
		local infoLine="${srcFileName}${DELIM}${srcDirName}"
		# local isHidden=$([[ "$srcFileName" =~ ^\\\. ]] && echo "1" || echo "0")
		# local visibleName=$([ "$isHidden" = "1" ] && echo "${srcFileName:1}" || echo "$srcFileName")
		local sedSafe=$(echo "$srcFileName" | sed -E -e 's/\./\\./g')

		# Copying file to store
		cp -r $realFileToTrack $STORE
		# Removing duplicates from register before adding
		sed -i '' -E -e "/^${sedSafe}/d" $REGISTER
		echo $infoLine >> "$REGISTER"
		# Nice and done
		echo "Registered $fileToTrack"
	fi
}

function link_registered {
	STORAGE_LOCATION=$(read_dotfile_location)
	REGISTER="$STORAGE_LOCATION/register.txt"
	STORE="$STORAGE_LOCATION/files"

	if [ ! -f "$REGISTER" ]; then
		echo "No register file found"
		exit 1
	fi

	if [ ! -d "$STORE" ]; then
		echo "No registered files found"
		exit 1
	fi

	while read -r line; do
		local arg1=$(echo "$line" | cut -d "$DELIM" -f1)
		local arg2=$(echo "$line" | cut -d "$DELIM" -f2)

		local src="$STORE/$arg1"
		local target="$HOME/$arg2/$arg1"

		if [ -f "$target" ] || [ -d "$target" ]; then
			echo "File $target already exists, please back it up an	remove it"
		else
			echo "Linking $src to $target"
			cp -r "$src" "$target"
		fi
	done < "$REGISTER"
}

function save_registered {
	STORAGE_LOCATION=$(read_dotfile_location)
	REGISTER="$STORAGE_LOCATION/register.txt"
	STORE="$STORAGE_LOCATION/files"

	if [ ! -f "$REGISTER" ]; then
		echo "No register file found"
		exit 1
	fi

	if [ ! -d "$STORE" ]; then
		echo "No registered files found"
		exit 1
	fi

	while read -r line; do
		local arg1=$(echo "$line" | cut -d "$DELIM" -f1)
		local arg2=$(echo "$line" | cut -d "$DELIM" -f2)

		local src="$HOME/$arg2/$arg1"
		local target="$STORE/$arg1"

		if [ -f "$target" ] || [ -d "$target" ]; then
			rm -rf "$target"
		else
			echo "Saving $src to $STORE"
			cp -r "$src" "$STORE"
		fi
	done < "$REGISTER"
}

function printHelp {
  echo "-------------------------"
  echo ""
  echo "Options for dotfiles mgmt"
  echo ""
  echo "  register <file>: Register a file or directory to be tracked"
  echo "  link: Copy over registered files into the system"
  echo "  save: Save all modifications made to files in the running system back into this repo"
  echo ""
  echo "------"
  echo ""
}

operation="$1"
options="$2"

case $operation in
  register)
    register $options
    ;;
  link)
    link_registered
    ;;
  save)
    save_registered
    ;;
  *)
    printHelp
esac
