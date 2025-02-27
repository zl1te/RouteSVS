#!/bin/bash

# Script mejorado para anonimato con cambio de IP verificable
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

# Validar que la interfaz existe
if ! ifconfig $INTERFACE >/dev/null 2>&1; then
    echo "Error: La interfaz $INTERFACE no existe."
    echo "Interfaces disponibles:"
    ifconfig -a | grep -oE '^[a-zA-Z0-9]+'
    exit 1
fi

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
        apt-get update && apt-get install -y tor macchanger proxychains-ng curl netcat
    elif [ "$OS" == "macos" ]; then
        brew install tor macchanger proxychains-ng curl netcat
    fi
}

# Configurar TOR con puerto de control
start_tor() {
    echo "Iniciando TOR con puerto de control..."
    if [ "$OS" == "linux" ] || [ "$OS" == "macos" ]; then
        TORRC="/etc/tor/torrc"
        [ "$OS" == "macos" ] && TORRC="/usr/local/etc/tor/torrc"
        echo "ControlPort 9051" >> $TORRC
        echo "CookieAuthentication 0" >> $TORRC
        service tor restart || tor &
        sleep 5
        if ! ps aux | grep -v grep | grep tor >/dev/null; then
            echo "Error: TOR no se inició correctamente."
            exit 1
        fi
        echo "TOR iniciado."
    fi
    echo "$(date): TOR iniciado" >> $LOG_FILE
}

# Rotar identidad TOR
rotate_tor() {
    echo "Rotando identidad TOR..."
    printf "AUTHENTICATE\r\nSIGNAL NEWNYM\r\nQUIT\r\n" | nc 127.0.0.1 9051
    sleep 5
    echo "Nueva identidad TOR establecida."
    CURRENT_IP=$(proxychains4 curl -s icanhazip.com 2>/dev/null || echo "No se pudo obtener IP")
    echo "IP actual: $CURRENT_IP"
    echo "$(date): Identidad TOR rotada - Nueva IP: $CURRENT_IP" >> $LOG_FILE
}

# Configurar Proxychains
setup_proxychains() {
    echo "Configurando Proxychains..."
    PROXYCHAINS_CONF="/etc/proxychains4.conf"
    [ "$OS" == "macos" ] && PROXYCHAINS_CONF="/usr/local/etc/proxychains.conf"
    cat > $PROXYCHAINS_CONF << EOL
strict_chain
proxy_dns
tcp_read_time_out 15000
tcp_connect_time_out 8000
[ProxyList]
socks5 127.0.0.1 9050
EOL
    echo "Proxychains configurado."
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
command -v curl >/dev/null 2>&1 || { echo "curl no está instalado."; install_deps; }
command -v nc >/dev/null 2>&1 || { echo "netcat no está instalado."; install_deps; }

# Detectar OS
detect_os

# Configurar todo
start_tor
setup_proxychains
setup_anonymous_dns
main_loop &

echo "Script ejecutándose. Log en $LOG_FILE. Usa Ctrl+C para detener."
wait
