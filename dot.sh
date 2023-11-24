#!/bin/bash

#
# TODO Deal with Errors on Vault operations
# TODO Find a way to deal with the password
#

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

DELIM="|"
DOTFILE_LOCATION="$HOME/.dotdot"
STORAGE_LOCATION="$HERE"

function read_pwd {
	maybePwd="$1"

	if [ -n "$maybePwd" ]; then
		echo "$maybePwd"
	else
		read -sp "Enter password: " PASSWORD
		# echo "Password: "
		# stty -echo
		# read PASSWORD
		# stty echo
		printf "\n"

		echo $(echo $PASSWORD | tr ' ' '_')
	fi
}
function write_dotfile_location {
	echo "$1" > "$DOTFILE_LOCATION"
}
function read_dotfile_location {
	echo $(cat "$DOTFILE_LOCATION" | head -n 1)
}
function expand_read_line {
	echo "$(eval echo $1)"
}
function save_git {
	local dir="$1"
	if [ -d "$dir" ] && [ -d "$dir/.git" ]; then
		(cd "$dir" && git add . && git commit -m "dotfiles update" && git push)
	fi
}

#############################################
# This function is used to encrypt/decrypt
# the secrets directory using a local .pass file
#############################################

function vault {
	local dir="$1"
	local op="$2"
	local cwd="$(pwd)"

	if [ "$op" = "encrypt" ]; then
		local pwd=$(read_pwd $3)

		hash openssl 2>/dev/null
		hasOpenSSL=$?

		# macos ships with libressl and brew does not want to override it
		# so we force adding openssl to the PATH during the execution of this script
		[ -d /usr/local/opt/openssl@1.1/bin ] \
			&& OPENSSL="/usr/local/opt/openssl@1.1/bin/openssl" \
			|| OPENSSL="openssl"

		OPENSSL="openssl"

		if [ -d "${dir}/.secrets" ] \
			&& [ "$hasOpenSSL" -eq "0" ] \
			&& [ -n "${pwd}" ]; then

			local encrypted=1

			cd "${dir}"
			tar cvz ./.secrets | $OPENSSL enc -aes-256-ecb -e -salt -pass "pass:'${pwd}'" -out .secrets.tar.gz.dat
			encrypted=$?
			[ $encrypted -eq 0 ] && rm -rf ./.secrets || rm -rf ./.secrets.tar.gz.dat
			cd "${cwd}"

			return $encrypted
		else
			return 1
		fi

	elif [ "$op" = "decrypt" ]; then
		local pwd=$(read_pwd $3)

		hash openssl 2>/dev/null
		hasOpenSSL=$?

		# macos ships with libressl and brew does not want to override it
		# so we force adding openssl to the PATH during the execution of this script
		[ -d /usr/local/opt/openssl@1.1/bin ] \
			&& OPENSSL="/usr/local/opt/openssl@1.1/bin/openssl" \
			|| OPENSSL="openssl"

		OPENSSL="openssl"

		if [ -f "${dir}/.secrets.tar.gz.dat" ] \
			&& [ "$hasOpenSSL" -eq "0" ] \
			&& [ -n "${pwd}" ]; then
			local decrypted=1

			cd "${dir}"
			$OPENSSL enc -aes-256-ecb -d -pass "pass:'${pwd}'" -in ./.secrets.tar.gz.dat | tar xvzf -
			decrypted=$?
			[ $decrypted -eq 0 ] && rm -rf ./.secrets.tar.gz.dat || rm -rf ./.secrets
			cd "${cwd}"

			return $decrypted
		else
			return 1
		fi
	elif [ "$op" = "ignore" ]; then
		hash git 2>/dev/null
		hasGit=$?

		if [ "$hasGit" -eq "0" ] \
		 && [ -f "${dir}/.secrets.tar.gz.dat" ]; then
			(cd $dir && git checkout ".secrets.tar.gz.dat")
		fi

		return 0
	else
		return 1
	fi
}

#############################################
# This function save the location of dotfiles
#############################################

function ensure_dotfile_location {
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

	echo "$STORAGE_LOCATION"
}

#############################################
# Track a file in the register and copy it to the store
#############################################

function register {
	local REGISTER="$1"
	local STORE="$2"
	local fileToTrack="$3"
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
}

#############################################
# Untrack a file in the register and remove it from the store
#############################################

function unregister {
	local REGISTER="$1"
	local STORE="$2"
	local fileToTrack="$3"
	local srcDirName="$(dirname $fileToTrack)"
	local srcFileName="$(basename $fileToTrack)"
	local infoLine="${srcFileName}${DELIM}${srcDirName}"
	# local isHidden=$([[ "$srcFileName" =~ ^\\\. ]] && echo "1" || echo "0")
	# local visibleName=$([ "$isHidden" = "1" ] && echo "${srcFileName:1}" || echo "$srcFileName")
	local sedSafe=$(echo "$srcFileName" | sed -E -e 's/\./\\./g')

	# Removing file from store
	rm -rf $STORE/$srcFileName
	sed -i '' -E -e "/^${sedSafe}/d" $REGISTER
}

#############################################
# Given a register file, copy the files in the STORE
# to the system
#############################################

function link {
	local REGISTER="$1"
	local STORE="$2"

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

#############################################
# Given a register, update the files in the store
# with the files in the system
#############################################

function save {
	local REGISTER="$1"
	local STORE="$2"

	while read -r line; do
		local arg1=$(echo "$line" | cut -d "$DELIM" -f1)
		local arg2=$(echo "$line" | cut -d "$DELIM" -f2)

		local src="$HOME/$arg2/$arg1"
		local target="$STORE/$arg1"

		if [ -f "$target" ] || [ -d "$target" ]; then
			rm -rf "$target"
		fi
		echo "Saving $src to $STORE"
		cp -r "$src" "$STORE"
	done < "$REGISTER"

}

#############################################
# This function to register a dotfile publicly
#############################################

function register_public {
	local STORAGE_LOCATION=$(ensure_dotfile_location)
	local FILE_STORE="$STORAGE_LOCATION/files"
	local FILE_REGISTER="$STORAGE_LOCATION/register.txt"

	mkdir -p $FILE_STORE
	touch "$FILE_REGISTER"

	local file="$1"
	local realFileToTrack=$(readlink -f $file)
	local fileToTrack="${realFileToTrack//$HOME\/}"

	if [ "$realFileToTrack" = "$fileToTrack" ]; then
		echo "File is not in home directory, cannot track it"
	else
		register "$FILE_REGISTER" "$FILE_STORE" "$fileToTrack"
		# Save to GIT
		save_git "$STORAGE_LOCATION"
	fi
}

#############################################
# This function to register a dotfile secretly
#############################################

function register_secret {
	local STORAGE_LOCATION=$(ensure_dotfile_location)
	local SECRETS_STORE="$STORAGE_LOCATION/.secrets"
	local SECRETS_REGISTER="$STORAGE_LOCATION/secrets.txt"
	local SECRETS_VAULT="$STORAGE_LOCATION/.secrets.tar.gz.dat"

	touch "$SECRETS_REGISTER"

	local file="$1"
	local pwd=$(read_pwd $2)
	local realFileToTrack=$(readlink -f $file)
	local fileToTrack="${realFileToTrack//$HOME\/}"

	if [ "$realFileToTrack" = "$fileToTrack" ]; then
		echo "File is not in home directory, cannot track it"
	else
		if [ -f "$SECRETS_VAULT" ]; then
			vault $STORAGE_LOCATION decrypt "$pwd"
			[ "$?" = "0" ] || exit 1
		else
			mkdir -p $SECRETS_STORE
		fi

		register "$SECRETS_REGISTER" "$SECRETS_STORE" "$fileToTrack"
		vault $STORAGE_LOCATION encrypt "$pwd"
		[ "$?" = "0" ] && save_git "$STORAGE_LOCATION"
	fi

}

#############################################
# This function to unregister a dotfile publicly
#############################################

function unregister_public {
	local STORAGE_LOCATION=$(ensure_dotfile_location)
	local FILE_STORE="$STORAGE_LOCATION/files"
	local FILE_REGISTER="$STORAGE_LOCATION/register.txt"

	mkdir -p $FILE_STORE
	touch "$FILE_REGISTER"

	local file="$1"
	local realFileToTrack=$(readlink -f $file)
	local fileToTrack="${realFileToTrack//$HOME\/}"

	if [ "$realFileToTrack" = "$fileToTrack" ]; then
		echo "File is not in home directory, cannot track it"
	else
		unregister "$FILE_REGISTER" "$FILE_STORE" "$fileToTrack"
		# Save to GIT
		save_git "$STORAGE_LOCATION"
	fi
}

#############################################
# This function to register a dotfile secretly
#############################################

function unregister_secret {
	local STORAGE_LOCATION=$(ensure_dotfile_location)
	local SECRETS_STORE="$STORAGE_LOCATION/.secrets"
	local SECRETS_REGISTER="$STORAGE_LOCATION/secrets.txt"
	local SECRETS_VAULT="$STORAGE_LOCATION/.secrets.tar.gz.dat"

	touch "$SECRETS_REGISTER"

	local file="$1"
	local pwd=$(read_pwd $2)
	local realFileToTrack=$(readlink -f $file)
	local fileToTrack="${realFileToTrack//$HOME\/}"

	if [ "$realFileToTrack" = "$fileToTrack" ]; then
		echo "File is not in home directory, cannot track it"
	else
		if [ -f "$SECRETS_VAULT" ]; then
			vault $STORAGE_LOCATION decrypt "$pwd"
			[ "$?" = "0" ] || exit 1
		else
			mkdir -p $SECRETS_STORE
		fi

		unregister "$SECRETS_REGISTER" "$SECRETS_STORE" "$fileToTrack"
		vault $STORAGE_LOCATION encrypt "$pwd"
		[ "$?" = "0" ] && save_git "$STORAGE_LOCATION"
	fi

}
#############################################
# This function restore the registered files
#############################################

function link_registered {
	local STORAGE_LOCATION=$(read_dotfile_location)
	local FILE_REGISTER="$STORAGE_LOCATION/register.txt"
	local FILE_STORE="$STORAGE_LOCATION/files"
	local SECRETS_REGISTER="$STORAGE_LOCATION/secrets.txt"
	local SECRETS_STORE="$STORAGE_LOCATION/.secrets"
	local SECRETS_VAULT="$STORAGE_LOCATION/.secrets.tar.gz.dat"

	if [ -f "${SECRETS_VAULT}" ] && [ -f "${SECRETS_REGISTER}" ]; then
		local pwd=$(read_pwd $1)
		vault $STORAGE_LOCATION decrypt "$pwd"
		[ "$?" = "0" ] || exit 1

		link "$SECRETS_REGISTER" "$SECRETS_STORE"

		vault $STORAGE_LOCATION encrypt "$pwd"
		vault $STORAGE_LOCATION ignore
		[ "$?" = "0" ] || exit 1
	fi

	if [ -f "$FILE_REGISTER" ] && [ -d "$FILE_STORE" ]; then
		link "$FILE_REGISTER" "$FILE_STORE"
	fi
}

#############################################
# This function to save the registered files
#############################################

function save_registered {
	local STORAGE_LOCATION=$(read_dotfile_location)
	local FILE_REGISTER="$STORAGE_LOCATION/register.txt"
	local FILE_STORE="$STORAGE_LOCATION/files"
	local SECRETS_REGISTER="$STORAGE_LOCATION/secrets.txt"
	local SECRETS_STORE="$STORAGE_LOCATION/.secrets"
	local SECRETS_VAULT="$STORAGE_LOCATION/.secrets.tar.gz.dat"

	# If some secrets are registered
	# We save them
	if [ -f "${SECRETS_REGISTER}" ]; then
		local pwd=$(read_pwd $1)

		# Check for the vault and either create it or decrypt it
		if [ -f "${SECRETS_VAULT}" ]; then
			vault $STORAGE_LOCATION decrypt "$pwd"
			[ "$?" = "0" ] || exit 1
		else
			mkdir -p $SECRETS_STORE
		fi

		save "$SECRETS_REGISTER" "$SECRETS_STORE"
		vault $STORAGE_LOCATION encrypt "$pwd"
		[ "$?" = "0" ] || exit 1
	fi

	# If some regular files are registered
	# We save them
	if [ -f "$FILE_REGISTER" ] && [ -d "$FILE_STORE" ]; then
		save "$FILE_REGISTER" "$FILE_STORE"
	fi

	# Save to GIT
	save_git "$STORAGE_LOCATION"
}

function printHelp {
  echo "-------------------------"
  echo ""
  echo "Options for dotfiles mgmt"
  echo ""
  echo "  register <file>: Register a file or directory to be tracked"
  echo "  secret <file>: Register a secret or directory to be tracked"
  echo "  link: Copy over registered files into the system"
  echo "  save: Save all modifications made to files in the running system back into this repo"
  echo ""
  echo "------"
  echo ""
}

operation="$1"
options="$2"

case $operation in
	encrypt)
		LOCATION=$(read_dotfile_location)
		PASS=$(read_pwd $options)
		vault $LOCATION encrypt "$PASS"
		[ "$?" = "0" ] && echo "Encrypted" || echo "Failed To encrypt"
	;;
	decrypt)
	  LOCATION=$(read_dotfile_location)
		PASS=$(read_pwd $options)
		vault $LOCATION decrypt "$PASS"
		[ "$?" = "0" ] && echo "Decrypted" || echo "Failed To decrypt"
	;;
  register)
    register_public $options
    ;;
  secret)
    register_secret $options
    ;;
  unregister)
    unregister_public $options
    ;;
  unsecret)
    unregister_secret $options
    ;;
  link)
    link_registered $options
    ;;
  save)
    save_registered $options
    ;;
  *)
    printHelp
esac
