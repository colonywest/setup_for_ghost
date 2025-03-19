# Ghost prerequisite setup

Why go through the [manual instructions for installing Ghost](https://ghost.org/docs/install/ubuntu/) when this script merely prompts you for a couple details and does the rest. It won't install Ghost, but it installs all the prerequisites so you don't have to waste your time doing that dirty work.

Run this script and in a couple minutes you'll be ready to install Ghost to your Ubuntu system.

## Requirements

There are two versions of the script: Ubuntu and Amazon Linux 2023.

You should be running this on a fresh Linux installation (e.g., a new cloud VM instance) with all updates applied, or at least an install that does not have nginx (or any other web server), Node.js, and MySQL or MariaDB already installed. It will not check for these in advance.

### Ubuntu-based distributions

So far Linux Mint is the only Ubuntu-derived distro on which this script has been tested.

Whichever distro you choose must be derived from 24.04 LTS ("Noble Numbat") or 22.04 LTS ("Jammy Jellyfish"). And the `UBUNTU_CODENAME` field in `/etc/os-release` must have the right string to reflect from which Ubuntu version it is derived. If the distro packager claims it's derived from one of the required releases but the script errors out, it's likely `UBUNTU_CODENAME` is not being set properly.

## Using this script

Just copy the script to the target system and run it... This script must be run by a user with sudo privileges, but cannot be run using sudo or by the root user.

It will prompt you for three things:

1. The system-level account to create for Ghost (default: ghost)
2. Install MySQL Community? (default: Yes)
3. MySQL database to create for Ghost (default: ghost, prompted only if installing MySQL)

Most likely you will want the defaults.

The script reaches out to random.org to generate passwords for Ghost system-level account and MySQL "root" and "ghost" accounts. This is to ensure you have strong passwords and aren't reusing anything. Details are output at the end and to a text file.

## Next steps

After the script is run, next steps are

1. Log out of the account you used to run the script
2. Log back in as the Ghost account
3. cd to the nginx directory created for Ghost
4. Run ghost install and follow the prompts

All information you need to configure Ghost is output at the end of the script run and written to a text file.

## Future plans

I want to see if I can get this script working on other Debian and non-Debian distros - e.g., [Linux Mint Debian Edition (LMDE)](https://linuxmint.com/download_lmde.php) and [Rocky Linux](https://rockylinux.org/). *Officially* [Ghost supports only Ubuntu](https://ghost.org/docs/hosting/), but since it all runs in Node.js, there isn't any reason it can't work elsewhere.

Linux distros supported by major cloud service providers, though, will be the priority.

## Copyright, License, Disclaimer

Copyright &copy; 2024-2025 Kenneth Ballard

Licensed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0) (the "License"); you may not use this file except in compliance with the License.

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

The author of this script is not affiliated with the [Ghost Foundation](https://ghost.org/) in any way.
