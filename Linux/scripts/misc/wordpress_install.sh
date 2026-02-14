#!/bin/bash
# WordPress Automated Installation Script
# Converted from Salt State configuration

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}[+] Starting WordPress Installation${NC}"

# Install required packages
echo -e "${BLUE}[*] Installing required packages...${NC}"
apt-get update
apt-get install -y \
    apache2 \
    mariadb-server \
    php \
    libapache2-mod-php \
    php-mysql \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-xmlrpc \
    php-zip \
    wget \
    unzip

# Enable Apache modules
echo -e "${BLUE}[*] Enabling Apache modules...${NC}"
a2enmod rewrite

# Start and enable MariaDB
echo -e "${BLUE}[*] Starting MariaDB service...${NC}"
systemctl start mariadb
systemctl enable mariadb

# Wait for MariaDB to be ready
sleep 3

# Create database and set up user
echo -e "${BLUE}[*] Setting up database...${NC}"
mysql -e "CREATE DATABASE IF NOT EXISTS wordpress;"
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '';"
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'root'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Download WordPress
echo -e "${BLUE}[*] Downloading WordPress...${NC}"
cd /var/www/html
if [ ! -f wordpress-6.3.1.tar.gz ]; then
    wget https://wordpress.org/wordpress-6.3.1.tar.gz
fi

# Extract WordPress
echo -e "${BLUE}[*] Extracting WordPress...${NC}"
tar -xzf wordpress-6.3.1.tar.gz

# Set ownership and permissions
echo -e "${BLUE}[*] Setting permissions...${NC}"
chown -R www-data:www-data /var/www/html/wordpress
chmod -R 755 /var/www/html/wordpress

# Create wp-config.php
echo -e "${BLUE}[*] Creating wp-config.php...${NC}"
cat > /var/www/html/wordpress/wp-config.php << 'EOF'
<?php
/**
 * The base configuration for WordPress
 */

// ** Database settings ** //
define( 'DB_NAME', 'wordpress' );
define( 'DB_USER', 'root' );
define( 'DB_PASSWORD', '' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication unique keys and salts.
 */
define('AUTH_KEY',         'put your unique phrase here');
define('SECURE_AUTH_KEY',  'put your unique phrase here');
define('LOGGED_IN_KEY',    'put your unique phrase here');
define('NONCE_KEY',        'put your unique phrase here');
define('AUTH_SALT',        'put your unique phrase here');
define('SECURE_AUTH_SALT', 'put your unique phrase here');
define('LOGGED_IN_SALT',   'put your unique phrase here');
define('NONCE_SALT',       'put your unique phrase here');

/**#@-*/

/**
 * WordPress database table prefix.
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 */
define( 'WP_DEBUG', false );

/* Add any custom values between this line and the "stop editing" line. */

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
EOF

chown www-data:www-data /var/www/html/wordpress/wp-config.php
chmod 755 /var/www/html/wordpress/wp-config.php

# Clean up tarball
echo -e "${BLUE}[*] Cleaning up WordPress tarball...${NC}"
rm -f /var/www/html/wordpress-6.3.1.tar.gz

# Download and install WP-CLI
echo -e "${BLUE}[*] Installing WP-CLI...${NC}"
if [ ! -f /usr/local/bin/wp ]; then
    wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -O /usr/local/bin/wp
    chmod 755 /usr/local/bin/wp
fi

# Run WordPress installation
echo -e "${BLUE}[*] Running WordPress core installation...${NC}"
cd /var/www/html/wordpress
wp core install \
    --url=blog.machine.place \
    --title="Gabe's Hardware Hacking" \
    --admin_user=admin \
    --admin_password="machine-PLACE-4!" \
    --admin_email=administrator@machine.place \
    --allow-root

# Download Ultimate Member plugin
echo -e "${BLUE}[*] Downloading Ultimate Member plugin...${NC}"
cd /var/www/html/wordpress/wp-content/plugins
if [ ! -f ultimate-member.2.6.6.zip ]; then
    wget https://downloads.wordpress.org/plugin/ultimate-member.2.6.6.zip
fi

# Extract Ultimate Member plugin
echo -e "${BLUE}[*] Extracting Ultimate Member plugin...${NC}"
unzip -o ultimate-member.2.6.6.zip

# Set permissions for Ultimate Member
chown -R www-data:www-data /var/www/html/wordpress/wp-content/plugins/ultimate-member
chmod -R 755 /var/www/html/wordpress/wp-content/plugins/ultimate-member

# Clean up plugin zip
rm -f ultimate-member.2.6.6.zip

# Activate Ultimate Member plugin
echo -e "${BLUE}[*] Activating Ultimate Member plugin...${NC}"
cd /var/www/html/wordpress
if ! wp plugin is-active ultimate-member --allow-root 2>/dev/null; then
    wp plugin activate ultimate-member --allow-root
fi

# Disable default Apache site
echo -e "${BLUE}[*] Disabling default Apache site...${NC}"
a2dissite 000-default.conf || true

# Create Apache virtual host configuration
echo -e "${BLUE}[*] Creating Apache virtual host configuration...${NC}"
cat > /etc/apache2/sites-available/blog.machine.place.conf << 'EOF'
<VirtualHost *:80>
    ServerName blog.machine.place
    ServerAdmin administrator@machine.place
    DocumentRoot /var/www/html/wordpress

    <Directory /var/www/html/wordpress>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/wordpress_error.log
    CustomLog ${APACHE_LOG_DIR}/wordpress_access.log combined
</VirtualHost>
EOF

chmod 644 /etc/apache2/sites-available/blog.machine.place.conf

# Enable WordPress site
echo -e "${BLUE}[*] Enabling WordPress site...${NC}"
a2ensite blog.machine.place.conf

# Reload systemd and restart Apache
echo -e "${BLUE}[*] Reloading systemd and restarting Apache...${NC}"
systemctl daemon-reload
systemctl enable apache2
systemctl restart apache2

echo -e "${GREEN}[+] WordPress installation complete!${NC}"
echo -e "${YELLOW}[!] Site URL: http://blog.machine.place${NC}"
echo -e "${YELLOW}[!] Admin User: admin${NC}"
echo -e "${YELLOW}[!] Admin Password: machine-PLACE-4!${NC}"
echo -e "${YELLOW}[!] Make sure to update /etc/hosts or DNS to point blog.machine.place to this server${NC}"
echo -e "${RED}[!] IMPORTANT: Change the WordPress salts in wp-config.php for security!${NC}"
echo -e "${RED}[!] IMPORTANT: Change the default admin password after login!${NC}"
