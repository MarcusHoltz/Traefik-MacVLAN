# Setting Up Docker MacVLAN Network for Traefik's Access Log Analytics from Promtail/Loki/Grafana: A Comprehensive Guide

I am working to pass the source IPs coming in to the containers in docker. I do not want to use host, and as far as I understand this is not possible in bridge mode. It is possible with a MacVLAN.

For a complete yet simple example, visit https://github.com/oglimmer/traefik-loki-grafana-web-analytics.

For the full guide that goes along with this repo, visit [https://blog.holtzweb.com](#urlhere).

## Demo 

![Traefik Docker MacVLAN Demo of Script Running](https://raw.githubusercontent.com/MarcusHoltz/marcusholtz.github.io/refs/heads/main/assets/img/posts/traefik_docker_macvlan_demo.gif)



# Pre-Setup 

a/k/a Required Software Install and System State Assumptions


## Install Script

The only requirement is Debian 12. 

The rest of the script covers all materials needed to have:

- MacVLAN on the host interface 

- Docker MacVLAN for Traefik

- Traefik's access logs with original source headers

- Analytic dashboard with Promtail/Loki/Grafana

* * *

### System Requirements

Make sure this is a Debian 12 system you're working with. I dont think I have mentioned this at all?


#### Debian 12 only

Oh look there, yes, `Debian 12`. You may find a path to do this with other methods, but out of the box LXC or VM - we're going with **Debian**.


* * *

### Script Features

- **Automated Traefik + MacVLAN Setup:** Configures Traefik with a MacVLAN Docker network for simplified reverse proxy.

- **Docker Installation** (Optional): Installs Docker if not already present on the system.

- **Automatic Network Information:** Detects and stores host network details (IP, gateway, subnet).

- **Systemd-Networkd Integration:** Generates and applies systemd network configuration files for MacVLAN support.

- **ifupdown networking disable**: Disables ifupdown2 networking if systemd-networkd is enabled.

- **Context-Aware Configuration**: Adapts its configuration steps based on whether it is running before or after a system reboot, ensuring proper setup in either scenario.

- **LXC virtualization check**: Will alter the script depending on the virtual environment.

- **Dynamic IP Assignment:** Automatically assigns an IP address to the Traefik MacVLAN for access.

- **Docker Network Management:** Creates `traefik_proxy_net` for Docker container communication and `traefik2host` for Traefik's personal MacVLAN.

- **Configuration File Management:** Verifies, downloads, and sets up necessary configuration files for Traefik, Promtail, and Grafana.

- **Docker Compose Deployment:** Deploys the entire Traefik stack using Docker Compose.

- **Informational Output**: Provides post-configuration instructions, including DNS record setup and application access URLs, to guide the user.


* * *

## MacVLAN WARNING!!

* * *

> ::Information about MacVLAN:: **All ports** are **exposed** by MacVLAN.
> This is fine when Traefik is only serving `80` and `443`, but this setup includes port `8080`.
> Additionally, you may want to secure your Traefik metric endpoints, like, `/metrics` or `/stats` with an ipWhitelist.



* * *

# Install

To run the script from the command line directly:

```bash

wget -O - https://raw.githubusercontent.com/MarcusHoltz/Traefik-MacVLAN/refs/heads/main/traefik_macvlan_setup_script.sh | bash

```


# Script Breakdown

```text
+----------------------------------------------------+
|                  Script Execution Start            |
+----------------------------------------------------+
                            |
                            v
+---------------------+     |     +-------------------+
|  Display Banner     |-----+---->| Check Prerequisites|
|  - Initial warnings |           | - Sudo validation  |
+---------------------+           | - Docker checks    |
                                  | - .env loading     |
                                  +-------------------+
+-----------------------------+               |
| Check for Domain Name       |               |
| - Prompt if not in .env     |<--------------+
+-----------------------------+
                            |
                            v
+----------------------------------------------------+
| Gather Network Information                         |
| - IP, gateway, interface, subnet detection         |
+----------------------------------------------------+
                            |
                            v
+----------------------------------------------------+
| Check/Create/Modify Systemd Network Files          | 
| - Create macvlan netdev file                       |
| - Modify for existing interface rename             |
+----------------------------------------------------+
                            |
                            v
+------------------+        +------------------+
| Pre-Reboot Path  |        | Post-Reboot Path |
| - virt-check     |        | - Get new iface  |
| - Create network |        +------------------+
| - Rename prompt  |                  |
+------------------+                  |
          |                           |
          v                           v
+------------------------------+    +-----------------------------+
| Setup Traefik's MacVLAN IP   |    | Continue to Docker Setup    |
| - Auto MacVLAN IP assignment |    +-----------------------------+
| - No IP match = prompt for 1 |                  |
+------------------------------+                  |
                            |                     |
                            v                     v
+----------------------------------------------------+
| Update .env File                                   |
| - Save all collected variables                     |
+----------------------------------------------------+
                            |
                            v
+----------------------------------------------------+
| Handle Reboot Requirements                         |
| - Check systemd-networkd - not enabled, reboot     |
+----------------------------------------------------+
                            |
                            v
+----------------------------------------------------+
| Docker Network Setup                               |
| - Create traefik_proxy_net & traefik2host networks |
+----------------------------------------------------+
                            |
                            v
+----------------------------------------------------+
| Cleanup & Verification                             |
| - Remove sample files                              |
| - Download required configs                        |
| - Check GeoLite database                           |
+----------------------------------------------------+
                            |
                            v
+----------------------------------------------------+
| Run Docker Compose                                 |
| - Bring up Traefik stack                           |
+----------------------------------------------------+
                            |
                            v
+----------------------------------------------------+
|                     Script Complete                |
+----------------------------------------------------+
```


* * *

## Screen Shots


![Traefik Access Logs in Grafana](https://raw.githubusercontent.com/MarcusHoltz/marcusholtz.github.io/refs/heads/main/assets/img/posts/traefik_docker_macvlan_6--grafana-analytics.png)



![Grafana Dashboard zoomed out](https://raw.githubusercontent.com/MarcusHoltz/marcusholtz.github.io/refs/heads/main/assets/img/posts/traefik_docker_macvlan_8--grafana-analytics-dashboard.png)






* * *
* * *

## I took the steps below and converted them - Now they're the script above

* * *

## Geo Location Lookup File Needed

- You must copy this file: `GeoLite2-City.mmdb`

- From this location: [maxmind.com](https://dev.maxmind.com/geoip/geolite2-free-geolocation-data)

- To this path `./promtail/`

As explained below:

* * *

### Geo location lookup

Promtail will throw an error in the config if you dont:

* * *

Go to https://dev.maxmind.com/geoip/geolite2-free-geolocation-data and download `GeoLite2-City.mmdb`. Place it into the `promtail` directory.

* * *

> Dont complain to me when promtail wont start because you forgot to do this step.




## Modifications you may make to this repo's files


* * *

### A few network related facts


- Currently the subnet I have set for my DMZ is:

`172.21.192.0/19`


- Within that network, the IP range for the MacVLAN subnet to communicate over:

`172.21.192.248/29`


- Gateway address for the MacVLAN subnet:

`172.21.192.254`


- The IP Address of Traefik on Docker's MacVLAN is: 

`172.21.192.251`


- The name of the MacVLAN on the Host is called: 

`traefik2docker`


- The name of the Docker Network using the MacVLAN is: 

`traefik2host`


* * *

### Blog directory's Docker-Compose file

The docker-compose file, `docker-compose.yml` is in the base of the `blog` directory. 

You will need to edit the `docker-compose.yml` to match your own personal setup.


* * *

#### Change docker-compose.yml

1. Change your DNS domain name pointing to services

- `noweb.myneatodomain.com` is the sample domain. 
  - If TLS certs are not involved, you can set the domain to anything you like as long as the DNS points to the Traefik IP address declared in the docker-compose file. It doesnt have to be real, but it has to resolve.

> So, if you want, *search and replace* that sample domain with your perfered domain replacing example.com in the command below:


```bash

sed -i 's/noweb\.myneatodomain\.com/example.com/g' docker-compose.yml

```


2. The IP address of traefik on the Host's MacVLAN interface.

- In the `docker-compose` file, look for traefik's network.

> This is the IP Address you set with the DNS domain name above, it is address to port forward port 80 to.

```yaml
    networks:
      traefik2host:
        ipv4_address: 172.21.192.251
```


* * *

### Interface on the MacVLAN and Docker Network


1. Modify the interface on `\etc\systemd\network\20-ens18.network`

- You will need to change the `ens18` interface name to whatever interface you're using. 

- In the filename: `20-ens18.network`

- And inside the file: 

```ini
[Match]
Name=enp0s18
```

2. Change network addresses declared in the `docker network create -d macvlan` command below:


* * *

## Docker Network commands required for this to work


1. Create the Docker MacVLAN network using the systemd MacVLAN interface:

```bash

docker network create -d macvlan --subnet=172.21.192.0/19 --ip-range=172.21.192.248/29 --gateway=172.21.192.254 -o parent=traefik2docker traefik2host

```


2. Create docker internal bridge network:

```bash

docker network create traefik_proxy_net

```


* * *

## Place the /etc/ files in the correct location

Why all the systemd network files? For a persistant network change.

Again, this was a skeleton folder structure for you to find and understand. 

Now the files have to go into the correct location, 

```bash

sudo cp -R ./etc/ /

```

- If that was successful, you can now remove the `/etc/` folder from your working directory.



* * *

## Traefik Analytics Collected

You can view Traefik logs in Grafana:

- `http://grafana.noweb.myneatodomain.com`



## Links to generate website requests

```
- http://traefik-dashboard.noweb.myneatodomain.com

- http://whoami1.noweb.myneatodomain.com

- http://whoami2.noweb.myneatodomain.com

- http://catapp.noweb.myneatodomain.com

- http://error.noweb.myneatodomain.com

- http://portainer.noweb.myneatodomain.com

- http://anything.noweb.myneatdomain.com
```


### Services not accessible by web:

```
- promtail

- loki
```

## Services directly accessibly by IP Adress:

- `http://172.21.192.251:8080` access Traefik's dashboard


## Docker User Setup Script


<details>  

<summary>Create a New User, Install Docker, and Tools</summary>  

```bash
#!/bin/bash

# This script automates adding a new user, installing software, configuring the system, and more, without interaction.
# Usage: ./add_user.sh <username> <password> <group> <shell> <full_name>
#       ./add_user.sh john_doe secretpass123 developers /bin/bash "John Doe"


# Parameters
USERNAME=$1
PASSWORD=$2
GROUP=$3
SHELL=$4
FULL_NAME=$5


# Function to check if the script is running as the newly created user
check_user() {
    if [ "$(whoami)" = "$USERNAME" ]; then
        echo "You are now $USERNAME..."
        return 0
    else
        echo "You are not $USERNAME..."
        return 1
    fi
}

# Main script logic
# Check if we're running as the new user or need to create the user
if check_user; then
    # We are running as the newly created user, so set up their environment
    
    # Add environment variables and commands to .bashrc
    echo -e "\n\n# Save the history regardless of what window you're in" >> "/home/$USERNAME/.bashrc"
    echo "export PROMPT_COMMAND='history -a'" >> "/home/$USERNAME/.bashrc"
    echo -e "\n\n# Save the history size to a worthwhile amount" >> "/home/$USERNAME/.bashrc"
    echo "HISTSIZE=10000" >> "/home/$USERNAME/.bashrc"
    echo "HISTFILESIZE=20000" >> "/home/$USERNAME/.bashrc"

    # Add a function to kill all Docker containers
    echo -e '\nkillalldocker() {\n  docker stop $(docker ps -a -q) 2>/dev/null\n  docker rm $(docker ps -a -q) 2>/dev/null\n}' >> "/home/$USERNAME/.bashrc"

    # Add a function to start Docker containers with Docker Compose
    echo -e '\nstartupdocker() {\n  docker compose up --build -d && echo waiting for containers to come up... && while docker ps | grep "health: starting" > /dev/null; do sleep 1; done\n}' >> "/home/$USERNAME/.bashrc"

    # Apply .bashrc changes immediately for the user
    source "/home/$USERNAME/.bashrc"

    # Enable serial console service (ttyS0)
    echo "Configuring serial console service..."; sleep 2;
    sudo touch /lib/systemd/system/ttyS0.service
    sudo bash -c "cat <<EOF > /lib/systemd/system/ttyS0.service
[Unit]
Description=Serial Console Service

[Service]
ExecStart=/sbin/getty -L 115200 ttyS0 vt102
Restart=always

[Install]
WantedBy=multi-user.target
EOF"
    sudo chmod 644 /lib/systemd/system/ttyS0.service
    sudo systemctl daemon-reload
    sudo systemctl enable ttyS0.service

    # Install dependencies and Docker
    echo "Installing system dependencies and Docker..."; sleep 4;
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y mc apt-transport-https ca-certificates curl software-properties-common

    # Add Docker GPG key and repo, then install Docker
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update && sudo apt install -y docker-ce
    sudo usermod -aG docker "$USERNAME"

    # Install extra software packages
    echo "Installing extra software..."; sleep 2;
    sudo apt install -y tmux mc ranger qemu-guest-agent spice-vdagent
    ranger --copy-config=rc
    echo "set show_hidden true" >> "/home/$USERNAME/.config/ranger/rc.conf"

    # Install lazydocker
    echo "Installing lazydocker..."; sleep 2;
    curl https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash

    # Add TMUX and FRIENDS
    bash << 'TMUXSETUP'
clear
echo -e "INSTALL TMUX and FRIENDS\n\n"
sleep 1
sudo apt install -y tmux git xsel
sleep 1
clear
echo -e "Adding plugin manager to tmux: \n\n"
sleep 1
[ ! -d ~/.tmux/plugins/tpm ] && git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
touch ~/.tmux.conf
# Creating the tmux configuration file
cat > ~/.tmux.conf << 'EOF'
# 720 no scope pane switch
set -g mouse on

# Convert UTC to: Are we on Daylight savings time? In the Mountain timezone?
set -g status-right '#(TZ="America/Denver" date +%%H:%%M:%%S)'

# Scroll History
set -g history-limit 30000

# Default statusbar with less colors
set-option -g status-bg colour0
set-option -g status-fg colour7

# Ensures new panes or windows inherit the working directory of the current pane:
bind-key c new-window -c "#{pane_current_path}"
bind-key % split-window -h -c "#{pane_current_path}"
bind-key '"' split-window -v -c "#{pane_current_path}"

# Disabling prevents accidental resizing
setw -g aggressive-resize on

# Reduce repeat-time to 200 milliseconds (default is 500ms)
set-option -g repeat-time 200

# By default, searching in the scrollback requires entering "copy mode" with C-b [ and then entering reverse search mode with C-r. Searching is common, so give it a dedicated C-b r.
bind r {
copy-mode
command-prompt -i -p "(search up)" "send-keys -X search-backward-incremental '%%%'"
}

# Set ability to capture on start and restore on exit window data when running an application
setw -g alternate-screen on

# Lower escape timing from 500ms to 50ms for quicker response to scroll-buffer access.
set -s escape-time 50

# Start window numbering at 1 for easier switching
set -g base-index 1
setw -g pane-base-index 1

# Start numbering at 1
set -g base-index 1

# Default window title colors
set-window-option -g automatic-rename on

# Active window title colors
setw -g window-status-current-format "|#I:#W|"

# Change prefix command to C-z and unbind C-b
#set -g prefix C-z
#unbind C-b

# List of plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-yank'
set -g @plugin 'tmux-plugins/tmux-resurrect'

# Initialize TMUX plugin manager (keep this line at the very bottom of tmux.conf)
run '~/.tmux/plugins/tpm/tpm'
EOF
tmux source-file ~/.tmux.conf > /dev/null 2>&1
sleep 1; clear; printf 'To finish the job, you must open\n__tmux__\n\nand then hit \n__CTRL + b__\n\nthen within 2 seconds hit\n_I_ (capital I)\n ... this will install the plugin manager.\n\n'; sleep 1;
TMUXSETUP

    # Output completion message
    echo -e "\nAll tasks completed successfully!"

else

    # We need to create the user first, check if we have root privileges
        if [ "$(id -u)" -ne 0 ]; then
            echo "This script must be run as root when creating a new user."
            exit 1
        fi

    # Check if all parameters are provided
    if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [ -z "$GROUP" ] || [ -z "$SHELL" ] || [ -z "$FULL_NAME" ]; then
        echo "Usage: $0 <username> <password> <group> <shell> <full_name>"
        exit 1
    fi

    # Install Sudo if not present
    if ! command -v sudo &> /dev/null; then
        apt update
        apt install -y sudo
    fi

    # Check if the group exists, create it if not
    if ! getent group "$GROUP" > /dev/null 2>&1; then
        echo "Group '$GROUP' not found, creating it..."
        groupadd "$GROUP"
    fi

    # Create the user with the given parameters
    echo "Creating user '$USERNAME'..."; sleep 2;

    # The -m option creates the home directory, -s specifies the shell, -c specifies full name
    useradd -m -s "$SHELL" -c "$FULL_NAME" -g "$GROUP" "$USERNAME"

    # Set the password for the user (encrypted using the specified password)
    echo "$USERNAME:$PASSWORD" | chpasswd

    # Ensure the user's home directory has the correct permissions
    chown -R "$USERNAME":"$GROUP" "/home/$USERNAME"

    # Add user to sudo group and modify sudoers file for full sudo access
    echo "Adding user '$USERNAME' to sudo group..."
    usermod -aG sudo "$USERNAME"
    echo "$USERNAME    ALL=(ALL:ALL) ALL" | tee -a /etc/sudoers > /dev/null

    # Set up initial .bashrc configurations
    echo -e "\n\n# Save the history regardless of what window you're in" >> "/home/$USERNAME/.bashrc"
    echo "export PROMPT_COMMAND='history -a'" >> "/home/$USERNAME/.bashrc"
    echo -e "\n\n# Save the history size to a worthwhile amount" >> "/home/$USERNAME/.bashrc"
    echo "HISTSIZE=10000" >> "/home/$USERNAME/.bashrc"
    echo "HISTFILESIZE=20000" >> "/home/$USERNAME/.bashrc"

    # Add a function to kill all Docker containers
    echo -e '\nkillalldocker() {\n  docker stop $(docker ps -a -q) 2>/dev/null\n  docker rm $(docker ps -a -q) 2>/dev/null\n}' >> "/home/$USERNAME/.bashrc"

    # Add a function to start Docker containers with Docker Compose
    echo -e '\nstartupdocker() {\n  docker compose up --build -d && echo waiting for containers to come up... && while docker ps | grep "health: starting" > /dev/null; do sleep 1; done\n}' >> "/home/$USERNAME/.bashrc"

    # Switch to the new user
    echo "User '$USERNAME' created with all the specified configurations."
    cp $(sudo ps -u root -o pid,etime,comm | grep [.]sh | awk '{print $3}') /home/$USERNAME
    chmod 777 /home/$USERNAME/$(sudo ps -u root -o pid,etime,comm | grep [.]sh | awk '{print $3}')
    chown $USERNAME:$USERNAME /home/$USERNAME/$(sudo ps -u root -o pid,etime,comm | grep [.]sh | awk '{print $3}')
    echo "Switching to '$USERNAME'..."; sleep 2;
    echo "Please rerun the same command you just ran, but in your home directory:"
    echo "cd /home/$USERNAME/"
    bash -c "fc -ln -1"
    history 2
    su "$USERNAME" -
fi
```
</details> 

