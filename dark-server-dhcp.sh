echo "=== Автоматическая настройка DarkServer by ScumDev ==="

read -p "Введите название ВХОДНОГО интерфейса (например, enp0s0): " INPUT_INTERFACE
read -p "Введите название ВЫХОДНОГО интерфейса (например, enp1s0): " OUTPUT_INTERFACE
read -p "Введите подсеть для локальной сети (например, 5): " SUBNET

echo "Устанавливаем необходимые пакеты..."
apt update && apt upgrade -y
apt install -y htop net-tools mtr network-manager isc-dhcp-server wireguard wireguard-tools resolvconf ufw iptables nano

echo "Настраиваем сетевые интерфейсы..."
NETPLAN_CONFIG="/etc/netplan/00-installer-config.yaml"
cat <<EOF > $NETPLAN_CONFIG
network:
  version: 2
  renderer: networkd
  ethernets:
    $OUTPUT_INTERFACE:
      dhcp4: false
      addresses:
        - 192.168.$SUBNET.1/24
      nameservers:
        addresses:
          - 192.168.$SUBNET.1
      optional: true
    $INPUT_INTERFACE:
      dhcp4: true
EOF
netplan apply

echo "Настраиваем DHCP-сервер..."
DHCP_CONFIG="/etc/dhcp/dhcpd.conf"
cat <<EOF > $DHCP_CONFIG
default-lease-time 600;
max-lease-time 7200;

ddns-update-style none;

authoritative;

subnet 192.168.$SUBNET.0 netmask 255.255.255.0 {
  option routers 192.168.$SUBNET.1;
  option broadcast-address 192.168.$SUBNET.255;
  range 192.168.$SUBNET.2 192.168.$SUBNET.254;
  option domain-name-servers 8.8.8.8, 8.8.4.4;
}
EOF

echo "INTERFACESv4=\"$OUTPUT_INTERFACE\"" > /etc/default/isc-dhcp-server
systemctl restart isc-dhcp-server

echo "Настраиваем WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

echo "Настраиваем NAT через UFW..."
UFW_RULES="/etc/ufw/before.rules"
sed -i '/\*nat/a :POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s 192.168.'$SUBNET'.0/24 -o wg0 -j MASQUERADE\nCOMMIT' $UFW_RULES
sed -i '/#net\/ipv4\/ip_forward=1/s/^#//g' /etc/ufw/sysctl.conf

echo "Настраиваем политики UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed

ufw allow ssh
ufw allow in on $OUTPUT_INTERFACE to any
ufw enable

echo "Настройка завершена! Перезагрузите сервер, чтобы изменения вступили в силу."
