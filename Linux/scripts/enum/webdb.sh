#!/bin/sh
# @d_tranman/Nigel Gerald/Nigerald
# KaliPatriot | TTU CCDC | Landon Byrge
# 7oister150  | TTU CCDC | Landon Foister

IS_RHEL=false
IS_DEBIAN=false
IS_ALPINE=false
IS_SLACK=false
IS_BSD=false
IS_SUSE=false
IS_ARCH=false

ORAG=''
GREEN=''
YELLOW=''
BLUE=''
RED=''
NC=''

if echo -e "test" | grep -qE '\-e'; then
    ECHO='echo'
else
    ECHO='echo -e'
fi

if [ -z "$DEBUG" ]; then
    DPRINT() { 
        "$@" 2>/dev/null 
    }
else
    DPRINT() { 
        "$@" 
    }
fi

RHEL(){
  IS_RHEL=true
}

SUSE(){
  IS_SUSE=true
}

DEBIAN(){
  IS_DEBIAN=true
}

UBUNTU(){
  DEBIAN
}

ALPINE(){
  IS_ALPINE=true
}

SLACK(){
  IS_SLACK=true
}

ARCH(){
  IS_ARCH=true
}

BSD(){
  IS_BSD=true
}


if command -v yum >/dev/null ; then
  RHEL
elif command -v zypper >/dev/null ; then
  SUSE
elif command -v apt-get >/dev/null ; then
  if $( cat /etc/os-release | grep -qi Ubuntu ); then
      UBUNTU
  else
      DEBIAN
  fi
elif command -v apk >/dev/null ; then
  ALPINE
elif command -v slapt-get >/dev/null || ( cat /etc/os-release | grep -i slackware ) ; then
  SLACK
elif command -v pacman >/dev/null ; then
  ARCH
elif command -v pkg >/dev/null || command -v pkg_info >/dev/null; then
    BSD
fi

if [ -n "$COLOR" ]; then
    ORAG='\033[0;33m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;36m'
    NC='\033[0m'
fi

echo ""
${ECHO} "${GREEN}#############SERVICE INFORMATION############${NC}"
if [ $IS_ALPINE = true ]; then
    SERVICES=$( rc-status -s | grep started | awk '{print $1}' )
elif [ $IS_SLACK = true ]; then
    SERVICES=$( ls -la /etc/rc.d | grep rwx | awk '{print $9}' ) 
elif [ $IS_BSD = true ]; then
    SERVICES=$( cat /etc/rc.conf /etc/rc.conf.d/* | grep -i "_enable" | grep -i "yes" | awk -F "_enable" '{print $1}' )
else
    SERVICES=$( DPRINT systemctl --type=service | grep active | awk '{print $1}' || service --status-all | grep -E '(+|is running)' )
fi
APACHE2=false
NGINX=false
checkService()
{
    serviceList=$1
    serviceToCheckExists=$2
    serviceAlias=$3                

	serviceGrep="$serviceToCheckExists"
	if [ -n "$serviceAlias" ]; then
		serviceGrep="$serviceAlias\|$serviceToCheckExists"
	fi

	if echo "$serviceList" | grep -qi "$serviceGrep"; then
		${ECHO} "\n${BLUE}[+] $serviceToCheckExists is on this machine${NC}\n"

		if [ "$( DPRINT sockstat -l | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(sockstat -l | grep -i "$serviceGrep" | grep -i ":" | awk 'BEGIN {ORS=" and " } {print $6}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		elif [ "$( DPRINT netstat -tulpn | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(netstat -tulpn | grep -i "$serviceGrep" | awk 'BEGIN {ORS=" and "} {print $1, $4}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		elif [ "$( DPRINT ss -blunt -p | grep -i "$serviceGrep" )" ]; then
			${ECHO} "Active on port(s) ${YELLOW}$(ss -blunt -p | grep -i "$serviceGrep" | awk 'BEGIN {ORS=" and " } {print $1,$5}' | sed 's/\(.*\)and /\1\n/')${NC}\n"
		fi
    
           

	fi

}

if checkService "$SERVICES"  'docker' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'docker'

    ACTIVECONTAINERS=$( docker ps )
    if [ -n "$ACTIVECONTAINERS" ]; then
        echo "Current Active Containers"
        ${ECHO} "${ORAG}$ACTIVECONTAINERS${NC}\n"
    fi

    ANONMOUNTS=$( docker ps -q | DPRINT xargs -n 1 docker inspect --format '{{if .Mounts}}{{.Name}}: {{range .Mounts}}{{.Source}} -> {{.Destination}}{{end}}{{end}}' | grep -vE '^$' | sed 's/^\///g' )
    if [ -n "$ANONMOUNTS" ]; then
        echo "Anonymous Container Mounts (host -> container)"
        ${ECHO} "${ORAG}$ANONMOUNTS${NC}\n"
    fi

    VOLUMES="$( DPRINT docker volume ls --format "{{.Name}}" )"
    if [ -n "$VOLUMES" ]; then
        echo "Volumes"
        for v in $VOLUMES; do
            container=$( DPRINT docker ps -a --filter volume=$v --format '{{.Names}}' | tr '\n' ',' | sed 's/,$//g' )
            if [ -n "$container" ]; then
                mountpoint=$( echo $( DPRINT docker volume inspect --format '{{.Name}}: {{.Mountpoint}}' $v ) | awk -F ': ' '{print $2}' )
                ${ECHO} "${ORAG}$v -> $mountpoint used by $container${NC}"
            fi
        done
        echo ""
    fi
fi

if checkService "$SERVICES" 'apache2' 'httpd' | grep -qi "is on this machine"; then
    checkService "$SERVICES" 'apache2' 'httpd'

    if [ $IS_BSD = true ]; then
        APACHE2VHOSTS=$(tail -n +1 /usr/local/etc/apache24/httpd.conf /usr/local/etc/apache24/extra/httpd-vhosts.conf |
            grep -v '#' |
            grep -E '==>|VirtualHost|ServerName|DocumentRoot|ServerAlias|Proxy')
    else
        if [ -d "/etc/httpd" ]; then
            APACHE2VHOSTS=$(tail -n +1 /etc/httpd/conf.d/* /etc/httpd/conf/httpd.conf |
                grep -v '#' |
                grep -E '==>|VirtualHost|ServerName|DocumentRoot|ServerAlias|Proxy')
        else
            APACHE2VHOSTS=$(tail -n +1 /etc/apache2/sites-enabled/* /etc/apache2/apache2.conf |
                grep -v '#' |
                grep -E '==>|VirtualHost|ServerName|DocumentRoot|ServerAlias|Proxy')
        fi
    fi

    ${ECHO} "\n[!] Configuration Details\n"
    ${ECHO} "${ORAG}$APACHE2VHOSTS${NC}"
    APACHE2=true
fi

if checkService "$SERVICES"  'nginx' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'nginx'
    NGINXCONFIG=$(tail -n +1 /etc/nginx/sites-enabled/* /etc/nginx/nginx.conf| grep -v '#'  | grep -E '==>|server|listen|root|server_name|proxy_')
    ${ECHO} "\n[!] Configuration Details\n"
    ${ECHO} "${ORAG}$NGINXCONFIG${NC}"
    NGINX=true
fi

sql_test(){

    if [ -f /lib/systemd/system/mysql.service ]; then
        SQL_SYSD=/lib/systemd/system/mysql.service
    elif [ -f /lib/systemd/system/mariadb.service ]; then
        SQL_SYSD=/lib/systemd/system/mariadb.service
    fi
    
    if [ -n "$SQL_SYSD" ]; then
        SQL_SYSD_INFO=$( grep -RE '^(User=|Group=)' $SQL_SYSD )
    fi
    
    if [ -d /etc/mysql ]; then
        SQLDIR=/etc/mysql
    elif [ -d /etc/my.cnf.d/ ]; then
        SQLDIR=/etc/my.cnf.d/
    fi

    if [ -n "$SQLDIR" ]; then
        SQLCONFINFO=$( DPRINT find $SQLDR *sql*.cnf *-server.cnf | sed 's/:user\s*/ ===> user /' | sed 's/bind-address\s*/ ===> bind-address /' )
    fi

    if [ -n "$SQLCONFINFO" ]; then
        ${ECHO} "${ORAG}$SQLCONFINFO${NC}"
    fi

    if [ -n "$SQL_SYSD_INFO" ]; then
        ${ECHO} "${ORAG}$SQL_SYSD:\n$SQL_SYSD_INFO${NC}\n"
    fi

    SQL_AUTH=1

    if mysql -uroot -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
        ${ECHO} "${RED}Can login as root, with root and no password${NC}\n"
        SQLCMD="mysql -uroot"
    fi

    if mysql -uroot -proot -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
        ${ECHO} "${RED}Can login with root:root${NC}\n"
        SQLCMD="mysql -uroot -proot"
    fi

    if mysql -uroot -ppassword -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
        ${ECHO} "${RED}Can login with root:password${NC}\n"
        SQLCMD="mysql -uroot -ppassword"
    fi

    if [ -n "$DEFAULT_PASS" ]; then
        if mysql -uroot -p"$DEFAULT_PASS" -e 'bruh' 2>&1 >/dev/null | grep -v '\[Warning\]' | grep -q 'bruh'; then
            ${ECHO} "${RED}Can login with root:$DEFAULT_PASS${NC}\n"
            SQLCMD="mysql -uroot -p$DEFAULT_PASS"
        fi
    fi

    if [ -z "$SQLCMD" ]; then
        SQL_AUTH=0
    fi
    
    if [ "$SQL_AUTH" = 1 ]; then
        echo "SQL User Information"
        ${ECHO} "${ORAG}$( DPRINT $SQLCMD -t -e 'select user,host,plugin,authentication_string from mysql.user where password_expired="N";' )${NC}\n" 
        DATABASES=$( DPRINT $SQLCMD -t -e 'show databases' | grep -vE '^\|\s(mysql|information_schema|performance_schema|sys|test)\s+\|' )
        if [ -n "$DATABASES" ]; then
            echo "SQL Databases"
            ${ECHO} "${ORAG}$DATABASES${NC}\n"
        fi
    else
        echo "Cannot login with weak creds or default credentials"
    fi
}
if checkService "$SERVICES"  'mysql' | grep -qi "is on this machine"; then 
    MYSQL=true
    checkService "$SERVICES"  'mysql' 
    sql_test
fi

if checkService "$SERVICES"  'mariadb' | grep -qi "is on this machine"; then 
    MARIADB=true
    checkService "$SERVICES"  'mariadb'
    sql_test
fi
if checkService "$SERVICES" 'mssql-server' | grep -qi "is on this machine" ; then
    sqlserver=true
    checkService "$SERVICES" 'mssql-server' 'sqlservr'
fi
if checkService "$SERVICES"  'postgres' | grep -qi "is on this machine" ; then
    POSTGRESQL=true
    checkService "$SERVICES" 'postgres' || checkService "$SERVICES" 'postgres' 'postmaster'
    PSQLHBA=$( grep -REvh '(#|^\s*$|replication)' $( DPRINT find /etc/postgresql/ /var/lib/pgsql/ /var/lib/postgres* -name pg_hba.conf | head -n 1 ) )
    ${ECHO} "PostgreSQL Authentication Details\n"
    ${ECHO} "${ORAG}$PSQLHBA${NC}\n"

    if DPRINT psql -U postgres -c '\q'; then
        AUTH=1
        DB_CMD=" psql -U postgres -c \l "
    elif DPRINT sudo -u postgres psql -c '\q'; then
        AUTH=1
        DB_CMD=" sudo -u postgres psql -c \l "
    fi
    if [ "$AUTH" = 1 ]; then
        DATABASES="$( DPRINT $DB_CMD | grep -vE '^\s(postgres|template0|template1|\s+)\s+\|' | head -n -2 )"
        if [ "$( echo "$DATABASES" | wc -l )" -gt 2 ]; then
            echo "PostgreSQL Databases"
            ${ECHO} "${ORAG}$DATABASES${NC}\n"
        fi
    fi
fi

if checkService "$SERVICES"  'php' | grep -qi "is on this machine"; then
    checkService "$SERVICES"  'php'
    PHP=true
    PHPINILOC=$( find / -name php.ini 2> /dev/null )
    ${ECHO} "\n[!] php.ini location(s): "
    ${ECHO} "${ORAG}$PHPINILOC${NC}"
    for ini in $PHPINILOC; do
        DISABLEDFUNCTIONS=$( grep -i 'disable_functions' $ini | grep -vE '^;|^$' )
        if [ -n "$DISABLEDFUNCTIONS" ]; then
            ${ECHO} "\n[!] Disabled Functions in $ini"
            ${ECHO} "${ORAG}$DISABLEDFUNCTIONS${NC}"
        else
            ${ECHO} "\n${RED}[!] No disabled functions found in $ini${NC}"
        fi
    done
fi

${ECHO} "\n${GREEN}#############CMS/E-COMMERCE DETECTION#############${NC}"

# WordPress Detection
WPCONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -name "wp-config.php" -type f )
if [ -n "$WPCONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] WordPress installations found${NC}\n"
    for wpconfig in $WPCONFIGS; do
        ${ECHO} "${YELLOW}WordPress Config:${NC} $wpconfig"
        WPDBNAME=$( grep -E "define.*DB_NAME" "$wpconfig" | grep -v '//' | head -n 1 | sed -E "s/.*['\"]DB_NAME['\"],\s*['\"]([^'\"]+).*/\1/" )
        WPDBUSER=$( grep -E "define.*DB_USER" "$wpconfig" | grep -v '//' | head -n 1 | sed -E "s/.*['\"]DB_USER['\"],\s*['\"]([^'\"]+).*/\1/" )
        WPDBPASS=$( grep -E "define.*DB_PASSWORD" "$wpconfig" | grep -v '//' | head -n 1 | sed -E "s/.*['\"]DB_PASSWORD['\"],\s*['\"]([^'\"]+).*/\1/" )
        WPDBHOST=$( grep -E "define.*DB_HOST" "$wpconfig" | grep -v '//' | head -n 1 | sed -E "s/.*['\"]DB_HOST['\"],\s*['\"]([^'\"]+).*/\1/" )
        WPTABLEPREFIX=$( grep -E "^\s*\\\$table_prefix" "$wpconfig" | head -n 1 | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
        
        ${ECHO} "  ${ORAG}Database Host: $WPDBHOST${NC}"
        ${ECHO} "  ${ORAG}Database Name: $WPDBNAME${NC}"
        ${ECHO} "  ${ORAG}Database User: $WPDBUSER${NC}"
        ${ECHO} "  ${ORAG}Database Pass: $WPDBPASS${NC}"
        ${ECHO} "  ${ORAG}Table Prefix: $WPTABLEPREFIX${NC}"
        
        # Check for WooCommerce
        WPDIR=$( dirname "$wpconfig" )
        if [ -d "$WPDIR/wp-content/plugins/woocommerce" ]; then
            ${ECHO} "  ${RED}[!] WooCommerce plugin detected${NC}"
        fi
        
        # Check for other common plugins
        if [ -d "$WPDIR/wp-content/plugins" ]; then
            PLUGINS=$( ls -1 "$WPDIR/wp-content/plugins" 2>/dev/null | grep -E '(jetpack|wordfence|elementor|yoast|akismet|contact-form-7)' | tr '\n' ',' | sed 's/,$//' )
            if [ -n "$PLUGINS" ]; then
                ${ECHO} "  ${ORAG}Notable Plugins: $PLUGINS${NC}"
            fi
        fi
        echo ""
    done
fi

# Drupal Detection
DRUPALCONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -path "*/sites/*/settings.php" -type f )
if [ -n "$DRUPALCONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] Drupal installations found${NC}\n"
    for drupalconfig in $DRUPALCONFIGS; do
        ${ECHO} "${YELLOW}Drupal Config:${NC} $drupalconfig"
        
        # Drupal 7 format
        DRUPAL7DB=$( grep -A5 "\$databases\s*=" "$drupalconfig" | grep -E "database|username|password|host" | sed "s/['\",]//g" | sed 's/^\s*/  /' )
        
        # Drupal 8+ format (same structure but might have different formatting)
        if [ -n "$DRUPAL7DB" ]; then
            ${ECHO} "${ORAG}Database Configuration:${NC}"
            ${ECHO} "${ORAG}$DRUPAL7DB${NC}"
        fi
        
        # Check Drupal version
        DRUPALDIR=$( dirname "$( dirname "$drupalconfig" )" )
        if [ -f "$DRUPALDIR/core/lib/Drupal.php" ]; then
            DRUPALVER=$( grep "const VERSION" "$DRUPALDIR/core/lib/Drupal.php" | sed -E "s/.*['\"]([0-9.]+).*/\1/" )
            ${ECHO} "  ${ORAG}Drupal Version: $DRUPALVER${NC}"
        elif [ -f "$DRUPALDIR/includes/bootstrap.inc" ]; then
            DRUPALVER=$( grep "define('VERSION'" "$DRUPALDIR/includes/bootstrap.inc" | sed -E "s/.*['\"]([0-9.]+).*/\1/" )
            ${ECHO} "  ${ORAG}Drupal Version: $DRUPALVER${NC}"
        fi
        echo ""
    done
fi

# Joomla Detection
JOOMLACONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -name "configuration.php" -type f -path "*/joomla/*" -o -name "configuration.php" -type f -exec grep -l "JConfig" {} \; )
if [ -n "$JOOMLACONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] Joomla installations found${NC}\n"
    for joomlaconfig in $JOOMLACONFIGS; do
        # Verify it's actually Joomla by checking for JConfig class
        if grep -q "class JConfig" "$joomlaconfig" 2>/dev/null; then
            ${ECHO} "${YELLOW}Joomla Config:${NC} $joomlaconfig"
            JOOMLADBHOST=$( grep "public \$host" "$joomlaconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
            JOOMLADBNAME=$( grep "public \$db\s*=" "$joomlaconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
            JOOMLADBUSER=$( grep "public \$user" "$joomlaconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
            JOOMLADBPASS=$( grep "public \$password" "$joomlaconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
            JOOMLADBPREFIX=$( grep "public \$dbprefix" "$joomlaconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
            
            ${ECHO} "  ${ORAG}Database Host: $JOOMLADBHOST${NC}"
            ${ECHO} "  ${ORAG}Database Name: $JOOMLADBNAME${NC}"
            ${ECHO} "  ${ORAG}Database User: $JOOMLADBUSER${NC}"
            ${ECHO} "  ${ORAG}Database Pass: $JOOMLADBPASS${NC}"
            ${ECHO} "  ${ORAG}Table Prefix: $JOOMLADBPREFIX${NC}"
            echo ""
        fi
    done
fi

# Magento Detection
MAGENTOCONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -path "*/app/etc/env.php" -type f -o -path "*/app/etc/local.xml" -type f )
if [ -n "$MAGENTOCONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] Magento installations found${NC}\n"
    for magentoconfig in $MAGENTOCONFIGS; do
        ${ECHO} "${YELLOW}Magento Config:${NC} $magentoconfig"
        
        if echo "$magentoconfig" | grep -q "env.php"; then
            # Magento 2
            MAGENTODBHOST=$( grep -A20 "'db'" "$magentoconfig" | grep "'host'" | head -n 1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
            MAGENTODBNAME=$( grep -A20 "'db'" "$magentoconfig" | grep "'dbname'" | head -n 1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
            MAGENTODBUSER=$( grep -A20 "'db'" "$magentoconfig" | grep "'username'" | head -n 1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
            MAGENTODBPASS=$( grep -A20 "'db'" "$magentoconfig" | grep "'password'" | head -n 1 | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
            ${ECHO} "  ${ORAG}Magento Version: 2.x${NC}"
        else
            # Magento 1
            MAGENTODBHOST=$( grep -oP '<host><!\[CDATA\[\K[^\]]+' "$magentoconfig" 2>/dev/null )
            MAGENTODBNAME=$( grep -oP '<dbname><!\[CDATA\[\K[^\]]+' "$magentoconfig" 2>/dev/null )
            MAGENTODBUSER=$( grep -oP '<username><!\[CDATA\[\K[^\]]+' "$magentoconfig" 2>/dev/null )
            MAGENTODBPASS=$( grep -oP '<password><!\[CDATA\[\K[^\]]+' "$magentoconfig" 2>/dev/null )
            ${ECHO} "  ${ORAG}Magento Version: 1.x${NC}"
        fi
        
        ${ECHO} "  ${ORAG}Database Host: $MAGENTODBHOST${NC}"
        ${ECHO} "  ${ORAG}Database Name: $MAGENTODBNAME${NC}"
        ${ECHO} "  ${ORAG}Database User: $MAGENTODBUSER${NC}"
        ${ECHO} "  ${ORAG}Database Pass: $MAGENTODBPASS${NC}"
        echo ""
    done
fi

# PrestaShop Detection
PRESTACONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -path "*/app/config/parameters.php" -type f -o -path "*/config/settings.inc.php" -type f )
if [ -n "$PRESTACONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] PrestaShop installations found${NC}\n"
    for prestaconfig in $PRESTACONFIGS; do
        # Verify it's PrestaShop
        if grep -qE "(prestashop|_DB_SERVER_|_PS_)" "$prestaconfig" 2>/dev/null; then
            ${ECHO} "${YELLOW}PrestaShop Config:${NC} $prestaconfig"
            
            if echo "$prestaconfig" | grep -q "parameters.php"; then
                # PrestaShop 1.7+
                PRESTADBHOST=$( grep "database_host" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBNAME=$( grep "database_name" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBUSER=$( grep "database_user" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBPASS=$( grep "database_password" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBPREFIX=$( grep "database_prefix" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
            else
                # PrestaShop 1.6 and older
                PRESTADBHOST=$( grep "_DB_SERVER_" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBNAME=$( grep "_DB_NAME_" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBUSER=$( grep "_DB_USER_" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBPASS=$( grep "_DB_PASSWD_" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
                PRESTADBPREFIX=$( grep "_DB_PREFIX_" "$prestaconfig" | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/" )
            fi
            
            ${ECHO} "  ${ORAG}Database Host: $PRESTADBHOST${NC}"
            ${ECHO} "  ${ORAG}Database Name: $PRESTADBNAME${NC}"
            ${ECHO} "  ${ORAG}Database User: $PRESTADBUSER${NC}"
            ${ECHO} "  ${ORAG}Database Pass: $PRESTADBPASS${NC}"
            ${ECHO} "  ${ORAG}Table Prefix: $PRESTADBPREFIX${NC}"
            echo ""
        fi
    done
fi

# Laravel Detection
LARAVELCONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -name ".env" -type f -path "*/laravel/*" -o -name ".env" -type f -exec grep -l "APP_KEY" {} \; )
if [ -n "$LARAVELCONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] Laravel installations found${NC}\n"
    for laravelconfig in $LARAVELCONFIGS; do
        # Verify it's Laravel
        if grep -qE "APP_KEY|LARAVEL" "$laravelconfig" 2>/dev/null; then
            ${ECHO} "${YELLOW}Laravel Config:${NC} $laravelconfig"
            LARAVELDBHOST=$( grep "^DB_HOST=" "$laravelconfig" | cut -d'=' -f2 )
            LARAVELDBNAME=$( grep "^DB_DATABASE=" "$laravelconfig" | cut -d'=' -f2 )
            LARAVELDBUSER=$( grep "^DB_USERNAME=" "$laravelconfig" | cut -d'=' -f2 )
            LARAVELDBPASS=$( grep "^DB_PASSWORD=" "$laravelconfig" | cut -d'=' -f2 )
            LARAVELAPPURL=$( grep "^APP_URL=" "$laravelconfig" | cut -d'=' -f2 )
            
            ${ECHO} "  ${ORAG}Database Host: $LARAVELDBHOST${NC}"
            ${ECHO} "  ${ORAG}Database Name: $LARAVELDBNAME${NC}"
            ${ECHO} "  ${ORAG}Database User: $LARAVELDBUSER${NC}"
            ${ECHO} "  ${ORAG}Database Pass: $LARAVELDBPASS${NC}"
            ${ECHO} "  ${ORAG}App URL: $LARAVELAPPURL${NC}"
            echo ""
        fi
    done
fi

# Django Detection
DJANGOCONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -name "settings.py" -type f -exec grep -l "DATABASES" {} \; )
if [ -n "$DJANGOCONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] Django installations found${NC}\n"
    for djangoconfig in $DJANGOCONFIGS; do
        # Verify it's Django
        if grep -qE "django|DATABASES.*ENGINE" "$djangoconfig" 2>/dev/null; then
            ${ECHO} "${YELLOW}Django Config:${NC} $djangoconfig"
            DJANGODBINFO=$( grep -A10 "DATABASES" "$djangoconfig" | grep -E "ENGINE|NAME|USER|PASSWORD|HOST|PORT" | sed 's/^\s*/  /' )
            
            if [ -n "$DJANGODBINFO" ]; then
                ${ECHO} "${ORAG}Database Configuration:${NC}"
                ${ECHO} "${ORAG}$DJANGODBINFO${NC}"
            fi
            echo ""
        fi
    done
fi

# Moodle Detection
MOODLECONFIGS=$( DPRINT find /var/www /usr/local/www /srv /home -name "config.php" -type f -exec grep -l "CFG->dbtype" {} \; )
if [ -n "$MOODLECONFIGS" ]; then
    ${ECHO} "\n${BLUE}[+] Moodle installations found${NC}\n"
    for moodleconfig in $MOODLECONFIGS; do
        ${ECHO} "${YELLOW}Moodle Config:${NC} $moodleconfig"
        MOODLEDBHOST=$( grep "CFG->dbhost" "$moodleconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
        MOODLEDBNAME=$( grep "CFG->dbname" "$moodleconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
        MOODLEDBUSER=$( grep "CFG->dbuser" "$moodleconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
        MOODLEDBPASS=$( grep "CFG->dbpass" "$moodleconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
        MOODLEDBTYPE=$( grep "CFG->dbtype" "$moodleconfig" | sed -E "s/.*['\"]([^'\"]+).*/\1/" )
        
        ${ECHO} "  ${ORAG}Database Type: $MOODLEDBTYPE${NC}"
        ${ECHO} "  ${ORAG}Database Host: $MOODLEDBHOST${NC}"
        ${ECHO} "  ${ORAG}Database Name: $MOODLEDBNAME${NC}"
        ${ECHO} "  ${ORAG}Database User: $MOODLEDBUSER${NC}"
        ${ECHO} "  ${ORAG}Database Pass: $MOODLEDBPASS${NC}"
        echo ""
    done
fi


${ECHO} "\n${GREEN}##########################End of Output#########################${NC}"