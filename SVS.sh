#!/bin/bash

# Script mejorado para anonimato en auditorías de Red Team con monitoreo
# Uso: sudo ./script.sh [interfaz]

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "Este script necesita ejecutarse como root. Usa sudo."
    exit 1
fi

# Verificar interfaz
if [ -z "$1" ]; then
    echo "Uso: $0 [interfaz]"
    echo "Ejemplo: $0 wlan0"
    exit 1
fi

INTERFACE=$1
LOG_FILE="anonimato.log"

# Detectar sistema operativo
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        OS="unknown"
        echo "Sistema operativo no soportado: $OSTYPE"
        exit 1
    fi
    echo "Sistema operativo detectado: $OS"
}

# Instalar dependencias
install_deps() {
    if [ "$OS" == "linux" ]; then
        echo "Instalando dependencias en Linux..."
        apt-get update && apt-get install -y tor macchanger proxychains-ng
    elif [ "$OS" == "macos" ]; then
        echo "Instalando dependencias en macOS..."
        brew install tor macchanger proxychains-ng
    fi
}

# Configurar TOR
start_tor() {
    echo "Iniciando TOR..."
    if [ "$OS" == "linux" ] || [ "$OS" == "macos" ]; then
        service tor start || tor &
        sleep 5
        echo "TOR iniciado."
    fi
    echo "$(date): TOR iniciado" >> $LOG_FILE
}

# Rotar identidad TOR
rotate_tor() {
    echo "Rotando identidad TOR..."
    killall -HUP tor
    sleep 2
    echo "Nueva identidad TOR establecida."
    echo "$(date): Identidad TOR rotada" >> $LOG_FILE
}

# Configurar Proxychains
setup_proxychains() {
    echo "Configurando Proxychains..."
    PROXYCHAINS_CONF="/etc/proxychains4.conf"
    if [ "$OS" == "macos" ]; then
        PROXYCHAINS_CONF="/usr/local/etc/proxychains.conf"
    fi

    cat > $PROXYCHAINS_CONF << EOL
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 127.0.0.1 9050
socks5 192.168.1.100 1080
http 45.32.123.45 8080
EOL
    echo "Proxychains configurado. Usa 'proxychains4 [comando]' para enrutar tráfico."
    echo "$(date): Proxychains configurado" >> $LOG_FILE
}

# Configurar DNS anónimo
setup_anonymous_dns() {
    echo "Configurando DNS anónimo..."
    if [ "$OS" == "linux" ]; then
        echo "nameserver 1.1.1.1" > /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    elif [ "$OS" == "macos" ]; then
        networksetup -setdnsservers Wi-Fi 1.1.1.1 8.8.8.8
    fi
    echo "DNS anónimo configurado."
    echo "$(date): DNS anónimo configurado" >> $LOG_FILE
}

# Cambiar MAC
change_mac() {
    echo "Cambiando dirección MAC de $INTERFACE..."
    if [ "$OS" == "linux" ]; then
        ifconfig $INTERFACE down
        macchanger -r $INTERFACE
        NEW_MAC=$(ifconfig $INTERFACE | grep ether | awk '{print $2}')
        ifconfig $INTERFACE up
    elif [ "$OS" == "macos" ]; then
        NEW_MAC=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/.$//')
        ifconfig $INTERFACE ether $NEW_MAC
    fi
    echo "Nueva MAC asignada: $NEW_MAC"
    echo "$(date): MAC cambiado a $NEW_MAC" >> $LOG_FILE
}

# Bucle principal
main_loop() {
    while true; do
        change_mac
        rotate_tor
        echo "Esperando 3 minutos para el próximo cambio..."
        sleep 180
    done
}

# Verificar e instalar dependencias
command -v tor >/dev/null 2>&1 || { echo "TOR no está instalado."; install_deps; }
command -v macchanger >/dev/null 2>&1 || { echo "macchanger no está instalado."; install_deps; }
command -v proxychains4 >/dev/null 2>&1 || { echo "Proxychains no está instalado."; install_deps; }

# Detectar OS
detect_os

# Configurar todo
start_tor
setup_proxychains
setup_anonymous_dns
main_loop &

# Mantener script activo
echo "Script ejecutándose con anonimato y monitoreo. Log en $LOG_FILE. Usa Ctrl+C para detener."
wait
