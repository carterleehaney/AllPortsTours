#!/bin/sh
# NightWalk3r | Behnjamin Barlow | TTU CCDC
# Foister is just happy to be here

# ---- Backup Location ----
if [ -z "$BCK" ]; then
    BCK="/root/.cache"
fi

BCK="$BCK/backups"
mkdir -p "$BCK"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
echo -e "\033[34m[i] Backup location: $BCK\033[0m"
echo -e "\033[34m[i] Timestamp: $TIMESTAMP\033[0m"

# ---- Detect Web Root Directory ----
# Different distros use different default web hosting paths:
#   Ubuntu/Debian/CentOS/Fedora/RHEL : /var/www
#   Arch Linux                       : /srv/http
#   SUSE/SLES/openSUSE               : /srv/www
#   Alpine                           : /var/www
#   Slackware                        : /var/www
#   FreeBSD                          : /usr/local/www

detect_webroot() {
    # Check all known web root paths and return whichever exist
    WEBROOTS=""

    # Most common - Debian/Ubuntu/CentOS/Fedora/RHEL/Alpine/Slackware
    if [ -d "/var/www" ]; then
        WEBROOTS="/var/www"
    fi

    # Arch Linux
    if [ -d "/srv/http" ]; then
        WEBROOTS="$WEBROOTS /srv/http"
    fi

    # SUSE/SLES/openSUSE
    if [ -d "/srv/www" ]; then
        WEBROOTS="$WEBROOTS /srv/www"
    fi

    # FreeBSD
    if [ -d "/usr/local/www" ]; then
        WEBROOTS="$WEBROOTS /usr/local/www"
    fi

    # Trim leading space
    WEBROOTS=$(echo "$WEBROOTS" | sed 's/^ //')

    if [ -z "$WEBROOTS" ]; then
        echo -e "\033[33m[!] No web root directory found on this system\033[0m"
    else
        echo -e "\033[32m[+] Detected web root(s): $WEBROOTS\033[0m"
    fi
}

# ---- Backup Function ----
backup_dir() {
    SRC="$1"
    NAME="$2"

    if [ -d "$SRC" ]; then
        echo -e "\033[34m[i] Backing up $SRC ...\033[0m"
        ARCHIVE="$BCK/${NAME}_${TIMESTAMP}"

        # Build exclude flag only if backup dir is inside the source dir
        EXCLUDE_TAR=""
        EXCLUDE_ZIP=""
        EXCLUDE_RSYNC=""
        case "$BCK" in
            "$SRC"|"$SRC"/*)
                EXCLUDE_TAR="--exclude=${BCK#/}"
                EXCLUDE_ZIP="-x ${BCK#/}/*"
                EXCLUDE_RSYNC="--exclude=${BCK#$SRC/}"
                ;;
        esac

        # Try tar.gz first (available everywhere), fall back to zip
        if command -v tar >/dev/null 2>&1; then
            tar czf "${ARCHIVE}.tar.gz" $EXCLUDE_TAR -C / "${SRC#/}" 2>/dev/null
            if [ -s "${ARCHIVE}.tar.gz" ]; then
                echo -e "\033[32m[+] $SRC backed up successfully (tar.gz)\033[0m"
                return 0
            else
                rm -f "${ARCHIVE}.tar.gz"
            fi
            # Try uncompressed tar if gzip failed
            tar cf "${ARCHIVE}.tar" $EXCLUDE_TAR -C / "${SRC#/}" 2>/dev/null
            if [ -s "${ARCHIVE}.tar" ]; then
                echo -e "\033[32m[+] $SRC backed up successfully (tar)\033[0m"
                return 0
            else
                rm -f "${ARCHIVE}.tar"
            fi
        fi

        # Fallback to zip if tar somehow failed
        if command -v zip >/dev/null 2>&1; then
            (cd / && zip -rq "${ARCHIVE}.zip" "${SRC#/}" $EXCLUDE_ZIP 2>/dev/null)
            if [ -s "${ARCHIVE}.zip" ]; then
                echo -e "\033[32m[+] $SRC backed up successfully (zip)\033[0m"
                return 0
            else
                rm -f "${ARCHIVE}.zip"
            fi
        fi

        # Last resort: cp/rsync (exclude backup dir if inside source)
        mkdir -p "$BCK/${NAME}_${TIMESTAMP}"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a $EXCLUDE_RSYNC "$SRC/" "$BCK/${NAME}_${TIMESTAMP}/" 2>/dev/null
        else
            cp -a "$SRC/." "$BCK/${NAME}_${TIMESTAMP}/" 2>/dev/null
        fi
        if [ $? -eq 0 ]; then
            echo -e "\033[32m[+] $SRC backed up successfully (copy)\033[0m"
        else
            echo -e "\033[31m[-] $SRC backup FAILED\033[0m"
        fi
    else
        echo -e "\033[33m[!] $SRC does not exist, skipping\033[0m"
    fi
}

# ---- Run Backups ----

# Standard directories
backup_dir "/etc"  "etc"
backup_dir "/home" "home"
backup_dir "/opt"  "opt"
backup_dir "/root" "root"

# Web root(s) - detect and back up all that exist
detect_webroot
for wr in $WEBROOTS; do
    # Create a safe name from the path (e.g. /var/www -> var_www)
    SAFE_NAME=$(echo "$wr" | sed 's|^/||; s|/|_|g')
    backup_dir "$wr" "$SAFE_NAME"
done

# ---- PAM Backup ----
# PAM libraries live in different paths depending on distro:
#   Debian/Ubuntu  : /lib/x86_64-linux-gnu/security/
#   RHEL/CentOS    : /lib64/security/
#   Arch           : /usr/lib/security/
#   SUSE           : /lib64/security/ or /usr/lib64/security/
#   Alpine         : /lib/security/
#   FreeBSD        : /usr/lib/

echo -e "\033[34m[i] Backing up PAM configuration and libraries...\033[0m"

mkdir -p "$BCK/pam/conf"
mkdir -p "$BCK/pam/pam_libraries"

# Backup PAM config files
if [ -d "/etc/pam.d" ]; then
    cp -R /etc/pam.d/ "$BCK/pam/conf/"
    echo -e "\033[32m[+] PAM config (/etc/pam.d) backed up\033[0m"
else
    echo -e "\033[33m[!] /etc/pam.d not found, skipping PAM config backup\033[0m"
fi

# Backup PAM shared libraries from all known lib paths
# Search across all possible locations for cross-distro compatibility
PAM_SEARCH_PATHS="/lib/ /lib64/ /lib32/ /usr/lib/ /usr/lib64/ /usr/lib32/ /usr/local/lib/"
MOD=$(find $PAM_SEARCH_PATHS -name "pam_unix.so" 2>/dev/null)

if [ -n "$MOD" ]; then
    for m in $MOD; do
        moddir=$(dirname "$m")
        mkdir -p "$BCK/pam/pam_libraries${moddir}"
        cp "$moddir"/pam*.so "$BCK/pam/pam_libraries${moddir}" 2>/dev/null
        echo -e "\033[32m[+] PAM libraries backed up from: $moddir\033[0m"
    done
else
    echo -e "\033[33m[!] No PAM libraries (pam_unix.so) found on this system\033[0m"
fi

# ---- Database Dumps (if available) ----
echo -e "\033[34m[i] Checking for databases to dump...\033[0m"

# MySQL/MariaDB
if command -v mysqldump >/dev/null 2>&1; then
    echo -e "\033[34m[i] Dumping MySQL/MariaDB databases...\033[0m"
    mysqldump -u root --all-databases > "$BCK/mysql_all_${TIMESTAMP}.sql" 2>/dev/null
    if [ $? -eq 0 ] && [ -s "$BCK/mysql_all_${TIMESTAMP}.sql" ]; then
        cd "$BCK" && zip -q "mysql_all_${TIMESTAMP}.zip" "mysql_all_${TIMESTAMP}.sql" 2>/dev/null
        rm -f "$BCK/mysql_all_${TIMESTAMP}.sql"
        chmod 600 "$BCK/mysql_all_${TIMESTAMP}.zip"
        echo -e "\033[32m[+] MySQL dump successful\033[0m"
    else
        echo -e "\033[33m[!] MySQL dump failed (may need credentials)\033[0m"
        rm -f "$BCK/mysql_all_${TIMESTAMP}.sql"
    fi
fi

# PostgreSQL
if command -v pg_dumpall >/dev/null 2>&1; then
    echo -e "\033[34m[i] Dumping PostgreSQL databases...\033[0m"
    su - postgres -c "pg_dumpall" > "$BCK/postgres_all_${TIMESTAMP}.sql" 2>/dev/null
    if [ $? -eq 0 ] && [ -s "$BCK/postgres_all_${TIMESTAMP}.sql" ]; then
        cd "$BCK" && zip -q "postgres_all_${TIMESTAMP}.zip" "postgres_all_${TIMESTAMP}.sql" 2>/dev/null
        rm -f "$BCK/postgres_all_${TIMESTAMP}.sql"
        chmod 600 "$BCK/postgres_all_${TIMESTAMP}.zip"
        echo -e "\033[32m[+] PostgreSQL dump successful\033[0m"
    else
        echo -e "\033[33m[!] PostgreSQL dump failed\033[0m"
        rm -f "$BCK/postgres_all_${TIMESTAMP}.sql"
    fi
fi

# MongoDB
if command -v mongodump >/dev/null 2>&1; then
    echo -e "\033[34m[i] Dumping MongoDB databases...\033[0m"
    mongodump --out "$BCK/mongo_dump_${TIMESTAMP}" 2>/dev/null
    if [ $? -eq 0 ]; then
        # Zip it up for consistency with other backups
        cd "$BCK" && zip -rq "mongo_all_${TIMESTAMP}.zip" "mongo_dump_${TIMESTAMP}" 2>/dev/null
        rm -rf "$BCK/mongo_dump_${TIMESTAMP}"
        chmod 600 "$BCK/mongo_all_${TIMESTAMP}.zip"
        echo -e "\033[32m[+] MongoDB dump successful\033[0m"
    else
        echo -e "\033[33m[!] MongoDB dump failed (may need auth: mongodump --username <user> --password <pass>)\033[0m"
        rm -rf "$BCK/mongo_dump_${TIMESTAMP}"
    fi
fi

# ---- Protect Backups ----
chmod -R 600 "$BCK"/*  2>/dev/null
chmod 700 "$BCK"

echo ""
echo -e "\033[32m[+] Backup complete! Files stored in: $BCK\033[0m"
echo -e "\033[34m[i] Backup contents:\033[0m"
ls -lh "$BCK"/ 2>/dev/null
