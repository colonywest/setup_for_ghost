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
# Amazon Linux 2023 installation. And I wrote it because I feel that if it 
# can be a script, it should be a script.

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

function randomize_string {
    if [[ -n $1 ]]; then
        shuffle_count=$(($RANDOM % 10))
        shuffle_count=$((shuffle_count + 1))

        string_to_shuffle=$1
        echo -e "import random\nprint(''.join(random.sample('$string_to_shuffle', ${#string_to_shuffle})))" | python3
    fi
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

os_id="${os_release_map[ID]}"
os_version_id="${os_release_map[VERSION_ID]}"
os_name="${os_release_map[NAME]}"

# And if the codename is "noble" or "jammy", presume the script will work.
# Anything else, though... abort!

if [[ "$os_id" != 'amzn' ]] || [[ "$os_version_id" != '2023' ]]; then
    echo This script is written for Amazon Linux 2023.
    exit
fi

# 2. Do NOT run as root. A new ghost user will be created, but the
#    current user will need to be added to that user's group for
#    future updates.

if [[ "$(whoami)" == 'root' ]]; then
    echo This script cannot be run as \'root\' or using \'sudo\'.
    exit
fi

# 3. But... make sure the current user is part of the 'wheel' group.

groups="$(groups)"
user_groups=(${groups// / })
has_sudo=0
for group_i in "${user_groups[@]}"; do
    if [[ "$group_i" == 'wheel' ]]; then
        has_sudo=1
        break
    fi
done

if [[ $has_sudo == 0 ]]; then
    echo You must run this script as a user with sudo privileges. The current
    echo user \($(whoami)\) is not in the \'wheel\' group.
    exit
fi

# Now for the main event!

echo
echo Welcome! I will prepare your Amazon Linux 2023 instance for installing the
echo Ghost content management system - https://ghost.org - by installing all
echo needed prerequisites: Node.js, Ghost CLI, nginx, and MySQL. These will be
echo installed from their *official* repositories, not the Amazon Linux repositories.
echo
echo I am intended to be run on a fresh instance. While I can be run on a
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
echo MySQL RPM repository. So answer N if you do not want this or you will be
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

sudo useradd --home /home/ghost --groups wheel $ghost_user --shell $SHELL
echo "$ghost_user:$ghost_user_password" | sudo chpasswd
sudo usermod -aG $ghost_user $(whoami)

# Now to create all the needed repositories up front. That way there is
# only one call to "dnf makecache" and "dnf install" later.

# nginx repository

nginx_repo="\
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/amzn/2023/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
priority=9"

echo "$nginx_repo" | sudo tee /etc/yum.repos.d/nginx.repo

# Node.js

NODE_MAJOR=20
curl -fsSL "https://rpm.nodesource.com/setup_$NODE_MAJOR.x" | sudo bash -

# MySQL

if [[ "$install_mysql" == 'y' ]]; then

    # Need to install MySQL from the EL9 repo, not FCxx.

    rpm_filename="mysql84-community-release-el9-1.noarch.rpm"
    mysql_rpm_url="https://dev.mysql.com/get/$rpm_filename"

    wget $mysql_rpm_url
    sudo dnf install -y $rpm_filename
    rm $rpm_filename
fi

# Run update and install

packages='nodejs nginx certbot python3-certbot-nginx'
if [[ "$install_mysql" == 'y' ]]; then
    packages="$packages mysql-server"
fi

sudo dnf makecache
sudo dnf install -y $packages

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

    mysql_root_password=$(curl -s "https://www.random.org/strings/?num=1&len=15&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new")
    mysql_ghost_password=$(curl -s "https://www.random.org/strings/?num=1&len=15&digits=on&upperalpha=on&loweralpha=on&unique=on&format=plain&rnd=new")

    sudo systemctl enable --now mysqld

    mysql_temp_password=$(sudo cat /var/log/mysqld.log | grep -E 'temporary password.+root@localhost:' | sed -E 's/^.+localhost: (.+)/\1/g')

    # A little unusual sequence here. Take the temp password, which matches
    # the default complexity requirements, and append it to the end of the
    # random string. Then shuffle it all together.

    mysql_root_password=$(randomize_string "$mysql_root_password$mysql_temp_password")
    mysql_ghost_password=$(randomize_string "$mysql_ghost_password$mysql_temp_password")

    ghost_mysql="ALTER USER 'root'@'localhost' IDENTIFIED BY '$mysql_root_password'; \
    CREATE DATABASE ghost; \
    CREATE USER 'ghost'@'%' IDENTIFIED BY '$mysql_ghost_password'; \
    GRANT ALL PRIVILEGES ON ghost.* TO 'ghost'@'%'; \
    FLUSH PRIVILEGES;"

    sudo mysql --user=root --password=$mysql_temp_password --connect-expired-password -e "$ghost_mysql"

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

MySQL hostname:      127.0.0.1 (should be the default)
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
