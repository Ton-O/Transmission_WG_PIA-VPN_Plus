# Transmission_VPN_Plus
Transmission over PIA with Wireguard VPN with multiple download clients
## Purpose
This image is stored primarily for my __personal__ reference, but can be used freely by others.
It is based on a number of other ideas I picked up from github.
## What mkaes this image different from others?
1) It is a working solution for _Transmission over a Wiregiard based PIA VPN_ (Private Internet Access).
So far, I have not encountered a working solution with PIA and Wireguard.
2) It generates and spins up 9 transmission daemons __in parallel__. 
## Why so many clients? 
I've got a decent fiber internet connection (1GB) that I would like to make use of completely.
During my day-to-day expoerience with my normal client (above referred to a as 1)), I have noticed a serious limitation on CPU-resources, despite having a beefy XEON processor with 8 cores.
However, most (or is it all?) Torrent clients are based on the same framework called libtorrent (a.k.a. Rasterbar). Libtorrent simply uses only 1 CPU for all of its processing.... __Bye-bye to this nice 8-core XEON, we're only using one of them__. Once multiple downloads take off, you'll see CPU-usage of 1 core spiking to 100%. 
This is where nr 2) comes in. Having multiple Torrrent clients running in parallel allows Torrent downloads to use multiple CPU's in parallel, removing the CPU-bottleneck....
It also contains a shell script that "regulates downloads over multiple clients automatically". More over this later. 
## Sounds nice, but what's the catch?
There's one catch: PIA only allows 1 Port to be forwarded.
Okay.... so what?
Torrenting over a VPN means connecting to the outer world over 1 VPN IP-address to keep your torrent-traffic anonymouly. That IP-address can be used for al of the Torrent clients, so not issue there.
The issue arrises that PIA only provides one port for port forwarding. This port is requested by the software and registered with the base Transmission client (client is available on the local network via port 9091). The base Transmission client then "owns" this port, it cannot be shared with anything else. That means that all other Transmission clients, although communicating over the PIA VPN, they cannot make use of that same forwarded port.....
In-stead they are using a "dummy port" that they will be listening on, but that will never receive any incoming requests (as PIA only forwards one specific port).
### Okay, explain this in simpler words please.
You can add Torrents to all of the Transmission clients and they will download but only your base Torrent client will use active port forwarding, the rest will become "passive peers". 
Google AI explains this as follows:
The consequences of not forwarding a port in a torrent client in 2026 are as follows:
Limited Reachability (Passive Mode): Without port forwarding, your torrent client can only initiate connections to others (outbound). You cannot be reached by others (inbound).
No Connection with "Passive" Peers: Two users who both have not forwarded their ports cannot communicate with each other. This causes you to miss out on a portion of the "swarm" (the group of connected users), which is especially problematic for torrents with few seeders.
Lower Speeds: Because you are connected to fewer peers simultaneously, both your download and upload speeds will often be lower than they could be.
Poor Upload/Ratio: It is much harder to upload data (seeding) if you are not passively reachable. On private trackers, this can lead to issues maintaining your required upload ratio.
## So why use this solution at all?
I use this solution to DOWNLOAD torrents in parallel, once downloaded, I automatically move them over to the base Transmission client and UPLOAD there over an ACTIVE forwarded port. That way, I'm not constrained on CPU resource for downloads, but can upload them normally. 
## Okay, wanna try this?
I've uploaded the image to hub,docker to be used:
You need to setup the docker-compose.yml file with the appropriate prameters:
. volumes; obviously your transmission client needs to be configured externally and store the received data somewhere outside of the container.
. LOCAL_NETWORK; you need to specify the subnet of your internal (local) network here. something like 192.168.0.0/24 or so.
. LOC; the location you wopuld like the PIA VPN to connect to
- USER and PASS; you PIA credentials
. TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true; or false if you do not want your clients protected internally
. TRANSMISSION_RPC_USERNAME; a username  if you specify TRANSMISSION_RPC_AUTHENTICATION_REQUIRED=true
. TRANSMISSION_RPC_PASSWORD; the same.
. MY_INTERNAL_IP; specify the IP_address where the docker system is running. F.E. 192.168.0.17 

You can start the docker image using the normal docker compose statements and connect your transmission client through a web browser or other client (I Use transmission remote client) specifying the IP-address defined in MY_INTERNAL_IP, TRANSMISSION_RPC_USERNAME & TRANSMISSION_RPC_PASSWORD.
The base Transmission daemon will use port 9091, ports 9092 to 9099 are defined for the "passive torrent client".

## Script Distribute.sh... what's that for?
This script (located in the .scripts folder) performs the function to "regulate downloads over multiple clients automatically".
It is started automatically (with the argument "NORMAL"), then runs continuously in the background. 
There, it performs the following functions:
* A) checking the "passive clients" if any __download is completed__. 
* B) __Watching__ a so-called "Multi-watch" directory for any *.torrent file. 
* C) __DISTRIBUTE__ or __CONSOLIDATE__
A break down of functionality 
A): If it detects a completed download, it will stop the torrent in the client, start it in the "Active client" using the same download directory and priority. Once that's done, it removes the torrent from the passive client.
B) If it finds a torrent file, it will move that away from there, determines which passive client has the lowest number of downloads running and starts the torrent there (using the "default download" directory).
This "ping pong" between passive and active clients is executed every 60 seconds, meaning a newly placed or completed torrent is picked up within 1 minute.  
Functionality C) can be triggered manually _WITHIN_ the comntainer: bash /scripts/Distribute.sh <__DISTRIBUTE__ or __CONSOLIDATE__> (UPPERCASE ONLY).
- _DISTRIBUTE_ will move all Torrents that are downloading in the active client to one of the passive clients. This can be used to "offload" a constrained active daemon.
- _CONSOLIDATE_ The opposite of _DISTRIBUTE_; it moves all torrents with state DOWNLOAD back to the active Torrent Daemon.
Note that these functions need to be initiated by the user and will run only once. The function "NORMAL" is unaffected by this manual user intervention.  

# Any other drawback?
A small one: stopping a torrent in a passive client and moving it to the active one will reset the upload and download counters....Your torrent will start with 0 for both of them once moved to the active client.
# If you find this solution "a big fuzz over nothing": fine, just move on. 