#!/bin/bash
echo 'Starting WireGuard peer configuration...'

while [[ $EUID != 0 ]];do
	echo "This script must be run as root."
	exit 1
done

hasWG=$(which wg-quick)
while [[ $hasWG == '' ]];do
    echo 'WireGuard not installed. Run wireguard-autoconfig.sh first.'
    exit 1
done

hasRC=$(which resolvconf)
while [[ $hasRC == '' ]];do
    echo 'resolvconf not installed. Run wireguard-autoconfig.sh first.'
    exit 1
done

hasQR=$(which qrencode)
while [[ $hasQR == '' ]];do
    echo 'qrencode not installed. Run wireguard-autoconfig.sh first.'
    exit 1
done

hasSettings=$(ls /etc/wireguard/settings/peer.next)
while [[ $hasSettings != '/etc/wireguard/settings/peer.next' ]];do
    echo 'Script config not found. Run wireguard-autoconfig.sh first.'
    exit 1
done

cd /etc/wireguard

peerNum=$(cat settings/peer.next)
echo $(($peerNum + 1)) > settings/peer.next

mkdir peer${peerNum}
cd peer${peerNum}

echo 'Generating keypair...'
umask 077
wg genkey | tee privatekey | wg pubkey > publickey
cat << EOF > peer.conf
[Interface]
PrivateKey = REF_PEER_KEY
Address = REF_PEER_ADDRESS

[Peer]
PublicKey = REF_SERVER_PUBLIC_KEY
AllowedIPs = ALLOWED_IP40/24, ALLOWED_IP6:/64
Endpoint = REF_SERVER_ENDPOINT
PersistentKeepalive = 25
EOF
external_ip=$(curl ipinfo.io/ip)
ipv4=$(cat ../settings/ipv4)
ipv6=$(cat ../settings/ipv6)
server_endpoint="$external_ip:$(cat ../settings/port)"
ipv4_peer_addr="$ipv4${peerNum}/24"
ipv6_peer_addr="$ipv6:${peerNum}/64"
#dns="$(cat ../settings/ipv4)1, $(cat ../settings/ipv6):1"

echo 'Setting peer configuration...'
sed -i "s;REF_PEER_KEY;$(cat privatekey);g" peer.conf
sed -i "s;REF_PEER_ADDRESS;$ipv4_peer_addr, $ipv6_peer_addr;g" peer.conf
#sed -i "s;REF_PEER_DNS;$dns;g" peer.conf
sed -i "s;REF_SERVER_PUBLIC_KEY;$(cat ../publickey);g" peer.conf
sed -i "s;REF_SERVER_ENDPOINT;$server_endpoint;g" peer.conf
sed -i "s;ALLOWED_IP4;$ipv4;g" peer.conf
sed -i "s;ALLOWED_IP6;$ipv6;g" peer.conf

wg-quick down wg0

echo 'Updating server configuration...'
cat << EOF >> ../wg0.conf

[Peer]
PublicKey = REF_PEER_PUBLIC_KEY
AllowedIPs = REF_PEER_IPS
EOF
allowed_ips="$(cat ../settings/ipv4)${peerNum}/32, $(cat ../settings/ipv6):${peerNum}/128"
sed -i "s;REF_PEER_PUBLIC_KEY;$(cat publickey);g" ../wg0.conf
sed -i "s;REF_PEER_IPS;$allowed_ips;g" ../wg0.conf

wg-quick up wg0

echo "You can connect using the config /etc/wireguard/peer${peerNum}/peer.conf -- or -- the QR code below:"
cat peer.conf | qrencode --type utf8
