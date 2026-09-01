# Networking Homework

Notes and captured output for the networking session, plus the `ip` command cheat sheet
from the earlier Linux session.

## Where these commands were run

My machine is a Mac, and `ip`, `ss` and friends are Linux tools that simply do not exist
there. Rather than substitute the BSD equivalents and get output that looks nothing like
the notes, I did the whole exercise inside an Ubuntu container:

    docker run --rm -it --cap-add=NET_ADMIN ubuntu:22.04 bash
    apt-get update
    apt-get install -y iproute2 iputils-ping dnsutils traceroute net-tools curl wget nginx

`--cap-add=NET_ADMIN` is needed because some of the tasks below change addresses and
routes, and a container is not allowed to do that by default.

The container has a single usable interface, `eth0`, addressed 172.17.0.4, and its
gateway is the Docker bridge on 172.17.0.1. Every private address in the output below is
in that 172.17.x.x range for that reason.

## Part 1: Addresses and interfaces

### ip addr show

Lists every interface together with the addresses configured on it. This is the first
thing to run when the question is "what is this machine's IP".

    13: eth0@if22: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP
        link/ether 6a:2c:88:1f:03:d1 brd ff:ff:ff:ff:ff:ff link-netnsid 0
        inet 172.17.0.4/16 brd 172.17.255.255 scope global eth0
           valid_lft forever preferred_lft forever

Reading it: `link/ether` is the MAC, the layer 2 hardware address. `inet` is the IPv4
address, and the `/16` is the prefix length, meaning the leading 16 bits identify the
network and the remaining 16 are available for hosts. Two separate flags matter in the
angle brackets, `UP` means the interface has been administratively enabled and
`LOWER_UP` means the link underneath it is actually live. An interface can be `UP` with
no `LOWER_UP` when the cable is unplugged.

### ip -brief addr

Identical information, collapsed to one line per interface, which is far easier to scan.

    lo               UNKNOWN        127.0.0.1/8 ::1/128
    tunl0@NONE       DOWN
    gre0@NONE        DOWN
    eth0@if22        UP             172.17.0.4/16

`lo` is loopback, the interface the machine uses to reach itself at 127.0.0.1. The tunnel
interfaces exist by default but are `DOWN` and carry nothing. Only `eth0` is doing any
work here.

### ip link show

The layer 2 view: interfaces, MAC addresses and state, with no IP addresses at all.

    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    13: eth0@if22: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65535 qdisc noqueue state UP
        link/ether 6a:2c:88:1f:03:d1 brd ff:ff:ff:ff:ff:ff link-netnsid 0

So `ip link` is about the interface itself and `ip addr` is about the addresses on it.
`mtu` is the largest payload the interface will put in a single frame; 1500 is the normal
value on a real ethernet, the very large number here is a Docker Desktop artefact.

### ifconfig

The old command covering roughly what `ip addr` does. It still runs, but it is deprecated
and is no longer installed by default, which is why `net-tools` had to be added above.

    eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 65535
            inet 172.17.0.4  netmask 255.255.0.0  broadcast 172.17.255.255
            ether 6a:2c:88:1f:03:d1  txqueuelen 0  (Ethernet)
            RX packets 2601  bytes 64118442 (64.1 MB)
            TX packets 1188  bytes 88104 (88.1 KB)

Same address, written differently: `netmask 255.255.0.0` is exactly what `/16` means.
The `RX` and `TX` counters are the useful extra, an interface that is up but has zero
packets in one direction is a strong hint about where a problem is.

### hostname and hostname -I

    $ hostname
    b7c41d9ae05f
    $ hostname -I
    172.17.0.4

`hostname` on its own gives the machine name, here the container ID. `hostname -I` prints
only the addresses, which is the form to use in a script because there is nothing to
parse out of it.

## Part 2: Routing

### ip route

Prints the routing table, the set of rules the kernel consults to decide which interface
and which next hop a packet should take.

    default via 172.17.0.1 dev eth0
    172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.4

The second line says everything inside 172.17.0.0/16 is on the directly attached network
and can be reached over `eth0` without help. The `default` line is the fallback for
everything else, handing the packet to the gateway 172.17.0.1. When the default route is
missing, the symptom is a machine that can reach its own subnet perfectly but cannot
reach anything beyond it.

### ip route get

Instead of reading the table and working it out yourself, ask the kernel what it would
actually do for one destination.

    $ ip route get 8.8.8.8
    8.8.8.8 via 172.17.0.1 dev eth0 src 172.17.0.4 uid 0
        cache

It answers with the next hop, the outgoing interface and the source address that will be
stamped on the packet. That last part is useful on a host with several addresses.

### ip route add and ip route delete

    $ ip route add 10.20.0.0/16 via 172.17.0.1 dev eth0
    $ ip route
    default via 172.17.0.1 dev eth0
    10.20.0.0/16 via 172.17.0.1 dev eth0
    172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.4

    $ ip route delete 10.20.0.0/16
    $ ip route
    default via 172.17.0.1 dev eth0
    172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.4

A route to a chosen network through a chosen gateway can be added by hand, and the more
specific prefix always wins over `default`. Anything done this way lives in memory only
and is lost on reboot; making it permanent means writing it into the distribution's
network configuration, for example a netplan file on Ubuntu.

### ip neigh

The ARP table, which is the mapping from local IP addresses to MAC addresses.

    172.17.0.1 dev eth0 lladdr 8e:44:c2:0b:71:5e REACHABLE

Before a frame can be sent to another machine on the same segment, its MAC has to be
known, and ARP is how the kernel discovers it. `REACHABLE` means the entry was verified
recently; `STALE` or `FAILED` entries are worth looking at when two hosts on the same
subnet cannot see each other.

## Part 3: Changing addresses and links

### ip addr add and ip addr del

    $ ip addr add 10.10.10.5/24 dev eth0
    $ ip -brief addr show eth0
    eth0@if22        UP             172.17.0.4/16 10.10.10.5/24

    $ ip addr del 10.10.10.5/24 dev eth0
    $ ip -brief addr show eth0
    eth0@if22        UP             172.17.0.4/16

One interface can hold several addresses at once, which is how a single server hosts
multiple IPs. The change is not written anywhere, so a reboot undoes it. It needs root,
and inside Docker it also needs the `NET_ADMIN` capability, which is why the container
was started with it.

### ip link set

    $ ip link set eth0 mtu 1400
    13: eth0@if22: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1400 qdisc noqueue state UP

`ip link set` operates on the interface rather than its addressing. The other two forms
in constant use are `ip link set eth0 down` and `ip link set eth0 up`. Worth being clear
about the danger: running `down` on the interface carrying your own SSH session drops
your connection and there is then no way back in remotely.

## Part 4: Testing connectivity

### ping

Sends ICMP echo requests and reports the replies, the quickest possible check of whether
a host answers and how far away it is.

    $ ping -c 4 google.com
    PING google.com (142.250.192.46) 56(84) bytes of data.
    64 bytes from bom12s16-in-f14.1e100.net (142.250.192.46): icmp_seq=1 ttl=63 time=32.7 ms
    64 bytes from bom12s16-in-f14.1e100.net (142.250.192.46): icmp_seq=2 ttl=63 time=27.9 ms
    64 bytes from bom12s16-in-f14.1e100.net (142.250.192.46): icmp_seq=3 ttl=63 time=41.2 ms
    64 bytes from bom12s16-in-f14.1e100.net (142.250.192.46): icmp_seq=4 ttl=63 time=30.5 ms

    --- google.com ping statistics ---
    4 packets transmitted, 4 received, 0% packet loss, time 3005ms
    rtt min/avg/max/mdev = 27.912/33.075/41.203/5.021 ms

`-c 4` stops after four packets, without it ping runs until interrupted. `time` is the
round trip in milliseconds and `ttl` is how many hops the reply had left before it would
have been dropped. `0% packet loss` means the path is clean. The case to recognise is a
ping that resolves the name and then times out: that usually means a firewall is dropping
ICMP, not that the host is off.

### traceroute

Shows each router the packets pass through on the way to a destination.

    $ traceroute -m 8 google.com
    traceroute to google.com (142.250.192.46), 8 hops max, 60 byte packets
     1  172.17.0.1 (172.17.0.1)  0.412 ms  0.015 ms  0.011 ms
     2  * * *
     3  * * *

Hop 1 is the gateway. The asterisks are hops that did not reply, which is normal since
plenty of routers are configured to ignore these probes, and in this case the Docker
Desktop VM hides the rest of the path as well. On a real network the value of the command
is seeing at which hop latency jumps or the path stops entirely.

## Part 5: DNS

### nslookup

Turns a name into an address.

    $ nslookup github.com
    Server:		192.168.65.7
    Address:	192.168.65.7#53

    Non-authoritative answer:
    Name:	github.com
    Address: 20.207.73.82

`Server` is the resolver that answered. "Non-authoritative" means the answer came out of
a cache rather than from the domain's own nameserver, which is the normal case. 53 is the
standard DNS port.

### dig

The detailed DNS tool.

    $ dig github.com +short
    20.207.73.82

    $ dig github.com
    ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 41902
    ;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

    ;; QUESTION SECTION:
    ;github.com.			IN	A

    ;; ANSWER SECTION:
    github.com.		58	IN	A	20.207.73.82

    ;; Query time: 2 msec
    ;; SERVER: 192.168.65.7#53(192.168.65.7) (UDP)

`+short` reduces it to the address, which is the form for scripts. In the full output,
`A` is the record type for an IPv4 address, and the 58 in front of it is the TTL, the
number of seconds this answer may be cached before it has to be looked up again.
`status: NOERROR` means the query succeeded; `NXDOMAIN` would mean the name does not
exist.

### host

The same lookup in the shortest possible form.

    $ host github.com
    github.com has address 20.207.73.82
    github.com mail is handled by 0 github-com.mail.protection.outlook.com.

It throws in the MX record, which names the mail server for the domain.

### /etc/resolv.conf

The file listing the resolvers the machine will use.

    # Generated by Docker Engine.
    nameserver 192.168.65.7

This is the first file to look at when pinging an IP address works but pinging a name
fails, because that combination means DNS is broken rather than the network.

### /etc/hosts

A static name to address table, consulted before DNS is asked.

    127.0.0.1	localhost
    ::1	localhost ip6-localhost ip6-loopback
    172.17.0.4	b7c41d9ae05f

Anything in here overrides DNS, which is what makes it useful for pointing a real domain
name at a test server before changing any public records.

## Part 6: Ports and connections

### ss -tulpn

Shows what the machine is listening on. I started nginx first so there was something
real to look at.

    Netid State  Recv-Q Send-Q Local Address:Port Peer Address:Port Process
    tcp   LISTEN 0      511          0.0.0.0:80        0.0.0.0:*    users:(("nginx",pid=2841,fd=6))
    tcp   LISTEN 0      511             [::]:80           [::]:*    users:(("nginx",pid=2841,fd=7))

The flags spell out as t for TCP, u for UDP, l for listening sockets only, p to show the
owning process and n to print numeric ports instead of service names. The distinction to
notice is the local address: `0.0.0.0:80` means nginx will accept connections arriving on
any interface, whereas `127.0.0.1:80` would restrict it to the machine itself. This is
also the command that answers "address already in use", because it names the process
holding the port.

### netstat -tulpn

The older equivalent, with the same flags.

    Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
    tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      2841/nginx: master
    tcp6       0      0 :::80                   :::*                    LISTEN      2841/nginx: master

Same facts. `ss` reads them straight out of the kernel and is noticeably faster on a busy
host, and `netstat` belongs to the deprecated `net-tools` package, so `ss` is the one to
learn.

### ss -s

A summary of socket usage.

    Total: 33
    TCP:   34 (estab 0, closed 32, orphaned 0, timewait 2)

    Transport Total     IP        IPv6
    TCP	  2         1         1

`estab` counts live connections and `timewait` counts connections that have closed but
are still being held briefly by the kernel so late packets do not confuse a new
connection. A very large `timewait` number on a busy server is a recognised symptom of
churn worth knowing about.

## Part 7: Talking to a web server

### curl -I

Makes an HTTP request and prints the response headers only.

    $ curl -I http://localhost
    HTTP/1.1 200 OK
    Server: nginx/1.18.0 (Ubuntu)
    Date: Tue, 01 Sep 2026 07:12:04 GMT
    Content-Type: text/html
    Content-Length: 612
    Connection: keep-alive

`200 OK` means the server handled the request normally, and the `Server` header says
which software answered. This is the fastest way to confirm a service is really up, as
opposed to the port merely being open. Without `-I` you get the whole page body as well.

### Finding the public IP with curl

    $ curl -s ifconfig.me
    49.36.xxx.xxx

That is the address the rest of the internet sees, which is the router's public IP, not
the container's private 172.17.0.4. The gap between the two is NAT: many private
addresses sharing one public one. The last two octets are masked here because this file
goes into a repository.

### wget

Fetches a URL to a file rather than to the terminal.

    $ wget -q -O page.html http://example.com
    $ ls -l page.html
    -rw-r--r-- 1 root root 559 Sep  1 07:14 page.html
    $ head -4 page.html
    <!doctype html><html lang="en"><head><title>Example Domain</title>...

The default behaviour is the real difference between the two tools: `wget` saves to disk,
`curl` writes to standard output. `-q` silences the progress bar and `-O` names the output
file.

## Quick reference: what each command is for

`ip addr` for addresses, `ip link` for interfaces and MACs, `ip route` for where packets
will go, `ip neigh` for the ARP table. `ifconfig` and `netstat` are the previous
generation of `ip` and `ss`, still present on many systems but deprecated.

`ping` answers whether a host replies, `traceroute` shows the path taken to it.

`nslookup`, `dig` and `host` all resolve names, with `dig` giving the most detail and
`host` the least.

`ss` and `netstat` show which ports are open and which process owns each one.

`curl` and `wget` both speak HTTP, `curl` for inspecting a response and `wget` for
downloading.

## The order I would work in when something is unreachable

1. `ip addr` to confirm the interface actually has an address.
2. `ip route` to confirm there is a default route.
3. `ping` the gateway, which separates a local problem from an upstream one.
4. `ping 8.8.8.8` to test raw connectivity to the internet by address.
5. `ping google.com` afterwards, so DNS is tested on its own rather than mixed in.
6. `ss -tulpn` on the far end, to confirm the service is listening at all, and on the
   address you expect rather than only on loopback.

Splitting steps 4 and 5 is the part that saves the most time, because it separates "the
network is down" from "name resolution is down", and those have completely different
fixes.
