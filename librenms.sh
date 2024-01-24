#!/bin/bash

set -e

# Configurations personnalisables
DB_PASSWORD_LIBRENMS='password'
SNMPD_COMMUNITY='STRING'
NGINX_SERVER_NAME='librenms.example.com'

# Fonctions
install_packages() {
    apt update && apt install -y apt-transport-https lsb-release ca-certificates wget acl curl fping git graphviz imagemagick mariadb-client mariadb-server mtr-tiny nginx-full nmap php8.2-cli php8.2-curl php8.2-fpm php8.2-gd php8.2-gmp php8.2-mbstring php8.2-mysql php8.2-snmp php8.2-xml php8.2-zip python3-dotenv python3-pymysql python3-redis python3-setuptools python3-systemd python3-pip rrdtool snmp snmpd unzip whois
}

create_librenms_user() {
    useradd librenms -d /opt/librenms -M -r -s "$(which bash)"
}

download_librenms() {
    git clone https://github.com/librenms/librenms.git /opt/librenms
}

set_permissions() {
    chown -R librenms:librenms /opt/librenms
    chmod 771 /opt/librenms
    setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
    setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
}

install_php_dependencies() {
    su - librenms -c './scripts/composer_wrapper.php install --no-dev'
}

configure_timezone() {
    for file in /etc/php/8.2/fpm/php.ini /etc/php/8.2/cli/php.ini; do
        sed -i 's/;date.timezone =.*/date.timezone = Europe\/Paris/' "$file"
    done
    timedatectl set-timezone Europe/Paris
}

configure_mariadb() {
    CONFIG_FILE="/etc/mysql/mariadb.conf.d/50-server.cnf"
    sed -i '/\[mysqld\]/a innodb_file_per_table=1' "$CONFIG_FILE"
    sed -i '/\[mysqld\]/a lower_case_table_names=0' "$CONFIG_FILE"
    systemctl enable mariadb
    systemctl restart mariadb
}

create_database() {
    mysql -u root -e "
    CREATE DATABASE librenms CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER 'librenms'@'localhost' IDENTIFIED BY '$DB_PASSWORD_LIBRENMS';
    GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';
    FLUSH PRIVILEGES;
    "
}

configure_php_fpm() {
    cp /etc/php/8.2/fpm/pool.d/www.conf /etc/php/8.2/fpm/pool.d/librenms.conf
    sed -i 's/\[www\]/\[librenms\]/' /etc/php/8.2/fpm/pool.d/librenms.conf
    sed -i 's/^user = .*/user = librenms/' /etc/php/8.2/fpm/pool.d/librenms.conf
    sed -i 's/^group = .*/group = librenms/' /etc/php/8.2/fpm/pool.d/librenms.conf
    sed -i 's|^listen = .*|listen = /run/php-fpm-librenms.sock|' /etc/php/8.2/fpm/pool.d/librenms.conf
}

configure_nginx() {
    cat > /etc/nginx/sites-enabled/librenms.vhost <<EOF
server {
    listen      80;
    server_name $NGINX_SERVER_NAME;
    root        /opt/librenms/html;
    index       index.php;
    charset utf-8;
    gzip on;
    gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    location ~ [^/]\.php(/|\$) {
        fastcgi_pass unix:/run/php-fpm-librenms.sock;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        include fastcgi.conf;
    }
    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
    rm -f /etc/nginx/sites-enabled/default
    systemctl reload nginx
    systemctl restart php8.2-fpm
}

configure_snmpd() {
    cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
    sed -i "s/RANDOMSTRINGGOESHERE/$SNMPD_COMMUNITY/" /etc/snmp/snmpd.conf
    curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
    chmod +x /usr/bin/distro
    systemctl enable snmpd
    systemctl restart snmpd
}

setup_cron_jobs() {
    cp /opt/librenms/dist/librenms.cron /etc/cron.d/librenms
    cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms
}

enable_scheduler() {
    cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/
    systemctl enable librenms-scheduler.timer
    systemctl start librenms-scheduler.timer
}

# Exécution des fonctions
install_packages
create_librenms_user
download_librenms
set_permissions
install_php_dependencies
configure_timezone
configure_mariadb
create_database
configure_php_fpm
configure_nginx
configure_snmpd
setup_cron_jobs
enable_scheduler

This paste expires in <1 hour. Public IP access. Share whatever you see with others in seconds with Context.Terms of ServiceReport this
