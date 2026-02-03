# 1. Install System Dependencies & Redis Server
export DEBIAN_FRONTEND=noninteractive && \
sudo apt-get update && \
sudo apt-get -y install gcc g++ make autoconf libc-dev pkg-config redis-server && \
\

# 2. DYNAMICALLY loop through all installed PHP versions
echo "Scanning for installed PHP versions..."
# nullglob prevents the script from breaking if no php-sp folders exist
shopt -s nullglob 
for php_dir in /etc/php*-sp; do
    if [ -d "$php_dir" ]; then
        # Extracts '8.4' from '/etc/php8.4-sp'
        ver=$(basename "$php_dir" | sed 's/php//;s/-sp//')
        echo "Processing PHP $ver..."
        
        # Install via PECL. Using '|| true' ensures the script continues if already installed.
        (yes '' | sudo pecl${ver}-sp install -q redis || true) && \
        sudo bash -c "echo extension=redis.so > /etc/php${ver}-sp/conf.d/redis.ini" && \
        sudo service php${ver}-fpm-sp restart && \
        echo "PHP $ver Redis extension is ready."
    fi
done
shopt -u nullglob # Turn off nullglob to keep environment clean

# 3. Find every WordPress App and activate Redis
echo "Searching for WordPress apps to enable Redis..."
for app_dir in /srv/users/serverpilot/apps/*/public; do
    if [ -f "$app_dir/wp-config.php" ]; then
        echo "Processing $app_dir..."

        # Define exclusions to prevent MainWP/Gravity Forms lag
        REDIS_EXCLUDES="define( 'WP_REDIS_IGNORED_GROUPS', [ 'transient', 'site-transient', 'wp_cron', 'counts', 'wordfence', 'action_scheduler', 'query_monitor', 'itsec', 'itsec_lockout', 'session', 'wc_session_queries', 'wp_cache_keys', 'plugins' ] );"
        
        # CLEANUP: Remove any existing exclusion line so we don't get duplicates
        # This allows you to update the list and re-run the script safely.
        sed -i "/WP_REDIS_IGNORED_GROUPS/d" "$app_dir/wp-config.php"

        # Inject the new constant above the happy blogging line
        sed -i "/\/\* That's all, stop editing! Happy blogging. \*\//i $REDIS_EXCLUDES" "$app_dir/wp-config.php"
        
        # Ensure ownership is correct
        chown serverpilot:serverpilot "$app_dir/wp-config.php"
        echo "Applied latest Redis group exclusions to wp-config.php."

        # Check if plugin is already installed to save time and API pings
        # Running as serverpilot ensures WP-CLI creates files with the right owner
        if ! sudo -u serverpilot -i -- wp --path="$app_dir" plugin is-installed redis-cache; then
             echo "Installing Redis Plugin in $app_dir..."
             sudo -u serverpilot -i -- wp --path="$app_dir" plugin install redis-cache --activate
        fi
        sudo -u serverpilot -i -- wp --path="$app_dir" redis enable
        echo "Redis enabled for $(basename $(dirname "$app_dir"))."
    fi
done && \
\
# 4. System-Wide Flush
if command -v redis-cli > /dev/null; then
    echo "Flushing Redis cache..."
    redis-cli flushall
fi && \
\
echo "SUCCESS: Server, Extensions, and all WP Apps are now using Redis."
