# Setting Up Docker MacVLAN Network for Traefik's Access Log Analytics from Promtail/Loki/Grafana: A Comprehensive Guide

I am working to pass the source IPs coming in to the containers in docker. As far as I understand this is not possible in bridge mode.
It is possible with a MacVLAN.

For a complete yet simple example, visit https://github.com/oglimmer/traefik-loki-grafana-web-analytics.

For the full guide that goes along with this repo, visit [https://blog.holtzweb.com](#urlhere).

## Demo 

![Traefik Docker MacVLAN Demo of Script Running](https://raw.githubusercontent.com/MarcusHoltz/marcusholtz.github.io/refs/heads/main/assets/img/posts/traefik_docker_macvlan_demo.gif)

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


