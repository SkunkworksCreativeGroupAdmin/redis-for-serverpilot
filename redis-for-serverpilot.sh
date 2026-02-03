# 1. Install System Dependencies & Redis Server
export DEBIAN_FRONTEND=noninteractive && \
sudo apt-get update && \
sudo apt-get -y install gcc g++ make autoconf libc-dev pkg-config redis-server && \
\
# 2. Loop through PHP versions
for ver in 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2; do \
    if [ -d "/etc/php${ver}-sp" ]; then \
        echo "Processing PHP $ver..." && \
        (yes '' | sudo pecl${ver}-sp install redis || echo "Redis already installed for $ver") && \
        sudo bash -c "echo extension=redis.so > /etc/php${ver}-sp/conf.d/redis.ini" && \
        sudo service php${ver}-fpm-sp restart && \
        echo "PHP $ver Redis extension is ready."; \
    fi \
done && \
\
# 3. Find every WordPress App and activate Redis
echo "Searching for WordPress apps to enable Redis..."
for app_dir in /srv/users/serverpilot/apps/*/public; do
    if [ -f "$app_dir/wp-config.php" ]; then
        echo "Processing $app_dir..."

        # Define exclusions to prevent MainWP/Gravity Forms lag
        REDIS_EXCLUDES="define( 'WP_REDIS_IGNORED_GROUPS', [ 'transient', 'site-transient', 'wp_cron', 'counts', 'wordfence', 'action_scheduler', 'query_monitor', 'itsec', 'itsec_lockout', 'session', 'wc_session_queries', 'wp_cache_keys', 'plugins' ] );"
        
        if ! grep -q "WP_REDIS_IGNORED_GROUPS" "$app_dir/wp-config.php"; then
            # Inject the constant above the happy blogging line
            sed -i "/\/\* That's all, stop editing! Happy blogging. \*\//i $REDIS_EXCLUDES" "$app_dir/wp-config.php"
            
            # CRITICAL: Revert ownership back to serverpilot so the site stays live
            chown serverpilot:serverpilot "$app_dir/wp-config.php"
            echo "Added group exclusions to wp-config.php."
        fi

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
