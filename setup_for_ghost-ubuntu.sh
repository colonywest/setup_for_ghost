#!/bin/bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# The author of this script is NOT affiliated with the Ghost Foundation
# in any way.

# This script is written with the presumption it is being run on a fresh
# Ubuntu LTS installation. And I wrote it because I feel that if it can be a
# script, it should be a script.

function map_os_release {
    mapfile os_release <<< $(cat /etc/os-release)
    for line in "${os_release[@]}"
    do
        IFS="=" read -a items <<< "$line"
        key="${items[0]}"
        value=$(echo "${items[1]}" | tr -d '"')

        # Note: ID_LIKE can have multiple values - e.g., on Linux Mint
        # the value will be "ubuntu debian"

        os_release_map[$key]="$value"
    done
}

function read_trap {
    echo
    echo Aborting...
    exit
}

trap read_trap SIGINT

declare -A os_release_map
map_os_release

# Sanity checks:
# 1. Make sure we're on a supported Ubuntu distro or Ubuntu derivation

os_name="${os_release_map[NAME]}"
os_codename="${os_release_map[UBUNTU_CODENAME]}"
os_arch=$(dpkg --print-architecture)

# Simple way to check: if UBUNTU_CODENAME isn't specified, it isn't an
# Ubuntu-derived Linux distro.

if [[ -z "$os_codename" ]]; then
    echo This script is written for an Ubuntu-based Linux distribution.
    exit
fi

# And if the codename is "noble" or "jammy", presume the script will work.
# Anything else, though... abort!

if [[ "$os_codename" != "noble" && "$os_codename" != "jammy" ]]; then
    echo This script is written for a Linux distribution derived from Ubuntu
    echo 22.04 LTS \(\"Jammy Jellyfish\"\) or 24.04 LTS \(\"Nobile Numbat\"\).

    exit
fi

# 2. Do NOT run as root. A new ghost user will be created, but the
#    current user will need to be added to that user's group for
#    future updates.

if [[ "$(whoami)" == 'root' ]]; then
    echo This script cannot be run as \'root\' or using \'sudo\'.
    exit
fi

# 3. But... make sure the current user is part of the 'sudo' group.

groups="$(groups)"
user_groups=(${groups// / })
has_sudo=0
for group_i in "${user_groups[@]}"; do
    if [[ "$group_i" == 'sudo' ]]; then
        has_sudo=1
        break
    fi
done

if [[ has_sudo == 0 ]]; then
    echo You must run this script as a user with sudo privileges. The current
    echo user \($(whoami)\) is not in the \'sudo\' group.
    exit
fi

# Now for the main event!

echo
echo Welcome! I will prepare your ${os_release_map[PRETTY_NAME]} instance for installing the
echo Ghost content management system - https://ghost.org - by installing all
echo needed prerequisites: Node.js, Ghost CLI, nginx, and MySQL. These will be
echo installed from their *official* repositories, not the $os_name repositories.
echo
echo I am intended to be run on a fresh system install. While I can be run on a
echo non-clean system, I cannot guarantee this will be successful and that your
echo system won\'t be maimed in the process. So if you are not running this on
echo a clean system, you have been warned!
echo
echo Along the way, I\'ll be generating passwords by reaching out to Random.org
echo rather than relying on user input. This ensures you will have strong passwords
echo for critical accounts and services and will not be reusing passwords.
echo
echo These passwords plus all additional details for installing Ghost will be output
echo at the end and written to a text file for immediate reference.
echo
read -p "Press Enter when you're ready to begin, Ctrl+C to abort."

# Reset the sudo timestamp and re-prompt for the sudo password to avoid the
# logged-in user from being prompted for it in the middle of this script.

sudo -k

# First check for passwordless sudo, since "sudo -k" is akin to a no-op on
# such systems. No point in saying they'll be prompted for the password when
# one isn't required in the first place.

if ! sudo -n true 2> /dev/null ; then
    echo
    echo I need your sudo password.
    echo
    echo I invalidated any previous entry of your sudo password - using \'sudo -k\', if
    echo you\'re not familiar\ - to make sure it\'s freshly cached so I don\'t get
    echo interrupted while I\'m working.
    echo
    echo Note: you should NOT be seeing this message if you have \"passwordless sudo\" set
    echo up properly on this server - e.g., this server is an AWS instance.
    echo
    if ! sudo true ; then
        exit
    fi
fi

echo
echo I\'ll start by creating a new user which Ghost will use for running the Ghost
echo services. If you intend to use a specific username, enter that here, or just
echo press ENTER to accept the default.
echo

read -p "System-level user for running Ghost [ghost]: " ghost_user
if [[ -z "$ghost_user" ]]; then
    ghost_user='ghost'
fi

echo
echo Should I install MySQL Server on this host?
echo
echo Note that I will be installing MySQL Community Edition from the official
echo MySQL APT repository. So answer N if you do not want this or you will be
echo using a separate host for MySQL.
echo
echo Note: Anything other than \'Y/y\' will be treated as No.
echo
read -n 1 -p "Install MySQL? [Y/n] " install_mysql
echo

if [[ -z "$install_mysql" ]]; then
    install_mysql=y
else
    install_mysql=$(echo $install_mysql | tr '[:upper:]' '[:lower:]')
fi

if [[ "$install_mysql" == 'y' ]]; then

    echo
    echo Now for the name of the database Ghost will use. You will likely want the
    echo default here, especially if you will have only one Ghost site on this host.
    echo
    read -p "MySQL database for Ghost [ghost]: " ghost_db

    if [[ -z "$ghost_db" ]]; then
        ghost_db='ghost'
    fi
fi

# Let's output the prompt values for confirmation...

echo
echo Okay let\'s review a moment. Here are the answers you gave above:
echo
echo System-level user for running Ghost: \"$ghost_user\"
echo Installing MySQL? $install_mysql

if [[ "$install_mysql" == 'y' ]]; then
    echo MySQL database for Ghost: $ghost_db
fi

echo
echo If everything above looks good, press ENTER and I\'ll continue with installing
echo the prerequisites. If not, abort this script with Ctrl+C and restart. No changes
echo have been made to your system and will not be unless you press ENTER here.
echo
read -p "Press ENTER to continue, or Ctrl+C to abort."
echo Continuing...

# First, let's create the new "ghost" user.

ghost_user_password=$(curl -s "https://www.random.org/strings/?num=1&len=16&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new")

sudo useradd --create-home --groups sudo $ghost_user --shell $SHELL
echo "$ghost_user:$ghost_user_password" | sudo chpasswd
sudo usermod -aG $ghost_user $(whoami)

# Now to create all the needed repositories up front. That way there is
# only one call to "apt update" and "apt install" later.

keyrings_dir=/usr/share/keyrings
sudo mkdir -p $keyrings_dir

# nginx repository

nginx_keyring="$keyrings_dir/nginx-archive-keyring.gpg"

curl -s https://nginx.org/keys/nginx_signing.key |\
    gpg --dearmor |\
    sudo tee $nginx_keyring > /dev/null

echo "deb [arch=$os_arch signed-by=$nginx_keyring] http://nginx.org/packages/ubuntu $os_codename nginx" |\
    sudo tee /etc/apt/sources.list.d/nginx.list > /dev/null

# Node.js

node_keyring="$keyrings_dir/nodesource.gpg"

curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | sudo gpg --dearmor -o $node_keyring

NODE_MAJOR=20 # Latest version that Ghost supports
echo "deb [arch=$os_arch signed-by=$node_keyring] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null

# MySQL

if [[ "$install_mysql" == 'y' ]]; then

    # Start by setting up the repository, starting with the PGP keys.
    # These IDs are the fingerprints for all keys associated with
    # "mysql-build@oss.oracle.com", which is the ID of the signing key
    # for the MySQL repo.

    mysql_keyring="$keyrings_dir/mysql-apt-config.gpg"
    signing_key_ids='467B942D3A79BD29 B7B3B788A8D3785C'

    # Use a temp folder for gpg so we avoid importing keys into the main
    # keyring for the user. The chmod call is to avoid the warning
    # "unsafe permissions on homedir".

    gpg_temp=./.gpg_temp

    mkdir $gpg_temp
    sudo chmod 700 $gpg_temp

    gpg --homedir $gpg_temp --keyserver keyserver.ubuntu.com --recv-keys $signing_key_ids
    gpg --homedir $gpg_temp --export $signing_key_ids | sudo tee $mysql_keyring > /dev/null
    sudo chmod 644 $mysql_keyring

    rm -rf $gpg_temp

    mysql_repo=\
"deb [arch=$os_arch signed-by=$mysql_keyring] http://repo.mysql.com/apt/ubuntu/ $os_codename mysql-apt-config
deb [arch=$os_arch signed-by=$mysql_keyring] http://repo.mysql.com/apt/ubuntu/ $os_codename mysql-8.0
deb [arch=$os_arch signed-by=$mysql_keyring] http://repo.mysql.com/apt/ubuntu/ $os_codename mysql-tools
deb-src [arch=$os_arch signed-by=$mysql_keyring] http://repo.mysql.com/apt/ubuntu/ $os_codename mysql-8.0"

    echo "$mysql_repo" | sudo tee /etc/apt/sources.list.d/mysql.list > /dev/null

    # Set some selections to avoid being prompted for anything when mysql is installed.
    # Don't set a root password now, though, as that'll come later.

    sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password "
    sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password "
    sudo debconf-set-selections <<< "mysql-community-server mysql-server/default-auth-override select Use Strong Password Encryption (RECOMMENDED)"

fi

# Run update and install

packages='nodejs nginx'
if [[ "$install_mysql" == 'y' ]]; then
    packages="$packages mysql-server"
fi

sudo apt update
sudo NEEDRESTART_MODE=a apt install -y $packages

# Config for nginx

# Ghost's install expects to find the sites-available and sites-enabled
# folders. When installing nginx from the "official" repo, these folders
# aren't created the Ghost installer doesn't account for this.

sudo mkdir -p /etc/nginx/sites-available
sudo mkdir -p /etc/nginx/sites-enabled

{ echo -e "include /etc/nginx/sites-enabled/*.conf;\n"; cat /etc/nginx/conf.d/default.conf; } | sudo tee /etc/nginx/conf.d/default.conf > /dev/null

sudo systemctl enable --now nginx

if [[ "$install_mysql" == 'y' ]]; then

    # Config and final setup for MySQL

    mysql_root_password=$(curl -s "https://www.random.org/strings/?num=1&len=16&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new")
    mysql_ghost_password=$(curl -s "https://www.random.org/strings/?num=1&len=16&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new")

    sudo systemctl enable --now mysql

    ghost_mysql="CREATE DATABASE ghost; \
    CREATE USER 'ghost'@'%' IDENTIFIED BY '$mysql_ghost_password'; \
    GRANT ALL PRIVILEGES ON ghost.* TO 'ghost'@'%'; \
    ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password'; \
    FLUSH PRIVILEGES;"

    sudo mysql --user=root -e "$ghost_mysql"

fi

# Update things

sudo npm install -g npm
sudo npm install -g ghost-cli

# Setting up new folder for Ghost

ghost_folder=/usr/share/nginx/ghost

sudo mkdir $ghost_folder
sudo chown $ghost_user:$ghost_user $ghost_folder
sudo chmod 775 $ghost_folder

# Final output.

final_output="Password for \"$ghost_user\" user: $ghost_user_password"

if [[ "$install_mysql" == 'y' ]]; then

    final_output="$final_output
MySQL \"root\" password: $mysql_root_password
MySQL \"ghost\" password: $mysql_ghost_password

During the Ghost installation, make sure to use these values when prompted:

MySQL hostname:      localhost (should be the default)
MySQL username:      ghost
MySQL password:      $mysql_ghost_password
Ghost database name: $ghost_db
"
fi

final_output="$final_output

Next steps:
1. Log off the current user
2. Log back in as $ghost_user
3. cd $ghost_folder
4. ghost install

You will be prompted for the \"sudo\" password during the Ghost install.
That will be the password for \"$ghost_user\".

Be sure to store off the passwords in a secure location, preferably using a
password manager.
"

echo
echo
echo "$final_output" | tee ghost_setup.log
echo
echo These details were also written to ghost_setup.log
