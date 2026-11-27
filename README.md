# eduMEET room connector

This repository connects SIP room systems to eduMEET meetings. A room system is a hardware
videoconferencing terminal in a meeting room, for example from Cisco or Poly. The connector
uses [SIPMediaGW](https://github.com/Renater/SIPMediaGW), a gateway that RENATER developed.

This repository does not contain the gateway code. It contains the files to deploy SIPMediaGW
for eduMEET: configuration, scripts and the eduMEET branding.

The gateway code comes from the fork [edumeet/edumeet-sipmediagw](https://github.com/edumeet/edumeet-sipmediagw).
`SIPMEDIAGW_VERSION` holds the tag of the version to deploy. See [Update SIPMediaGW](#update-sipmediagw).

## How it works

Each call uses one gateway container. The container holds two programs:

- `baresip`, a SIP client. It answers the call from the room system.
- Chromium. It joins the eduMEET meeting as a normal participant.

The camera and microphone of Chromium are the video and audio of the room system. The screen and
the sound of Chromium go back to the room system. The room system shows the eduMEET page as
Chromium shows it.

A person in the room controls the call from a phone:

1. The room system calls `sip.example.org`. Save this address once in the contacts of the room
   system.
2. The room screen shows a QR code, a pairing code, and the time that is left to choose a meeting.
3. The person opens the QR code on a phone and enters the pairing code.
4. The person selects the eduMEET instance and enters the name of the meeting on the phone.
5. The gateway joins the meeting. The phone controls the microphone, the camera, the chat and the
   raised hand.
6. The person ends the call on the phone or on the room system.

If nobody chooses a meeting in 5 minutes (`IVR_TIMEOUT`), the call ends and the gateway is free
again. The room screen counts down the time.

After each call, the gateway container stops. A new container takes its place after approximately
15 seconds.

## Call addresses

The usual address is `sip.example.org`, with the QR code (see [How it works](#how-it-works)). The part
before `@` can also give a code, and the meeting:

| Address | Result |
| --- | --- |
| `sip.example.org` | The room screen and the phone show all the listed instances. The person selects the instance and the meeting on the phone. |
| `example@sip.example.org` | The room screen and the phone show only the instances of the group `example`. If the group has one instance, it is selected. |
| `example.lecture1@sip.example.org` | The same, and the gateway joins the meeting `lecture1` on the instance that is selected. |
| `12.lecture1@sip.example.org` | The meeting `lecture1` on the instance number 12, for a keypad with digits only. |

- A code is the name of a group of instances. Each instance is in the group of its own key, and in
  the groups of its `groups` field (see [eduMEET instances](#edumeet-instances)). Upper case and
  lower case letters are the same.
- The number is the position of the instance among the listed instances of `webrtc_domains.json`.
  With a code, the numbers are the positions in the group.
- A meeting name can contain dots.
- A room system that cannot call an address without a part before `@` calls `0@sip.example.org`.
- When all the gateways are in a call, or start again after a call (about 10 seconds), the room
  system gets `486 Busy Here`. Call again later.

## Parts

| Part | Where | What it does |
| --- | --- | --- |
| Kamailio and MySQL | central host | SIP server. It sends each incoming call to a free gateway. |
| Proxy and Redis | central host | Phone pages, pairing codes, commands from the phone to the gateways. It also serves the gateway assets. |
| nginx | central host | HTTPS for the phone pages. |
| Gateway containers | gateway hosts | One container for each call. |
| `HTTPLauncher` | gateway hosts | Receives the commands from the proxy and runs them in the gateway containers. |
| nginx | gateway hosts | HTTPS for the commands from the proxy. Only the central host can connect. |
| coturn | eduMEET media nodes | Relays the media between the room system and the gateway. |

On the central host, Kamailio, MySQL, the proxy and Redis run in Docker. nginx runs on the host,
not in Docker.

The build server builds the images of the gateways, Kamailio and the proxy. The hosts load them
and build nothing. See [Images](#images).

The gateway hosts can be in different networks and with different providers. All connections
between the central host and the gateway hosts go through the internet, with TLS:

- The gateways register with the proxy and get the assets through nginx on the central host.
- The gateways register with Kamailio with SIP over TLS. Kamailio sends the calls through the same
  connection.
- The proxy sends the commands to nginx on the gateway host, which passes them to `HTTPLauncher`.

## Requirements

- One central host with Ubuntu 24.04 or 26.04, nginx, certbot with its nginx plugin (`python3-certbot-nginx`),
  Docker Engine and the Docker Compose plugin, and a public IPv4 address.
- One or more gateway hosts with Ubuntu 24.04 or 26.04, nginx, certbot with its nginx plugin, Docker Engine and
  the Docker Compose plugin, and a public IPv4 address.
- 4 vCPU and 4 GB of memory for each gateway. A host with 32 vCPU runs 8 gateways. A host must not
  run more than 10 gateways.
- For each gateway host, an eduMEET media node near it with coturn, configured with a secret for
  the gateways. See [TURN on a media node](#turn-on-a-media-node).
- A DNS name for the central host and for each gateway host. See [DNS](#dns).

Kamailio sends each call to a free gateway on any gateway host. Put the gateway hosts in the EEA
only: a gateway receives the audio and video of the room.

## DNS

| Record | Value |
| --- | --- |
| `sip.example.org` A | The public IPv4 address of the central host |
| `node1.<org>.<country>.sip.example.org` A | The public IPv4 address of a gateway host, for example `node1.example.de.sip.example.org` |

The name of the central host:

- The room systems call SIP addresses at this name: port 5060 for SIP over UDP or TCP, port 5061
  for SIP over TLS.
- The QR code on the room screen opens `https://sip.example.org`.
- The gateways register at this name, with the proxy and with Kamailio.
- certbot gets the certificate for this name. nginx and Kamailio use it.

Use this name in `SIP_DOMAIN` (`central/kamailio.env`), and in `SIP_REGISTRAR`, `GW_PROXY`,
`GW_REVERSE_PROXY` and `ASSETS_URL` (`gateway.env`).

The name of a gateway host goes in `HOST_IP` (`gateway.env`). The proxy sends the commands to this
name. certbot on the gateway host gets the certificate for it.

Do not publish AAAA records. The service uses IPv4 only, and nginx on the gateway hosts allows the
IPv4 address of the central host only.

## Firewall

| From | To | Port | Purpose |
| --- | --- | --- | --- |
| Room systems | central host | 5060 UDP and TCP, 5061 TCP | SIP, SIP over TLS |
| Room systems | media node | 3478 UDP, 50000-60000 UDP | Media through coturn |
| Phones | central host | 80 TCP, 443 TCP | Phone pages |
| Gateway hosts | central host | 443 TCP | Registration with the proxy, assets |
| Gateway hosts | central host | 5061 TCP | SIP over TLS: registration and calls |
| Central host | gateway hosts | 443 TCP | Commands to the gateways |
| Let's Encrypt | central host, gateway hosts | 80 TCP | Certificate renewal |
| Gateway hosts | media node | 3478 UDP, 50000-60000 UDP | Media through coturn |
| Gateway hosts | eduMEET | 443 TCP and the media node ports | The meeting |

The proxy (port 9000) and `HTTPLauncher` (port 8100) listen on `127.0.0.1` only. On a gateway host,
nginx refuses all addresses except the central host on port 443.

`firewall.sh` sets the same rules in ufw, as on the eduMEET media nodes, so that a host is protected
also without the firewall of the provider. `install.sh` runs it when it sets up a gateway host;
`gateway-host/update.sh` leaves ufw as it is. After a change of `SSH_SOURCES` or `CENTRAL_IP`, run
`firewall.sh gateway` as root on the gateway host. On the central
host it is optional: use it only when you connect with SSH from the addresses in `SSH_SOURCES`.
Without it, the firewall of the provider must allow only the ports in the table above, and SSH.

- `firewall.sh central`: SSH from `SSH_SOURCES`. 80, 443 and 5061 TCP, and 5060 TCP and UDP, from
  all IPv4 addresses.
- `firewall.sh gateway`: SSH from `SSH_SOURCES`. 80 TCP from all IPv4 addresses. 443 TCP from
  `CENTRAL_IP` only.

All incoming IPv6 traffic is refused. The script replaces all ufw rules of the host. It stops if
your SSH session comes from an address that is not in `SSH_SOURCES`, so that it cannot cut you off.

Docker ports that are published on a public address bypass ufw. This setup publishes Docker ports on
`127.0.0.1` only.

## Allowed room systems

Only the room systems in the address table of Kamailio can call the gateways (`IPAUTH=True` in
`central/kamailio.env`). Kamailio refuses calls from other addresses with `403 Forbidden`. An empty
table refuses all calls. The addresses in the table can only call the gateways: Kamailio refuses
their requests for other SIP domains with `403 Not relaying`.

Add only the addresses of room systems or of their call control systems. Do not add the address of a
public SIP service (for example `sip.linphone.org`): all its users could then call the gateways.

### Add the room systems of an institution

1. Ask the institution how its room systems call outside:
   - directly, through the NAT of their network: Kamailio sees the public address of that NAT;
   - through a call control system (for example Cisco Unified CM with a Cisco Expressway-E, or a
     session border controller): Kamailio sees the public address of each Expressway-E or SBC node;
   - registered to a cloud service (for example Webex): see below.
2. Ask them to allow these outgoing connections:
   - TCP 5061 (SIP over TLS), or TCP and UDP 5060, to the central host;
   - UDP 3478 and UDP 50000-60000 to the TURN media node of each gateway host (any gateway can
     answer a call);
   - TCP 443 to the central host, for the phones.
3. Call `<code>@sip.example.org` from one room system. Kamailio refuses the call and writes the
   source address in its log. On the central host:

   ```sh
   journalctl -t kamailio --since "-15min" --no-pager | grep "refused" | grep -oE "Call from [0-9.]+" | sort | uniq -c
   ```

4. Make sure that the address belongs to the institution, for example with
   `whois <address> | grep -iE "netname|descr|org-name"`. If it belongs to a cloud service or a
   public SIP service, do not add it.
5. Add the address, the network of the room systems, or each node of the call control system:

   ```sh
   docker exec kamailio kamctl address add 1 192.0.2.10 32 0 example-university
   sleep 6
   docker exec kamailio kamctl address reload
   docker exec kamailio kamctl address dump
   ```

6. Call again. The room screen with the QR code comes up.

Use the narrowest entry: the address of the call control system or of the NAT of the room systems'
network, not the whole network of the institution. Every device in an entry can call the gateways.

Room systems that are registered to a cloud service call from addresses that the service shares
with all its customers. Do not add these addresses. The institution must send these calls through
its own call control system or SBC.

### Manage the table

- `1` is the group that Kamailio checks. Always use `1`.
- `192.0.2.0 24` is the address and the network mask. Use `32` for one address.
- `0` means all source ports.
- `example-university` is a label for the entry.

To show the entries that Kamailio uses: `docker exec kamailio kamctl address dump` (after a
`reload`). Do not use `kamctl address show`: it reads the database with the read-only user
`kamailioro`, which `kamdbctl` creates for local connections only, and Kamailio reaches MySQL
through the published port. Kamailio accepts one `reload` in 5 seconds: if it answers `ongoing
reload`, wait and run it again. To remove
an entry: `docker exec kamailio kamctl address rm 1 192.0.2.0`, then
`docker exec kamailio kamctl address reload`.

The table is in the MySQL database of Kamailio, so it stays after a restart.

The gateway hosts do not need an entry: they register with Kamailio with `SIP_SECRET`.

### Block SIP scanners

SIP scanners call public SIP servers without end, about once a second, from addresses outside the
address table. Kamailio refuses each call, and fail2ban blocks SIP (5060 and 5061, TCP and UDP)
from an address with 30 refusals in 10 minutes, for one day. Kamailio never refuses the addresses
in the table, so fail2ban never blocks them. A room system that is not in the table yet is refused
once per call.

On the central host:

```sh
apt-get install -y fail2ban
ln -sf /root/edumeet-sip-gateway/central/fail2ban/filter.d/kamailio-refused.conf /etc/fail2ban/filter.d/
ln -sf /root/edumeet-sip-gateway/central/fail2ban/jail.d/kamailio-refused.conf /etc/fail2ban/jail.d/
systemctl restart fail2ban
fail2ban-client status kamailio-refused
```

The package also blocks SSH from addresses with failed logins (its `sshd` jail). An address that
you add to the table stays blocked until its ban ends:
`fail2ban-client set kamailio-refused unbanip 192.0.2.10` ends it now.

## TURN on a media node

The gateways use coturn on an eduMEET media node. coturn must run with `--use-auth-secret`.

1. Make a new random secret for the gateways.
2. Add a second `static-auth-secret` line with this secret to the coturn configuration of the
   media node. coturn accepts credentials from each of its secrets.
3. Restart coturn.
4. Put the new secret in `GATEWAY_TURN_SECRET` on the gateway hosts.

Do not give the first secret to the gateway hosts. On an eduMEET media node, that secret usually
also authenticates the room server.

Each gateway host uses one media node, in `TURN_SRV`. Use a media node near the gateway host, in
the same network or with the same provider when possible. Different gateway hosts can use different
media nodes.

A restart of the media node stops the media of the calls that use it. Plan the maintenance of
these media nodes for the times when the rooms are not in use.

### Add a TURN server

1. Make a secret, for example with `openssl rand -hex 32`, and add it to the coturn configuration of
   the media node as a second `static-auth-secret` line. See [TURN on a media node](#turn-on-a-media-node).
2. Restart coturn on the media node, at a time when no call uses it.
3. On a gateway host, test the relay with this secret:

   ```sh
   set -a; . /etc/edumeet-sip-gateway/gateway.env; set +a
   docker run --rm --network host -e S="<secret>" --entrypoint sh coturn/coturn:4.18.0 -c 'timeout 30 turnutils_uclient -y -n 3 -m 1 -l 100 -W "$S" -u sipgw <media node address> 2>&1 | grep -i "lost packets\|401\|error"'
   ```

   It must show `Total lost packets 0`.
4. On each gateway host that will use this media node, set `TURN_SRV` and `GATEWAY_TURN_SECRET` in
   `/etc/edumeet-sip-gateway/gateway.env`, then run `systemctl restart edumeet-sip-gateway`. The
   restart stops the calls on that host.
5. Tell the institutions to allow UDP 3478 and UDP 50000-60000 to the new media node.

One media node relays the media of many gateways. A call sends about 2 to 4 Mbit/s in each direction
through the relay, so 20 calls need about 100 Mbit/s in and out. More TURN servers are useful for a
gateway host in another network (a near media node), and so that the restart of one media node stops
only the calls of the gateway hosts that use it.

## Images

`build-server/build_and_publish.sh` builds the images on a build server: a host with Docker and a
web server that the central host and the gateway hosts can reach. Copy the script and `.env-build`
(from `build-server/.env-build.example`) to a folder on the build server, and run the script there.

| Image | Built from |
| --- | --- |
| `edumeet/edumeet-sip-gateway` | The `Dockerfile` of SIPMediaGW |
| `edumeet/edumeet-sip-kamailio` | `deploy/kamailio` of SIPMediaGW |
| `edumeet/edumeet-sip-proxy` | `deploy/proxyAPI` of SIPMediaGW and `central/proxy` of this repository (the Dockerfile and the pinned Python packages) |

- The script clones this repository and builds the tag of the fork in `SIPMEDIAGW_VERSION`. The
  images get the same tag.
- It warns when its copy on the build server differs from `build-server/build_and_publish.sh` of the
  branch it builds. Copy the new one to the build server then.
- It writes `edumeet-sip-*_<tag>.tar` and `current_sip_version.txt` in `DEST_DIR`, the directory
  of the web server at `IMAGES_URL`. It deletes the SIP tar files of other versions, and changes
  no other file there. It removes the images that it built from Docker after it saved them.
- `central/prepare.sh` and `gateway-host/install.sh` load the images with `fetch-images.sh` and
  tag them `<name>:local`. They stop when `current_sip_version.txt` is not the version in
  `SIPMEDIAGW_VERSION`.

Each change of `SIPMEDIAGW_VERSION` needs a build first.

## Set up the central host

1. Clone this repository to `/root/edumeet-sip-gateway`.
2. Copy `central/.env.example` to `central/.env` and set the values.
3. Copy each `central/*.env.example` file to the same name without `.example`, and set the values.
   Use long random values for the secrets and tokens.
4. Optional: run `./firewall.sh central` as root. See [Firewall](#firewall).
5. Run `central/prepare.sh`. It clones SIPMediaGW, packs the gateway assets, and loads the
   Kamailio and proxy images. See [Images](#images).
6. Get the certificate and install the nginx site. Set `host` to the DNS name of the central host:

   ```sh
   host=sip.example.org
   certbot certonly --nginx --key-type rsa -d "$host" --deploy-hook /root/edumeet-sip-gateway/central/certbot-deploy-hook.sh
   sed "s/sip\.example\.org/$host/g" central/nginx/sip.example.org > "/etc/nginx/sites-available/$host"
   ln -s "/etc/nginx/sites-available/$host" /etc/nginx/sites-enabled/
   nginx -t && systemctl reload nginx
   ```

7. In `central/`, run `docker compose up -d`. Kamailio does not start without the
   certificate, so do step 6 first.
8. Install fail2ban for the SIP scanners. See [Block SIP scanners](#block-sip-scanners).

certbot renews the certificate automatically. After each renewal, `central/certbot-deploy-hook.sh`
copies the certificate to `central/tls/` for Kamailio, and loads it in nginx and in Kamailio
without a restart. With `certonly`, certbot does not change the site file, so the file on the host
stays the same as `central/nginx/sip.example.org`.

The certificate has an RSA key, because some older room systems do not accept other key types.

nginx sends the phone pages and the requests of the gateways to the proxy on `127.0.0.1:9000`. The
pairing page is the start page: nginx does not serve the portal page of the proxy. nginx lets
through only the status requests by gateway id: the proxy also answers a status request by meeting
room with the gateway id, and the gateway id controls the room system.
`GW_API_SCHEME=https` in `central/proxy.env` makes the proxy send the commands to the gateways with
HTTPS.

## Set up a gateway host

1. Clone this repository to `/root/edumeet-sip-gateway`.
2. Copy `gateway-host/gateway.env.example` to `/etc/edumeet-sip-gateway/gateway.env`, set the
   values, and set the file mode to 600.
3. Check `gateway-host/webrtc_domains.json`: the gateways join the eduMEET instances of this file.
   See [eduMEET instances](#edumeet-instances).
4. Get the certificate and install the nginx site. Set `host` to the DNS name of the gateway host
   (`HOST_IP`), and `central` to the public IPv4 address of the central host (`CENTRAL_IP`):

   ```sh
   host=node1.example.de.sip.example.org
   central=203.0.113.10
   certbot certonly --nginx -d "$host" --deploy-hook "systemctl reload nginx"
   sed -e "s/gateway\.example\.org/$host/g" -e "s/203\.0\.113\.10/$central/" gateway-host/nginx/gateway.example.org > "/etc/nginx/sites-available/$host"
   ln -s "/etc/nginx/sites-available/$host" /etc/nginx/sites-enabled/
   nginx -t && systemctl reload nginx
   ```

5. Run `gateway-host/install.sh` as root.

The script does these steps:

- It installs the kernel modules `snd-aloop` and `v4l2loopback`.
- It clones SIPMediaGW and loads the gateway image. See [Images](#images).
- It sets ufw with `firewall.sh gateway`. See [Firewall](#firewall). With `--update` (as
  `gateway-host/update.sh` runs it), it leaves ufw as it is.
- It installs the systemd service `edumeet-sip-gateway` and the timer
  `edumeet-sip-turn-credentials`.

The service starts one gateway for each 4 vCPU. The timer writes new TURN credentials every hour.
A gateway reads them when it starts and keeps them until the end of its next call, which can be
weeks later, so they are valid for a year (`TURN_CREDENTIAL_TTL` in `gateway.env`, in seconds).

## Add a gateway host

The central host needs no change: the new gateways register themselves, and Kamailio sends the next
calls to them.

1. Get a server in the EEA with Ubuntu 24.04 or 26.04: 4 vCPU and 4 GB of memory for each gateway,
   at most 10 gateways.
2. Add the DNS record `node<n>.<org>.<country>.sip.example.org` A with its IPv4 address (no AAAA).
3. In the firewall of the provider: SSH from the addresses in `SSH_SOURCES`, TCP 80 from all IPv4
   addresses, TCP 443 from the central host only.
4. Choose its TURN media node, near the server. See [Add a TURN server](#add-a-turn-server).
5. Install nginx, certbot with its nginx plugin, git, and Docker Engine with the compose plugin.
6. Connect with SSH from an address in `SSH_SOURCES` (`install.sh` sets ufw and stops otherwise),
   and do the steps of [Set up a gateway host](#set-up-a-gateway-host). In `gateway.env`:
   - `HOST_IP`: the DNS name of the server;
   - `PREFIX`: unique for each gateway host, for example `node2.example.de`;
   - `CENTRAL_IP`, and `SIP_SECRET`, `GW_NAME_PREFIX` and `PROXY_TOKEN` with the same values as on
     the central host;
   - `TURN_SRV` and `GATEWAY_TURN_SECRET` of its TURN media node.
7. On the central host, check the registration. The count in
   `journalctl -t kamailio --since "-5min" | grep "registered SIPMediaGWs"` grows by the number of
   new gateways, and `docker logs proxy 2>&1 | grep "registered" | tail -3` shows the DNS name of the
   new host.

`kamctl ul show` shows no gateways: Kamailio keeps the registrations in the database only
(`db_mode` 3).

## eduMEET instances

One gateway pool serves many eduMEET instances. The call address can select the instance (see
[Call addresses](#call-addresses)). If it does not, the person in the room selects the instance on
the phone, or enters its number on the keypad of the room system.

`webrtc_domains.json` has one entry for each instance:

```json
{
    "example": { "name": "Example", "domain": "edumeet.example.org", "browsing": "edumeet" },
    "example-dev": { "name": "Example dev", "domain": "dev.example.org", "browsing": "edumeet", "groups": ["example"], "listed": false }
}
```

- The key is the code of the instance in the call addresses. Use lower case letters and digits, and
  start with a letter. Do not use dots.
- `name` is the name that the phone and the room screen show.
- `domain` is the host name that the gateway opens.
- `browsing` must be `edumeet`. All the instances use the same eduMEET connector.
- `groups` (optional) adds the instance to other groups. In the example, `example@sip.example.org`
  shows both instances, and `example-dev@sip.example.org` only the second one. Use the same rules as
  for the keys.
- `listed` (optional): `false` removes the instance from the list of `sip.example.org`. Its code and
  its groups continue to show it. In the example, `sip.example.org` shows only the first instance.
  Use it for a test instance.

`gateway-host/webrtc_domains.json` is an example with one instance, and the gateways use this file.
Put your instances in it. Add a new instance at the end of the file: the number of each instance is its position
among the listed instances. When you remove an instance, the numbers of the instances after it
change. After a change, run `gateway-host/update.sh` on each gateway host. All the gateway hosts then
have the same list.

For a list of your own, copy the file to `/etc/edumeet-sip-gateway/webrtc_domains.json`, change it,
and set `WEBRTC_DOMAINS_FILE` in `gateway.env` to that path.

The `browsing`, `groups` and `listed` fields and the codes in the call addresses are changes of the
fork. They are offered to SIPMediaGW as pull requests.

## Change the connector

The eduMEET connector, `browsing/assets/edumeet.js`, is in the fork. It finds the controls of the
eduMEET page and clicks them. `build-assets.sh` puts the connector of the SIPMediaGW checkout into
the gateway assets, so a new connector needs no rebuild of the gateway image.

1. Commit the change on the `edumeet` branch of the fork, and offer it to Renater/SIPMediaGW as a
   pull request.
2. Tag the result `edumeet-YYYY-MM-DD`, push the branch and the tag, and write the tag in
   `SIPMEDIAGW_VERSION`.
3. Run `build_and_publish.sh` on the build server. See [Images](#images).
4. Run `central/update.sh` on the central host. See [Update SIPMediaGW](#update-sipmediagw).

Each gateway reads the assets when its container starts, so the next call uses the new connector.

## Change the branding

The branding comes from the eduMEET client: the logo, the app icon, the background gradient and the
primary colour of the client theme.

- `assets/gateway/IVR/logo.svg` is the logo on the room screen: the light logo of the eduMEET client
  (`public/images/logo.edumeet.light.svg`), for the dark background. `assets/gateway/IVR/edumeet.css`
  sets the colours of the room screen. `assets/gateway/IVR/index.html` sets the texts of the room
  screen that differ from SIPMediaGW: the prompts, the selected organisation and the keypad line.
- `assets/gateway/IVR/platform_en.mp3` and `conference_en.mp3` are the spoken prompts of the
  organisation list and of the room step. They replace the prompts of SIPMediaGW. They are made with
  Piper and the voice `en_GB-alba-medium` (CC BY 4.0: dataset
  https://datashare.ed.ac.uk/handle/10283/3270, base model on the NVIDIA Hi-Fi TTS dataset).
  Make new ones as MP3, 44.1 kHz, mono. The room hears `platform_en.mp3` only when it sees a list of
  instances. Its text names the eduMEET Federation, so replace it for a list of your own.
- `assets/proxy/brand.js` sets the name, the accent colour and the texts of the phone pages that
  differ from SIPMediaGW, in all their languages. `assets/proxy/favicon.svg` is the icon of the
  phone pages.
- `allPlatforms` in `assets/gateway/IVR/index.html` and `assets/proxy/brand.js` is the name of the
  full list of the instances: `Federation`. Change it for a list of your own.

After a change, run `build-assets.sh` on the central host and restart the `proxy` container. Each
gateway reads the assets when its container starts.

## See the usage

Run `central/usage.sh` as root on the central host. It shows, for each gateway host, the gateways
that are registered with Kamailio and their state: free, in a call (with the time and the caller),
or busy without a call (a call is being set up, or the gateway starts again after a call). For each
host and for the central host, it says if `update.sh` can run now without ending a call.
`central/usage.sh -w` shows the state again every 5 seconds, `-w 10` every 10 seconds.

A gateway that has just ended a call is missing for about 15 seconds while it starts again.

## Debug logs

Both servers can log more, to find problems with room systems:

- Kamailio: `DEBUG_LEVEL` in `central/kamailio.env`. `0` logs errors and warnings, `1` also each
  call and each BYE (`journalctl -t kamailio | grep ACC:`), `3` all debug output, with where each
  request goes. `central/update.sh` applies a change. To change the level of the running Kamailio
  until its next restart: `docker exec kamailio kamcmd cfg.set_now_int core debug 3`.
- The gateways: `BARESIP_ARGS` in `/etc/edumeet-sip-gateway/gateway.env`. `" -s"` logs every SIP
  message that a gateway sends or receives, `" -s -v"` also all debug output. The SIP messages
  contain the SRTP keys of the calls. `systemctl restart edumeet-sip-gateway` applies a change and
  stops the calls on that host.

The journal keeps the newest logs within its size limit: by default 10 percent of the disk, at most
4 GB. At level 3 Kamailio writes millions of lines a day, and the journal then keeps them only for a
short time. To keep more, set `SystemMaxUse` in a file in `/etc/systemd/journald.conf.d/` and run
`systemctl restart systemd-journald`. `journalctl --no-pager -o short-iso | head -1` shows the oldest
entry that the journal still has. If it reports suppressed messages
(`journalctl -u systemd-journald | grep -i suppressed`), Kamailio logged faster than the journal
accepts: raise `RateLimitBurst`.

## Update SIPMediaGW

The fork has these branches:

| Branch or tag | Contents |
| --- | --- |
| `main` | The `main` branch of Renater/SIPMediaGW, without changes. |
| `edumeet` | The version that this repository deploys: `main` and the eduMEET changes. |
| `edumeet-YYYY-MM-DD` | A tag for each deployed version. A second tag on the same day gets `.2`, and so on. |
| `feature/...` | One branch for each pull request to Renater/SIPMediaGW, based on its `main`. |

To take changes from Renater/SIPMediaGW:

1. Update `main` of the fork from Renater/SIPMediaGW.
2. Rebase `edumeet` on `main`. Drop the commits of the fork that Renater/SIPMediaGW merged.
3. Compare the upstream `.env` with `gateway-host/sipmediagw.env`, and copy the new settings.
4. Tag the result `edumeet-YYYY-MM-DD`, push the branch and the tag, and write the tag in
   `SIPMEDIAGW_VERSION`.
5. Run `build_and_publish.sh` on the build server. See [Images](#images).
6. Run `central/update.sh` on the central host. It restarts Kamailio, so first check with
   `central/usage.sh` that no call is running. See [See the usage](#see-the-usage).
7. Run `gateway-host/update.sh` as root on each gateway host. It restarts the gateways, so the calls
   on that host stop: `central/usage.sh` shows when the host has no calls.

Both scripts run `git pull` first and then continue with the pulled version of themselves. At the
end, both remove the images that no container uses (`docker image prune -a -f`), so the images of
the previous version go away. `gateway-host/update.sh` runs `gateway-host/install.sh` and removes
images only when a gateway container runs: without one, the prune would also remove the gateway
image, and SIPMediaGW would build it for the next call.

`central/update.sh` runs `central/prepare.sh`, then `docker compose up -d --renew-anon-volumes`.
Do not update with a plain `docker compose up -d`: the Kamailio image keeps its configuration in
`/etc/kamailio`, which its base image declares as a volume. Docker Compose keeps that volume when it
recreates the container, and Kamailio then runs the new image with the configuration of its first
start. `--renew-anon-volumes` replaces only the anonymous volumes of the recreated containers. The
MySQL data is in the named volume `kamailio_db` and stays. To check the configuration that Kamailio
uses: `docker exec kamailio grep -n "source IP allowed" /etc/kamailio/kamailio.cfg`.

Always deploy a tag, never a commit of a branch. A rebase removes the old commits from the branch,
but a tagged commit stays available.

Run `build_and_publish.sh` regularly, also without a new version: the gateway image takes the
current Chromium from the Debian security updates when it is built, and all images take their
current base images. Then do steps 6 and 7.

## Known limitations

- A room system in the address table gets a gateway for each call. The eduMEET room rules decide
  who can join the meeting. A call without a meeting ends after 5 minutes (`IVR_TIMEOUT`).
- The connector finds the controls by their `data-edumeet-*` attributes (see AUTOMATION.md in the
  edumeet repository). An older eduMEET client does not have these attributes. The connector then
  finds the controls by their English or French labels, so the gateway's Chromium must use one of these languages.
- A room system waits in the lobby of a locked room for up to 15 minutes, until a moderator admits it.
- A meetings-only room asks for the meeting token of the invitation. The room screen then shows the
  pairing code, and the phone page asks for the token. A pasted invitation link gives the room and
  the token together. When no token comes in 5 minutes (`IVR_TIMEOUT`), the gateway ends the call.
- The connector cannot join a room that requires a login.
- The phone pages use the language of the browser when it is one of the 17 complete languages of
  the eduMEET client. For other browsers, they use English (`lang: 'en'` in `assets/proxy/brand.js`).
  The menu at the top of the page changes the language. The room screen is in English only:
  `gateway-host/sipmediagw.env` sets `IVR_LANG`.
- `v4l2loopback` is a DKMS module. Make sure that it builds for a new kernel before you restart
  a gateway host.

## License

This repository is under the Apache License 2.0. See `LICENSE`. `NOTICE` lists the files that come
from SIPMediaGW, and the credits for the branding and the spoken prompts.
