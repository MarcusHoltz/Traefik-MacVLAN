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


