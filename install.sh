#!/bin/bash


# Default values for the database and Moodle installation
DEFAULT_DB_NAME="moodle"
DEFAULT_DB_USER="moodleuser"
DEFAULT_DOMAIN="example.com"
DEFAULT_MOODLE_DIR="/var/www/html/moodle"
SSL_DIR="/etc/nginx/ssl_certificates"
DEFAULT_VERSION="v4.3.7"  # Default Moodle version

# Function to update the system
update_system() {
    sudo dnf update -y
}

# Function to disable SELinux
disable_selinux() {
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
}

# Function to install Nginx
install_nginx() {
    sudo tee /etc/yum.repos.d/nginx.repo <<EOL
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/\$releasever/\$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOL

    sudo dnf install -y nginx
    sudo systemctl enable --now nginx
}

# Function to install MariaDB
install_mariadb() {
    sudo tee /etc/yum.repos.d/MariaDB.repo <<EOL
[mariadb]
name = MariaDB
baseurl = https://yum.mariadb.org/10.6/rhel/\$releasever/\$basearch
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
enabled=1
EOL

    sudo dnf install -y MariaDB-server MariaDB-client
    sudo systemctl enable --now mariadb

    # Secure MariaDB installation
    sudo mysql_secure_installation
}

# Function to install Redis
install_redis() {
    sudo dnf install -y redis
    sudo systemctl enable --now redis
}

# Function to install PHP 8.2 and required modules
install_php() {
    sudo dnf install -y epel-release
    sudo dnf module reset php
    sudo dnf module enable php:8.0 -y
    sudo dnf install -y php php-cli php-fpm php-mysqlnd php-xml php-mbstring php-zip php-gd php-intl php-curl php-redis php-soap php-opcache php-sodium
    # PHP setting max_input_vars must be at least 5000
    sudo sed -i '/^;\s*max_input_vars\s*=\s*1000/!b;n;/^max_input_vars\s*=\s*5000/!a max_input_vars = 5000' /etc/php.ini
}

# Function to configure PHP-FPM
configure_php_fpm() {
    sudo tee /etc/php-fpm.d/www.conf > /dev/null <<EOF
[www]
user = nginx
group = nginx
listen = 127.0.0.1:9000
listen.allowed_clients = 127.0.0.1

pm = dynamic
pm.max_children = 50
pm.start_servers = 5
pm.min_spare_servers = 5
pm.max_spare_servers = 35

security.limit_extensions = .php

slowlog = /var/log/php-fpm/www-slow.log

php_admin_value[error_log] = /var/log/php-fpm/www-error.log
php_admin_flag[log_errors] = on

php_value[session.save_handler] = files
php_value[session.save_path]    = /var/lib/php/session
php_value[soap.wsdl_cache_dir]  = /var/lib/php/wsdlcache
EOF
}

# Function to prompt for database details with a timeout
prompt_for_db_details() {
    echo -n "Enter the Moodle database name [Default: ${DEFAULT_DB_NAME}]: "
    read -t 30 -r DB_NAME
    DB_NAME=${DB_NAME:-$DEFAULT_DB_NAME}

    echo -n "Enter the Moodle database username [Default: ${DEFAULT_DB_USER}]: "
    read -t 30 -r DB_USER
    DB_USER=${DB_USER:-$DEFAULT_DB_USER}

    # Generate a strong 20-character password for MariaDB with special symbols
    GENERATED_DB_PASS=$(openssl rand -base64 24 | tr -dc '[:alnum:]|\/)(!+' | head -c20)
    echo "Generated strong password for MariaDB: $GENERATED_DB_PASS"

    echo -n "Enter the Moodle database password or press Enter to use the generated password: "
    read -t 30 -r -s DB_PASS
    DB_PASS=${DB_PASS:-$GENERATED_DB_PASS}
    echo
}

# Function to generate SSL certificate
generate_ssl_certificate() {
    echo "Please enter your domain name:"
    read -t 30 DOMAIN_NAME
    if [ -z "$DOMAIN_NAME" ]; then
        DOMAIN_NAME=$DEFAULT_DOMAIN
    fi
    sudo mkdir -p /etc/nginx/ssl_certificates
    sudo openssl req -new -x509 -days 365 -nodes -out /etc/nginx/ssl_certificates/${DOMAIN_NAME}.crt -keyout /etc/nginx/ssl_certificates/${DOMAIN_NAME}.key -subj "/C=US/ST=State/L=City/O=Organization/OU=Department/CN=${DOMAIN_NAME}"
    sudo chmod 600 /etc/nginx/ssl_certificates/${DOMAIN_NAME}.key
}

##################################################################
# Function to ask Moodle version
#ask_moodle_version() {
 #   local moodle_version
#    echo  $DEFAULT_VERSION
#    echo "Type new Moodle version (example: 4.1.5, 4.2.2, 4.3.7, 4.4.1) or Enter to use default:"

 #   read -t 30 -r MOODLE_SHORT_VERSION

#    if [[ -z "$MOODLE_SHORT_VERSION" ]]; then
#        MOODLE_VERSION=$DEFAULT_VERSION
#    else
#        MOODLE_VERSION="v${MOODLE_SHORT_VERSION}"
#    fi

#    echo "$MOODLE_VERSION"
#}

# Function to install Moodle
install_moodle() {
    # Отримуємо правильну версію Moodle
#    local moodle_version
#    MOODLE_VERSION=$(ask_moodle_version)

    echo  $DEFAULT_VERSION
    echo "Type new Moodle version (example: 4.1.5, 4.2.2, 4.3.7, 4.4.1) or Enter to use default:"

    read -t 30 -r MOODLE_SHORT_VERSION

    if [[ -z "$MOODLE_SHORT_VERSION" ]]; then
        MOODLE_VERSION=$DEFAULT_VERSION
    else
        MOODLE_VERSION="v${MOODLE_SHORT_VERSION}"
    fi

#    echo "$MOODLE_VERSION"

    echo "Default Moodle version: $MOODLE_VERSION"
    
    # Check, is folder /var/www/html/moodle is empty and clone
    if [[ ! -d /var/www/html/moodle/.git ]]; then
        sudo mkdir -p /var/www/html/moodle
        cd /var/www/html/moodle || exit
        
        # Clone Moodle by teg
        sudo git clone --branch "$MOODLE_VERSION" --single-branch https://github.com/moodle/moodle.git /var/www/html/moodle/ 
    else
        echo "Moodle successully instaled in /var/www/html/moodle"
    fi


    # Create Moodledata folder and grant permissions
    sudo mkdir /var/moodledata
    sudo chmod -R 777 /var/moodledata
}

##################################################################

# Function to set permissions on Moodle directory
set_permissions() {
    sudo chown -R nginx:nginx /var/www/html/moodle
    sudo chmod -R 755 /var/www/html/moodle
}

# Function to configure Nginx
configure_nginx() {
    sudo tee /etc/nginx/conf.d/moodle.conf > /dev/null <<EOF
server {
        listen 80;
        server_name www.${DOMAIN_NAME} ${DOMAIN_NAME};

        location / {
            return 301 https://${DOMAIN_NAME}\$request_uri;
        }


}

server {
        listen 443 default_server ssl;
        server_name ${DOMAIN_NAME};

        root ${DEFAULT_MOODLE_DIR};

        index index.php;

        log_not_found off;
        access_log /var/log/nginx/${DOMAIN_NAME}.access.log;
        error_log /var/log/nginx/${DOMAIN_NAME}.error.log;

        location ~ [^/]\.php(/|$) {
            fastcgi_split_path_info  ^(.+\.php)(/.+)$;
            fastcgi_index            index.php;
            fastcgi_pass             127.0.0.1:9000;
            include                  fastcgi_params;
            fastcgi_param   PATH_INFO       \$fastcgi_path_info;
            fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            fastcgi_read_timeout 250s;
        }

        location /dataroot/ {
            internal;
            alias /var/moodledata; # ensure the path ends with /
        }


        client_max_body_size 11000M;
        fastcgi_keep_conn on;

        location = /robots.txt {
            alias /var/www/html/robots.txt;
        }

        # Protection against illegal HTTP methods. Out of the box only HEAD
        if ( \$request_method !~ ^(?:GET|HEAD|POST|PUT|DELETE|OPTIONS)$ ) {
            return 405;
        }

        # Disable .htaccess git and other and other hidden files
        location ~ /\. {
            return 404;
        }

         location ~* ^(?:.+\.(?:htaccess|make|engine|inc|info|install|module|profile|po|pot|sh|.*sql|test|theme|tpl(?:\.php)?|xtmpl)|code-style\.pl|/Entries.*|/Repository|/Root|/Tag|/Template)$ {
            return 404;
        }

        # This should be after the php fpm rule and very close to the last nginx ruleset.
        # Don't allow direct access to various internal files. See MDL-69333
        location ~ (/vendor/|/node_modules/|composer\.json|/readme|/README|readme\.txt|/upgrade\.txt|db/install\.xml|/fixtures/|/behat/|phpunit\.xml|\.lock|environment\.xml) {
            deny all;
            return 404;
        }


        #gzip compression
        gzip on;
        gzip_comp_level 3;
        gzip_vary on;
        gzip_static off;
        gzip_types text/css text/plain application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript text/x-js;
        gzip_min_length 1024;
        gzip_disable "MSIE [1-6].(?!.*SV1)";
        gzip_proxied any;

        #ssl on;
        ssl_certificate ${SSL_DIR}/${DOMAIN_NAME}.crt;
        ssl_certificate_key ${SSL_DIR}/${DOMAIN_NAME}.key;
        ssl_session_cache shared:SSL:20m;
        ssl_session_timeout 180m;
        ssl_protocols TLSv1.1 TLSv1.2;
        ssl_prefer_server_ciphers on;
        ssl_ciphers ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS;

}
EOF
}

# Function to create Moodle database and user
create_moodle_db() {
    prompt_for_db_details

    sudo mysql -e "CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    sudo mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
    sudo mysql -e "FLUSH PRIVILEGES;"
}

# Function to start services
start_services() {
    sudo systemctl restart nginx
    sudo systemctl restart php-fpm
    sudo systemctl restart mariadb
    sudo systemctl enable nginx
    sudo systemctl enable php-fpm
    sudo systemctl enable mariadb
}
################################################################################################

    # Main script
main() {
    update_system
    disable_selinux
    install_nginx
    install_mariadb
    install_redis
    install_php
    configure_php_fpm
    generate_ssl_certificate
    install_moodle
    set_permissions
    configure_nginx
    create_moodle_db
    start_services
}

main
