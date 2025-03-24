#!/bin/bash


##################################
## Script Begins Warning/Checks ##
##################################

#  [main] -- Display script banner, delay, and initial warning
display_banner() {
    echo "=== Traefik + MacVLAN Setup ==="
    sleep 0.5
    
    if [ ! -f ".env" ]; then
        echo "A reboot will be required if this is your first time using systemd-networkd"
        sleep 0.25
        echo "   .::WARNING::    This Script Will Want to Reboot     ::WARNING::."
        echo " Please re-run script after reboot - reboot after script re-run pleasE"
        sleep 3
    fi
}


####################################
## No Root! Yes Docker! Sudo now! ##
####################################

#  [main] -- Check all prerequisites before proceeding
check_prerequisites() {
    # Prompt for sudo password
    sudo -v

    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo "Please do not run this script as root, it will use sudo when necessary"
        exit 1
    fi
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        echo "Docker was not found and is required to continue. This will install docker."
        read -p "Do you want to continue? (Y/n): " response

        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Exiting..."
            exit 1
        fi
        # Install Docker and clear screen
        install_docker
        clear
    fi
    
    # Check for Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo "Docker Compose is not installed, please install Docker Compose first."
        exit 1
    fi
    
    # Load the .env file if it exists
    if [ -f .env ]; then
        source .env
    fi
}

# Used in [check_prerequisites] -- Installs Docker if not present
install_docker() {
    sudo apt update
    sudo apt upgrade -y
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce
    sudo usermod -aG docker $USER
}


###################################################
## Prompt for configuration - Domain name to use ##
###################################################

#  [main] -- Configure the domain name
configure_domain() {
    if [ -z "$DOMAIN" ]; then
        echo "Enter Full Domain -- example: (subdomain1.example.com)"
        read -p "Enter domain name: " DOMAIN
    fi
}


#####################################
## Save networking info for script ##
#####################################

#  [main] -- Gather host network information for configuration
gather_network_info() {
    HOST_IP_SUBNET=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1)
    HOST_IP=$(ip -o -f inet addr show | awk '/scope global/ {print $4}' | head -n 1 | sed 's/...$//')
    HOST_GATEWAY=$(ip route | awk '/default/ { print $3 }')
    HOST_INTERFACE=$(ip route | awk '/default/ { print $5 }')
    HOST_SUBNET=$(ip route | awk "/$HOST_INTERFACE/" | awk '/kernel scope link/ { print $1 }')
}

#######################################################
# Generate systemd macvlan network configuration file #
#######################################################

#  [main] -- his one can clobber, the MacVLAN names dont change
generate_macvlan_systemd_network_file() {
    # Create the macvlan netdev file
    HOST_MACVLAN_SYSTEMD_FILE="/etc/systemd/network/25-traefik2docker.netdev"
    
    echo "[NetDev]
Name=traefik2docker
Kind=macvlan

[MACVLAN]
Mode=private" | sudo tee "$HOST_MACVLAN_SYSTEMD_FILE" > /dev/null

}


########################################################
# Check/create/modify systemd-networkd interface files #
########################################################

#  [main] -- Was the env var HOST_INTERFACE_NEW set? Is this pre- or post- reboot? BOOLEAN_INTERFACE_RENAME_FILE will tell us!
configure_host_interface_systemd_files() {
    BOOLEAN_INTERFACE_RENAME_FILE=$(find "/etc/systemd/network/" -maxdepth 1 -type f -name "10-*-renamed-*.link")
    
    if [[ -z "${BOOLEAN_INTERFACE_RENAME_FILE}" ]]; then
        # PRE-REBOOT: Configure network interfaces
        configure_prereboot_systemd_network
    else
        # POST-REBOOT: Get interface name from existing config
        HOST_INTERFACE_NEW=$(find "/etc/systemd/network/" -maxdepth 1 -type f -name "10-*-renamed-*.link" | awk -F'renamed-|\.link' '{print $2}')
    fi
}

# Used in [configure_host_interface_systemd_files] -- Configures systemd's interface for the host network settings
configure_prereboot_systemd_network() {
    # Create host interface network file
    HOST_INTERFACE_SYSTEMD_FILE="/etc/systemd/network/20-$(echo "$HOST_INTERFACE").network"
    
    # Check if running in LXC container, this function also obtains HOST_INTERFACE_MATCH
    check_virtualization
    
    # Create network interface file for the macvlan
    echo "[Match]
Name=$HOST_INTERFACE_MATCH

[Network]
# Added the macvlan as a secondary device
MACVLAN=traefik2docker" | sudo tee "$HOST_INTERFACE_SYSTEMD_FILE" > /dev/null
    
    # Prompt for new a interface name and modify the host interface's config to DHCP
    prompt_interface_rename
}


######################################################
## LXC still using host resources, small adjustment ##
######################################################

# Used in [configure_prereboot_systemd_network] -- Checks if system is running in virtualization
check_virtualization() {
    # Check if virt-what is installed, then install it
    sudo virt-what > /dev/null 2>&1 || sudo apt install virt-what > /dev/null 2>&1
    
    # Check if in LXC container
    if sudo virt-what | grep -q "lxc"; then
        HOST_INTERFACE_MATCH="$HOST_INTERFACE"
    else
        # System is not in LXC container, get the hardware name of the interface
        HOST_INTERFACE_MATCH=$(ip a | awk '/altname/ { print $2 }')
    fi
}


##############################################################
## Prompt for configuration - Host network interface's name ##
##############################################################

# Used in [configure_prereboot_systemd_network] -- Prompt for interface rename, this doesnt need to be a choice, but I made it a nonmandatory one.
prompt_interface_rename() {
    echo -e "Renaming the host interface responsible for the MacVLAN\n\n########## This--must--begin--with--a--letter ##########\nType in a name for the interface connecting with traefik's MacVLAN -- example: (host_network)"
    read -p "Enter interface name: " HOST_INTERFACE_NEW
    HOST_INTERFACE_NEW=${HOST_INTERFACE_NEW:-host_network}
    
    # Create interface rename file
    MACaddr=$(ip link show $(echo "$HOST_INTERFACE") | grep -o -E ..:..:..:..:..:.. | head -n 1)
    sudo bash -c "cat <<EOF > /etc/systemd/network/10-$(echo "$HOST_INTERFACE")-renamed-$(echo "$HOST_INTERFACE_NEW").link
[Match]
MACAddress=$MACaddr

[Link]
Name=$HOST_INTERFACE_NEW
EOF"
    
    # Add DHCP to to the host interface's config, that interface is fully systemd-networkd now. So the ifupdown2 will no longer be getting an IP address.
    sudo sed -i '/\[Network\]/a DHCP=yes' /etc/systemd/network/20-$(echo "$HOST_INTERFACE").network
}


###############################################
## Obtain a free IP for Traefik's MacVLAN IP ##
###############################################

#  [main] -- Setup MacVLAN IP address for Traefik - This will find your IP, and try and add increment two digits in the last octet. Ping checks to see was the IP is taken
setup_macvlan_ip() {
    # Attempt auto-assignment of IP
    if ping -c1 -w3 $(echo "$HOST_IP" | awk -F '.' '{print $1 "." $2 "." $3 "." $4+2}') >/dev/null 2>&1; then
        echo "Please enter new IP address in subnet $(echo "$HOST_IP_SUBNET"), attempted IP Address already allocated" >&2
        read -p "Enter IP address of traefik: " TRAEFIK_MACVLAN_IP
    else
        TRAEFIK_MACVLAN_IP=$(echo "$HOST_IP" | awk -F '.' '{print $1 "." $2 "." $3 "." $4+2}') >/dev/null 2>&1
    fi
}


#########################################
## Dump current env var values to file ##
#########################################

#  [main] -- Create or update .env file with current settings
update_env_file() {
    cat > .env <<EOL
DOMAIN=${DOMAIN}
HOST_IP_SUBNET=${HOST_IP_SUBNET}
HOST_IP=${HOST_IP}
HOST_GATEWAY=${HOST_GATEWAY}
HOST_SUBNET=${HOST_SUBNET}
HOST_INTERFACE=${HOST_INTERFACE}
HOST_INTERFACE_MATCH=${HOST_INTERFACE_MATCH}
HOST_INTERFACE_SYSTEMD_FILE=${HOST_INTERFACE_SYSTEMD_FILE}
BOOLEAN_INTERFACE_RENAME_FILE=${BOOLEAN_INTERFACE_RENAME_FILE}
HOST_MACVLAN_SYSTEMD_FILE=${HOST_MACVLAN_SYSTEMD_FILE}
HOST_INTERFACE_NEW=${HOST_INTERFACE_NEW}
TRAEFIK_MACVLAN_IP=${TRAEFIK_MACVLAN_IP}
EOL
}


########################################################
## New IP - countdown_and_reboot - disable networking ##
########################################################

#  [main] -- Handle systemd-networkd activation and reboot if needed
handle_reboot() {
    if systemctl is-enabled --quiet systemd-networkd; then
        echo "systemd-networkd is already enabled." | logger
    else
        echo "systemd-networkd is not enabled. Enabling it now..."
        sudo systemctl enable systemd-networkd
        echo "systemd-networkd has been enabled."
        echo "ifupdown2's networking service must now become disabled..."
        echo -e "############################################################################################\nThis script will attempt to reboot your machine now.\n############################################################################################"
        sleep 0.5
        echo -e "################      Please re-run this script after reboot finishes.      ################\n###########################################################################################"
        sleep 1.5
        echo "====You May Get A New IP Address Upon Reboot===="
        sleep 1
        # Demo reboot in seconds and do heavy lifting of disabling Debian default networking and disablabling the service that makes everything wait 5min until networking is up
        countdown_and_reboot
    fi
}

# Used in [handle_reboot] -- Countdown and give the user a chance to cancel the script before it disables Debian default networking and reboots
countdown_and_reboot() {
    echo -e "Rebooting in 7 seconds......."
    sleep 1
    echo -e "Rebooting in 6 seconds......"
    sleep 1
    echo -e "Rebooting in 5 seconds....."
    sleep 1
    echo -e "Rebooting in 4 seconds...."
    sleep 1
    echo -e "Rebooting in 3 seconds..."
    sleep 1
    echo -e "Rebooting in 2 seconds.."
    sleep 1
    echo -e "Rebooting in less than 1 second."
    sleep 0.5
    echo -e "\n##############################\n    ###### REBOOTING ######\n##############################"
    # "There can be only one... [networking stack]"  - Connor MacLeod
    sudo systemctl disable networking
    sudo systemctl disable ifupdown-wait-online.service
    sleep 1
    sudo reboot
}


###############################
## Establish Docker Networks ##
###############################

#  [main] -- Setup Docker networks
setup_docker_networks() {
    # Create traefik_proxy_net if it doesn't exist
    if ! docker network inspect traefik_proxy_net >/dev/null 2>&1; then
        echo "Creating internal docker network: traefik_proxy_net"
        docker network create traefik_proxy_net
    fi
    
    # Create traefik2host MacVLAN network if it doesn't exist
    if ! docker network inspect traefik2host >/dev/null 2>&1; then
        echo "Creating MacVLAN docker network: traefik2host"
        docker network create -d macvlan --subnet="${HOST_SUBNET}" --gateway="${HOST_GATEWAY}" -o parent=traefik2docker traefik2host || {
            echo "Error: Failed to create the Docker network. Please re-run the script after a reboot has finished."
            exit 1
        }
    fi
}



############ END CONFIGURATION ############
###########################################
########## BEGIN FILE MANAGEMENT ##########



##################################################################################################################################
## If you downloaded this repo from Github I left some example files up, you dont need them - this should, cleanly, remove them ##
##################################################################################################################################

#  [main] -- Clean up extra files from GitHub download
cleanup_github_files() {
    local extra_git_dir="./etc/systemd/network"
    local files=(
        "$extra_git_dir/20-ens18.network"
        "$extra_git_dir/25-traefik2docker.netdev"
    )

    # Remove files if they exist
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            rm "$file" &>/dev/null
        fi
    done

    # Remove the directory only if it exists and is the intended directory
    if [ -d "$extra_git_dir" ] && [ "$extra_git_dir" != "/" ] && [ "$extra_git_dir" != "." ]; then
        # Additional check to avoid removing important directories
        if [[ "$extra_git_dir" != /* ]]; then # Another check to avoid causing a bad day
            rm -r "$extra_git_dir"
        else
            echo "Warning: Refusing to remove absolute path: $extra_git_dir"
        fi
    fi
}


#########################################################
## If you didnt download this from Github, it will now ##
#########################################################

#  [main] -- Verify and download required files
verify_required_files() {
    REPO_URL="https://raw.githubusercontent.com/MarcusHoltz/Traefik-MacVLAN/refs/heads/main"
    
    # List of directories to check/create
    directories=(
        "./traefik"
        "./promtail"
        "./grafana"
        "./grafana/provisioning"
        "./grafana/provisioning/dashboards"
        "./grafana/provisioning/datasources"
    )
    
    # List of files to check/download
    files=(
        "./docker-compose.yml"
        "./traefik/traefik.yml"
        "./promtail/promtail-config.yml"
        "./grafana/provisioning/datasources/ds.yaml"
        "./grafana/provisioning/dashboards/dashboard.yaml"
        "./grafana/provisioning/dashboards/Webanalytics.json"
    )
    
    # Create directories
    echo "Checking and creating directories..." | logger
    for dir in "${directories[@]}"; do
        create_directory "$dir" || exit 1
    done
    
    # Download files
    echo "Checking and downloading files..." | logger
    for file in "${files[@]}"; do
        download_file "$file" || exit 1
    done
}

# Used in [verify_required_files] -- Create a directory if it doesn't exist
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

# Used in [verify_required_files] -- Download a file if it doesn't exist
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


########################################
## Reqired File - Up to Date Download ##
########################################

#  [main] -- Check for GeoLite2 database and download if missing
check_geolite_db() {
    if [ ! -f "./promtail/GeoLite2-City.mmdb" ]; then
        echo "GeoLite2-City.mmdb was not found in the ./promtail directory!"
        echo "You need GeoLite2-City.mmdb downloaded before running Docker!"
        echo ""
        sleep 1.5      
        echo -e "GeoLite2-City.mmdb was not found and is required to continue.\nWould you like me to automatically download it for you so we can proceed?"
        read -p "Do you want to continue? (Y/n): " response
        
        if [[ "$response" =~ ^[Nn]$ ]]; then
            echo "Exiting..."
            exit 1
        else
            wget -P ./promtail https://git.io/GeoLite2-City.mmdb
        fi
    fi
}


################################################
## Bake your recipe - now with Docker Compose ## 
################################################

#  [main] -- Run Docker Compose
run_docker_compose() {
    echo "Environment setup complete... running Docker"
    docker compose up -d || docker-compose up -d
}


######################
## Dashboard of DNS ##
######################

#  [main] -- Prints out reminders to the user on what may need to be done next and what was accomplished
congratulations_and_reminders() {
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
echo "- Traefik Dashboard:    http://traefik.${DOMAIN}"
echo "- Cat Meme Portal:      http://catapp.${DOMAIN}"
echo "- Grafana Dashboard:    http://grafana.${DOMAIN}"
echo "- Portainer UI:         http://portainer.${DOMAIN}"
echo "- Error Pages:          http://error.${DOMAIN}"
echo "- Whoami1 Page:         http://whoami1.${DOMAIN}"
echo "- Whoami2 Page:         http://whoami2.${DOMAIN}"
echo "- Nginx Catch All:      http://anything.${DOMAIN}"
}


################################
## Run the Functions in Order ##
################################

# Main function to orchestrate the entire process
main() {
    # Exit on any error
    set -e
    
    # Display banner and initial warning
    display_banner
    
echo "    # Check prerequisites"
    check_prerequisites
    
echo "    # Configure domain"
    configure_domain
    
echo "    # Gather network information"
    gather_network_info
    
echo "    # Generate macvlan systemd network file"
    generate_macvlan_systemd_network_file
    
echo "    # Setup MacVLAN IP"
    setup_macvlan_ip
    
echo "    # Update .env file with current settings"
    update_env_file
    
echo "    # Handle reboot if needed"
    handle_reboot
    
echo "    # Setup Docker networks"
    setup_docker_networks
    
echo "    # Clean up extra files"
    cleanup_github_files
    
echo "    # Verify and download required files"
    verify_required_files
    
echo "    # Check for GeoLite2 database"
    check_geolite_db
    
echo "    # Run Docker Compose"
    run_docker_compose

#echo "    # Displays a little board reminding of all DNS"
    congratulations_and_reminders
}

# Execute main function
main

# # Have a great day! :)
