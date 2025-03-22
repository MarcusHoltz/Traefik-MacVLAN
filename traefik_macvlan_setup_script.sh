#!/bin/bash

##################################
## Script Begins Warning/Checks ##
##################################
# # Exit on any error
set -e

# # Warn user about the script they're running and what they're getting into
echo "=== Traefik + MacVLAN Setup ==="
sleep .5;

if [ ! -f ".env" ]; then
  echo "A reboot will be required if this is your first time using systemd-networkd"
  sleep .25;
  echo "   .::WARNING::     This Script Will Want to Reboot      ::WARNING::."
  echo ""
  sleep 3.25;
fi

# # Prompt the user for sudo even if the script isn't run with sudo
sudo -v  # This will prompt for sudo password, but doesn't run any command


# # Check if running as root
if [ "$EUID" -eq 0 ]; then
  echo "Please do not run this script as root, it will use sudo when necessary"
  exit 1
fi


# # Check for required software: Docker
if ! command -v docker &> /dev/null; then
  echo "Docker was no found and is required to continue. This will install docker."
  read -p "Do you want to continue? (Y/n): " response

  if [[ "$response" =~ ^[Nn]$ ]]; then
    echo "Exiting..."
    exit 1
  fi
  sudo apt update
  sudo apt upgrade -y
  sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
  curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce
  sudo usermod -aG docker $USER
# # Clear the screen full of update messages
clear
fi

# # Check for required software: Docker-Compose or Docker compose plugin
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
  echo "Docker Compose is not installed, please install Docker Compose first."
  exit 1
fi

# # Load the .env file to make sure some variables are available
if [ -f .env ]; then
  source .env
fi



#################################
### Prompt for configuration ###
#################################
# # Check if DOMAIN is set, if not prompt the user to enter it
###### Prompt 1 ###### -- ENTER DOMAIN NAME
if [ -z "$DOMAIN" ]; then
echo "Enter Full Domain -- example: (subdomain1.example.com)"
  read -p "Enter domain name: " DOMAIN
fi

# # Output the DOMAIN value, before and after reboot incase user forgot
echo "DOMAIN is set to:  $DOMAIN"



#####################################
## Save networking info for script ##
#####################################
# # Save IP Address information for use later in script
  HOST_IP_SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)
  HOST_IP=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1 | sed 's/...$//')
  HOST_GATEWAY=$(ip route | awk '/default/ { print $3 }')
  HOST_INTERFACE=$(ip route | awk '/default/ { print $5 }')
  HOST_INTERFACE_MATCH=$(ip a | awk '/altname/ { print $2 }')
  HOST_SUBNET=$(ip route | awk "/$HOST_INTERFACE/" | awk '/kernel scope link/ { print $1 }')



####################################
## Generate Systemd network files ##
####################################
# # This one can clobber, the MacVLAN names dont change
# # # The traefik2docker name doesnt change
HOST_MACVLAN_SYSTEMD_FILE="/etc/systemd/network/25-traefik2docker.netdev"

# # Create the traefik2docker file with the desired content
echo "[NetDev]
Name=traefik2docker
Kind=macvlan

[MACVLAN]
Mode=private" | sudo tee "$HOST_MACVLAN_SYSTEMD_FILE" > /dev/null



###################################################
## Check for pre-configured files, before reboot ##
###################################################
# # Was the env var HOST_INTERFACE_NEW set? Is this pre- or post- reboot?
BOOLEAN_INTERFACE_RENAME_FILE=$(find "/etc/systemd/network/" -maxdepth 1 -type f -name "10-*-renamed-*.link")
if [[ -z "${BOOLEAN_INTERFACE_RENAME_FILE}" ]]; then

# # THIS SECTION EXECUTES - if - this is pre-reboot, first time running script.
# # # Create the Host Interface network file if this is the first time being networkd is being ran
HOST_INTERFACE_SYSTEMD_FILE="/etc/systemd/network/20-$(echo "$HOST_INTERFACE").network"

# # # Create the network interface file for the additional macvlan
echo "[Match]
Name=$HOST_INTERFACE_MATCH

[Network]
# Added the macvlan as a secondary device
MACVLAN=traefik2docker" | sudo tee "$HOST_INTERFACE_SYSTEMD_FILE" > /dev/null



#################################
### Prompt for configuration ###
#################################
# # Prompt user for the new interface name, or defaults to host_network
echo -e "Renaming the host interface responsible for the MacVLAN\n------------------------------------------\nType in a name for the interface connecting with traefik's MacVLAN -- example: (host_network)"
###### Prompt 2 ###### -- RENAME HOST INTERFACE
  read -p "Enter interface name: " HOST_INTERFACE_NEW
    HOST_INTERFACE_NEW=${HOST_INTERFACE_NEW:-host_network}

MACaddr=$(ip link show $(echo "$HOST_INTERFACE") | grep -o -E ..:..:..:..:..:.. | head -n 1) && sudo bash -c "cat <<EOF > /etc/systemd/network/10-$(echo "$HOST_INTERFACE")-renamed-$(echo "$HOST_INTERFACE_NEW").link
[Match]
MACAddress=$MACaddr

[Link]
Name=$HOST_INTERFACE_NEW
EOF" && sudo sed -i '/\[Network\]/a DHCP=yes' /etc/systemd/network/20-$(echo "$HOST_INTERFACE").network
else

# # THIS SECTION EXECUTES - if - this is post-reboot, after running script and generating config files
# # # Assign the env var of HOST_INTERFACE_NEW from the value in the filename 
HOST_INTERFACE_NEW=$(find "/etc/systemd/network/" -maxdepth 1 -type f -name "10-*-renamed-*.link" | awk -F'renamed-|\.link' '{print $2}')
fi



#####################################
## Assign an IP to Traefik MacVLAN ##
#####################################
# # Attempt to auto-assign an IP to Traefik's MacVLAN
# # #  This will find your IP, and try and add increment two digits in the last octet. Ping checks to see was the IP is taken
###### Possible Prompt 3 ###### -- ENTER TRAEFIK IP ADDRESS
if ping -c1 -w3 $(echo "$HOST_IP" | awk -F '.' '{print $1 "." $2 "." $3 "." $4+2}') >/dev/null 2>&1
then
    echo "Please enter new IP address in subnet $(echo "$HOST_IP_SUBNET"), attempted IP Address already allocated" >&2

    read -p "Enter IP address of traefik: " TRAEFIK_MACVLAN_IP
else
    TRAEFIK_MACVLAN_IP=$(echo "$HOST_IP" | awk -F '.' '{print $1 "." $2 "." $3 "." $4+2}') >/dev/null 2>&1
fi



######################
## Create .env file ##
######################
# # Save the values used up to this point in an .env file
cat > .env <<EOL
DOMAIN=${DOMAIN}
HOST_IP_SUBNET=${HOST_IP_SUBNET}
HOST_IP=${HOST_IP}
HOST_GATEWAY=${HOST_GATEWAY}
HOST_SUBNET=${HOST_SUBNET}
HOST_INTERFACE=${HOST_INTERFACE}
HOST_INTERFACE_MATCH=${HOST_INTERFACE_MATCH}
HOST_INTERFACE_SYSTEMD_FILE=${HOST_INTERFACE_SYSTEMD_FILE}
HOST_INTERFACE_RENAME_FILE=${HOST_INTERFACE_RENAME_FILE}
HOST_MACVLAN_SYSTEMD_FILE=${HOST_MACVLAN_SYSTEMD_FILE}
HOST_INTERFACE_NEW=${HOST_INTERFACE_NEW}
TRAEFIK_MACVLAN_IP=${TRAEFIK_MACVLAN_IP}
EOL



#########################################
## Reboot to activate systemd-networkd ##
#########################################
# # I cannot find a way to hot-plug in the new MacVLAN
# # # Device events for already existing devices need re-run at system startup, cold-plugging in the new MacVLAN
# # # # Reboot required
if systemctl is-enabled --quiet systemd-networkd; then
    echo "systemd-networkd is already enabled." | logger
else
    echo "systemd-networkd is not enabled. Enabling it now..."
    sudo systemctl enable systemd-networkd
    echo "systemd-networkd has been enabled."
    echo "====You May Get A New IP Address Upon Reboot===="
    echo -e "####################################################\nThis script will attempt to reboot your machine now.\n####################################################"; sleep .5; 
    echo -e "Rebooting in 7 seconds......."; sleep 1.5; echo -e "Rebooting in 6 seconds......"; sleep 1.5; 
    echo -e "Rebooting in 5 seconds....."; sleep 1.5; echo -e "Rebooting in 4 seconds...."; sleep 1.5; 
    echo -e "Rebooting in 3 seconds..."; sleep 1.5; echo -e "Rebooting in 2 seconds.."; sleep 2; 
    echo -e "Rebooting in less than 1 second."; sleep 1; echo -e "\n##############################\n    ###### REBOOTING ######\n##############################"; sleep 5; sudo reboot;
fi



#######################################################################
## This section will create the Docker networks if they do not exist ##
#######################################################################
# # Create Docker network traefik_proxy_net
# # # traefik_proxy_net is an internal docker network for container to container communications
if ! docker network inspect traefik_proxy_net >/dev/null 2>&1; then
  echo "Creating internal docker network: traefik_proxy_net"
  docker network create traefik_proxy_net
fi

# # Create Docker network traefik2host
# # # traefik2host is a MacVLAN docker network that is built on the host's upstream gateway's interface 
if ! docker network inspect traefik2host >/dev/null 2>&1; then
# # # # Attempt to create the Docker network and check if it fails
  echo "Creating MacVLAN docker network: traefik2host"
  docker network create -d macvlan --subnet="${HOST_SUBNET}" --gateway="${HOST_GATEWAY}" -o parent=traefik2docker traefik2host || {
# # # # If the command fails, print an error message reminder the user - reboot.
      echo "Error: Failed to create the Docker network. Please re-run the script after a reboot has finished."
      exit 1
  }
fi

###########################################
############ END CONFIGURATION ############
###########################################






##################################################
## Clean up files if you downloaded from Github ##
##################################################
# # If you downloaded this repo from Github
# # # Sample files were included in the repo for demo content
extra_git_dir="./etc/systemd/network"
files=(
    "$extra_git_dir/20-ens18.network"
    "$extra_git_dir/25-traefik2docker.netdev"
)

# # Remove files if they exist
for file in "${files[@]}"; do
    [ -f "$file" ] && rm "$file" &>/dev/null
done

# # Remove from the base of the extra git downloads directory
[ -d "$extra_git_dir" ] && rm -r "$(echo "$extra_git_dir" | cut -d'/' -f1,2)"



####################################################
## Verify files needed from Github repo are there ##
####################################################
# # This is basically a downloader for my Github repo
# # # Verify the files for docker-compose are there
REPO_URL="https://raw.githubusercontent.com/MarcusHoltz/Traefik-MacVLAN/refs/heads/main/"

# # List of directories to check/create
directories=(
  "./traefik"
  "./promtail"
  "./grafana"
  "./grafana/datasources"
  "./grafana/provisioning"
  "./grafana/provisioning/dashboards"
)

# # List of files to check/download
files=(
  "./docker-compose.yml"
  "./traefik/traefik.yml"
  "./promtail/promtail-config.yml"
  "./grafana/datasources/ds.yaml"
  "./grafana/provisioning/dashboards/dashboard.yaml"
  "./grafana/provisioning/dashboards/Webanalytics.json"
)

# # Create a directory if it doesn't exist, messages go to logs
create_directory() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    if [ $? -eq 0 ]; then
      echo "Successfully created directory: $dir" | logger
    else
      echo "Error: Failed to create directory: $dir" | logger
      return 1
    fi
  else
    echo "Directory already exists: $dir" | logger
  fi
}

# # Download the files if they doesn't exist
download_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "Downloading file: $file" | logger
    wget -q "$REPO_URL/$file" -O "$file"
    if [ $? -eq 0 ]; then
      echo "Successfully downloaded file: $file" | logger
    else
      echo "Error: Failed to download file: $file" | logger
      return 1
    fi
  else
    echo "File already exists: $file" | logger
  fi
}

# # Create directories
echo "Checking and creating directories..." | logger
for dir in "${directories[@]}"; do
  create_directory "$dir" || exit 1
done

# # Download files
echo "Checking and downloading files..." | logger
for file in "${files[@]}"; do
  download_file "$file" || exit 1
done


# # Check for GeoLite2-City.mmdb
if [ ! -f "./promtail/GeoLite2-City.mmdb" ]; then
  echo "GeoLite2-City.mmdb was not found in the ./promtail directory!"
  echo "You still need GeoLite2-City.mmdb downloaded before running Docker"
  echo ""
  echo "Please visit: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data"
  echo ""
  echo "Sign up, and download: GeoLite2-City.mmdb"
  echo "Place GeoLite2-City.mmdb in the ./promtail directory"
  echo "Then re-run this script."
  echo ""
  sleep 15;
  echo -e "GeoLite2-City.mmdb was not found and is required to continue.\nBut, for testing, would you like to proceed?"
    read -p "Do you want to continue? (Y/n): " response
    if [[ "$response" =~ ^[Nn]$ ]]; then
      echo "Exiting..."
      exit 1
    fi
fi

echo "Environment setup complete... running Docker"



########################
## Run Docker-Compose ##
########################
# # Download some docker images and bring up containers
docker compose up -d || docker-compose up -d



####################################################
###############  THIS   SECTION  ###################
####################################################
##  Prints out reminders to the user on what may  ##
## need to be done next and what was accomplished ##
####################################################
echo ""
echo "Make sure your DNS records have a wildcard record pointing to ${TRAEFIK_MACVLAN_IP} for:"
echo "*.${DOMAIN}"
echo ""
echo "Or you must create a DNS entry for the following sub-domains, pointing to: ${TRAEFIK_MACVLAN_IP}"
echo "  catapp.${DOMAIN}"
echo "  traefik.${DOMAIN}"
echo "  grafana.${DOMAIN}"
echo "  error.${DOMAIN}"
echo "  portainer.${DOMAIN}"
echo "  whoami1.${DOMAIN}"
echo "  whoami2.${DOMAIN}"
echo "  anything.${DOMAIN}"
echo ""
echo "You can access your applications at:"
echo "- Traefik Dashboard:    http://traefik-dashboard.${DOMAIN}"
echo "- Cat Meme Portal:      http://catapp.${DOMAIN}"
echo "- Grafana Dashboard:    http://grafana.${DOMAIN}"
echo "- Portainer UI:         http://portainer.${DOMAIN}"
echo "- Error Pages:          http://error.${DOMAIN}"
echo "- Whoami1 Page:         http://whoami1.${DOMAIN}"
echo "- Whoami2 Page:         http://whoami2.${DOMAIN}"
echo "- Nginx Catch All:      http://anything.${DOMAIN}"
# # Have a great day! :)
