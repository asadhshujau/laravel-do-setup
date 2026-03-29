#!/bin/bash
# =============================================================================
# Laravel API Server Setup Script for DigitalOcean (Ubuntu 24.04 LTS)
# =============================================================================
#
# BEFORE RUNNING:
#   1. Generate an SSH key for the deploy user (see README.md — Step 3)
#   2. Edit the CONFIGURATION section below with your values
#   3. Run as root:
#        chmod +x laravel-server-setup.sh
#        ./laravel-server-setup.sh
#
# =============================================================================

set -e

# ---------------------------
# CONFIGURATION - EDIT THESE
# ---------------------------
APP_DOMAIN="your-domain.com"           # Your domain or droplet IP address
APP_DIR="/var/www/your-app"            # Where your Laravel app will live
DB_NAME="laravel"                      # MySQL database name
DB_USER="laravel_user"                 # MySQL username
DB_PASS="CHANGE_ME_STRONG_PASSWORD"    # MySQL password - CHANGE THIS!
PHP_VERSION="8.4"                      # PHP version (8.3, 8.4, etc.)
DEPLOY_USER="deploy"                   # Non-root user for app tasks
GIT_REPO=""                            # Git SSH URL (leave empty to enter during setup)
                                       # Format: git@github.com:username/repo.git

echo "============================================"
echo "  Laravel API Server Setup"
echo "  Ubuntu 24.04 LTS | DigitalOcean"
echo "============================================"

# ---------------------------
# Preflight checks
# ---------------------------
if [ "$EUID" -ne 0 ]; then
    echo "  ERROR: This script must be run as root."
    exit 1
fi

if [ "$DB_PASS" = "CHANGE_ME_STRONG_PASSWORD" ]; then
    echo ""
    echo "  ERROR: You must change DB_PASS before running this script."
    echo "  Edit the CONFIGURATION section at the top of this file."
    echo ""
    exit 1
fi

# ---------------------------
# STEP 1: System Update
# ---------------------------
echo ""
echo "[1/12] Updating system packages..."
apt update && apt upgrade -y

# ---------------------------
# STEP 2: Install Git & Utilities
# ---------------------------
echo ""
echo "[2/12] Installing Git, Supervisor, and utilities..."
apt install -y git unzip supervisor acl

# ---------------------------
# STEP 3: Create Deploy User
# ---------------------------
echo ""
echo "[3/12] Creating deploy user..."

if id "${DEPLOY_USER}" &>/dev/null; then
    echo "  -> User '${DEPLOY_USER}' already exists, skipping"
else
    adduser --disabled-password --gecos "" ${DEPLOY_USER}
    # Add to www-data group so Nginx can read files
    usermod -aG www-data ${DEPLOY_USER}
    echo "  -> User '${DEPLOY_USER}' created"
fi

# Copy root's SSH key to deploy user so they can SSH in too
if [ -f /root/.ssh/authorized_keys ]; then
    mkdir -p /home/${DEPLOY_USER}/.ssh
    cp /root/.ssh/authorized_keys /home/${DEPLOY_USER}/.ssh/
    chown -R ${DEPLOY_USER}:${DEPLOY_USER} /home/${DEPLOY_USER}/.ssh
    chmod 700 /home/${DEPLOY_USER}/.ssh
    chmod 600 /home/${DEPLOY_USER}/.ssh/authorized_keys
    echo "  -> SSH keys copied (you can now ssh ${DEPLOY_USER}@your-ip)"
fi

# Allow deploy user to restart services without password
cat > /etc/sudoers.d/${DEPLOY_USER} <<SUDOERS
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/sbin/service php${PHP_VERSION}-fpm restart
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl restart laravel-worker\:*
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl reread
${DEPLOY_USER} ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl update
SUDOERS
chmod 440 /etc/sudoers.d/${DEPLOY_USER}

# ---------------------------
# STEP 4: Clone Laravel Project
# ---------------------------
echo ""
echo "[4/12] Cloning Laravel project..."

if [ -z "$GIT_REPO" ]; then
    echo ""
    echo "  Enter your Git repo SSH URL"
    echo "  (e.g. git@github.com:username/repo.git)"
    echo ""
    read -p "  Repo URL: " GIT_REPO
fi

if [ -z "$GIT_REPO" ]; then
    echo "  ERROR: No repo URL provided. Exiting."
    exit 1
fi

mkdir -p $(dirname ${APP_DIR})

# Clone as deploy user (uses deploy user's SSH key for GitHub)
sudo -u ${DEPLOY_USER} git clone ${GIT_REPO} ${APP_DIR}

echo "  -> Project cloned to ${APP_DIR}"

# ---------------------------
# STEP 5: Add PHP Repository
# ---------------------------
echo ""
echo "[5/12] Adding PHP repository..."
apt install -y software-properties-common
add-apt-repository -y ppa:ondrej/php
apt update

# ---------------------------
# STEP 6: Install Nginx
# ---------------------------
echo ""
echo "[6/12] Installing Nginx..."
apt install -y nginx
systemctl enable nginx
systemctl start nginx

# ---------------------------
# STEP 7: Install PHP + Extensions
# ---------------------------
echo ""
echo "[7/12] Installing PHP ${PHP_VERSION} and extensions..."
apt install -y \
    php${PHP_VERSION}-fpm \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-pgsql \
    php${PHP_VERSION}-sqlite3 \
    php${PHP_VERSION}-redis \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-bcmath \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-intl \
    php${PHP_VERSION}-tokenizer \
    php${PHP_VERSION}-opcache

# Tune PHP-FPM for API usage
sed -i "s/upload_max_filesize = .*/upload_max_filesize = 64M/" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/post_max_size = .*/post_max_size = 64M/" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/memory_limit = .*/memory_limit = 256M/" /etc/php/${PHP_VERSION}/fpm/php.ini
sed -i "s/max_execution_time = .*/max_execution_time = 60/" /etc/php/${PHP_VERSION}/fpm/php.ini

# Enable OPcache for better performance
cat >> /etc/php/${PHP_VERSION}/fpm/conf.d/10-opcache.ini <<EOF
opcache.enable=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.validate_timestamps=0
opcache.save_comments=1
EOF

systemctl restart php${PHP_VERSION}-fpm

# ---------------------------
# STEP 8: Install Composer + Dependencies
# ---------------------------
echo ""
echo "[8/12] Installing Composer and project dependencies..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

cd ${APP_DIR}
sudo -u ${DEPLOY_USER} composer install --no-dev --optimize-autoloader

# ---------------------------
# STEP 9: Install MySQL + Setup Database
# ---------------------------
echo ""
echo "[9/12] Installing MySQL 8..."
apt install -y mysql-server

mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${DB_PASS}';"
mysql -u root -p"${DB_PASS}" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

echo "  -> Database '${DB_NAME}' created"
echo "  -> User '${DB_USER}' created with privileges"

# ---------------------------
# STEP 10: Configure Laravel
# ---------------------------
echo ""
echo "[10/12] Configuring Laravel..."

cd ${APP_DIR}

if [ ! -f .env ]; then
    sudo -u ${DEPLOY_USER} cp .env.example .env
    sudo -u ${DEPLOY_USER} php artisan key:generate

    sed -i "s/DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
    sed -i "s/DB_USERNAME=.*/DB_USERNAME=${DB_USER}/" .env
    sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
    sed -i "s/DB_HOST=.*/DB_HOST=127.0.0.1/" .env
    sed -i "s/APP_URL=.*/APP_URL=https:\/\/${APP_DOMAIN}/" .env
    sed -i "s/APP_ENV=.*/APP_ENV=production/" .env
    sed -i "s/APP_DEBUG=.*/APP_DEBUG=false/" .env

    echo "  -> .env created and configured"
else
    echo "  -> .env already exists, skipping"
fi

# Run migrations as deploy user
sudo -u ${DEPLOY_USER} php artisan migrate --force
echo "  -> Migrations complete"

# Set ownership: deploy user owns files, www-data group for Nginx
chown -R ${DEPLOY_USER}:www-data ${APP_DIR}
chmod -R 775 ${APP_DIR}/storage ${APP_DIR}/bootstrap/cache

# Build caches as deploy user
sudo -u ${DEPLOY_USER} php artisan config:cache
sudo -u ${DEPLOY_USER} php artisan route:cache
sudo -u ${DEPLOY_USER} php artisan view:cache
sudo -u ${DEPLOY_USER} php artisan event:cache
echo "  -> Caches built"

# ---------------------------
# STEP 11: Configure Nginx
# ---------------------------
echo ""
echo "[11/12] Configuring Nginx..."

rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/laravel <<'NGINX_CONF'
server {
    listen 80;
    listen [::]:80;
    server_name SERVER_NAME_PLACEHOLDER;

    root APP_DIR_PLACEHOLDER/public;
    index index.php;

    charset utf-8;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Max upload size (match PHP settings)
    client_max_body_size 64M;

    # Gzip compression for API responses
    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_types
        application/json
        application/javascript
        text/css
        text/plain
        text/xml
        application/xml;

    # Laravel routing
    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # PHP-FPM handling
    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/phpPHP_VERSION_PLACEHOLDER-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;

        fastcgi_read_timeout 60;
        fastcgi_send_timeout 60;
    }

    # Block dotfiles (except .well-known for SSL)
    location ~ /\.(?!well-known).* {
        deny all;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    access_log /var/log/nginx/laravel-access.log;
    error_log  /var/log/nginx/laravel-error.log;
}
NGINX_CONF

sed -i "s|SERVER_NAME_PLACEHOLDER|${APP_DOMAIN}|g" /etc/nginx/sites-available/laravel
sed -i "s|APP_DIR_PLACEHOLDER|${APP_DIR}|g" /etc/nginx/sites-available/laravel
sed -i "s|PHP_VERSION_PLACEHOLDER|${PHP_VERSION}|g" /etc/nginx/sites-available/laravel

ln -sf /etc/nginx/sites-available/laravel /etc/nginx/sites-enabled/laravel

nginx -t
systemctl reload nginx

# ---------------------------
# STEP 12: Firewall + Supervisor
# ---------------------------
echo ""
echo "[12/12] Configuring firewall and queue workers..."

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

cat > /etc/supervisor/conf.d/laravel-worker.conf <<SUPERVISOR
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${APP_DIR}/artisan queue:work --sleep=3 --tries=3 --max-time=3600
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${DEPLOY_USER}
numprocs=2
redirect_stderr=true
stdout_logfile=${APP_DIR}/storage/logs/worker.log
stopwaitsecs=3600
SUPERVISOR

supervisorctl reread
supervisorctl update

# ---------------------------
# Install Node.js
# ---------------------------
echo ""
echo "Installing Node.js 24 LTS..."
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt install -y nodejs

# ---------------------------
# Create deployment helper
# ---------------------------
cat > /usr/local/bin/deploy-laravel <<DEPLOY
#!/bin/bash
set -e

APP_DIR="${APP_DIR}"
PHP_VERSION="${PHP_VERSION}"
DEPLOY_USER="${DEPLOY_USER}"

cd \$APP_DIR

echo "-> Pulling latest code..."
sudo -u \$DEPLOY_USER git pull origin main

echo "-> Installing dependencies..."
sudo -u \$DEPLOY_USER composer install --no-dev --optimize-autoloader

echo "-> Running migrations..."
sudo -u \$DEPLOY_USER php artisan migrate --force

echo "-> Clearing and rebuilding caches..."
sudo -u \$DEPLOY_USER php artisan config:cache
sudo -u \$DEPLOY_USER php artisan route:cache
sudo -u \$DEPLOY_USER php artisan view:cache
sudo -u \$DEPLOY_USER php artisan event:cache

echo "-> Restarting queue workers..."
sudo -u \$DEPLOY_USER php artisan queue:restart

echo "-> Setting permissions..."
chown -R \$DEPLOY_USER:www-data storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

echo "-> Restarting PHP-FPM..."
systemctl restart php\${PHP_VERSION}-fpm

echo ""
echo "Deployment complete!"
DEPLOY

chmod +x /usr/local/bin/deploy-laravel

# ---------------------------
# DONE
# ---------------------------
echo ""
echo "============================================"
echo "  SETUP COMPLETE! Your API is live."
echo "============================================"
echo ""
echo "  App URL:        http://${APP_DOMAIN}"
echo "  App directory:  ${APP_DIR}"
echo "  Deploy user:    ${DEPLOY_USER}"
echo ""
echo "  Database:"
echo "     Name: ${DB_NAME}"
echo "     User: ${DB_USER}"
echo "     Pass: ${DB_PASS}"
echo ""
echo "  SSH access:"
echo "     ssh ${DEPLOY_USER}@YOUR_IP  (for app tasks)"
echo "     ssh root@YOUR_IP            (for system admin)"
echo ""
echo "  Next: Add SSL (HTTPS)"
echo "     apt install certbot python3-certbot-nginx"
echo "     certbot --nginx -d ${APP_DOMAIN}"
echo ""
echo "  Future deployments (as root):"
echo "     deploy-laravel"
echo ""
echo "============================================"
