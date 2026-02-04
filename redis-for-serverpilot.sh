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

        # SAFETY: Create a timestamped backup
        BAK_FILE="$app_dir/wp-config.php.bak.$(date +%F_%H%M%S)"
        cp "$app_dir/wp-config.php" "$BAK_FILE"

        # CLEANUP: Remove any existing exclusion lines (matches single or multi-line)
        sed -i '/WP_REDIS_IGNORED_GROUPS/,/\] );/d' "$app_dir/wp-config.php"

        # Create the beautifully formatted/commented block in a temp file
        cat << 'EOF' > /tmp/redis_excludes.txt
// Redis Object Cache Exclusions - Updated Feb 2026
define( 'WP_REDIS_IGNORED_GROUPS', [
    'transient',          // Core: Temporary data (MainWP syncs)
    'site-transient',     // Core: Network-wide temporary data
    'wp_cron',            // Core: Scheduled tasks (Gravity Forms emails)
    'counts',             // Core: Comment/Post counts
    'plugins',            // Core: Active plugin list (MainWP updates)
    'themes',             // Core: Active theme list
    'action_scheduler',   // Management: Background tasks (Woo/MainWP)
    'wordfence',          // Security: Wordfence firewall/scans
    'itsec',              // Security: Solid Security settings
    'itsec_lockout',      // Security: Solid Security lockouts
    'limit-login-attempts', // Security: Brute force protection
    'userlogins',         // Security: User session logs
    'session',            // Commerce: User sessions (WooCommerce)
    'wc_session_queries', // Commerce: Database session lookups
    'wc_cache_keys',      // Commerce: WooCommerce internal keys
    'wpforms',            // Forms: WPForms entries/nonces
    'formidable',         // Forms: Formidable entries/logic
    'contact-form-7',     // Forms: CF7 nonces
    'query_monitor',      // Debug: Prevents Redis RAM bloat
    'cloudflare',         // Infra: Cloudflare API & APO
    'wpml',               // Trans: WPML Language mapping
    'site-options',       // Trans: WPML operational settings
    'wp_cache_keys'       // Technical: Internal cache tracking
] );
EOF

        # INJECTION: Use the 'r' (read) command in sed to pull in the file content
        # This places the contents of the file BEFORE the "Happy blogging" line
        sed -i "/\/\* That's all, stop editing! Happy blogging. \*\//e cat /tmp/redis_excludes.txt" "$app_dir/wp-config.php"

        # VERIFICATION: The Safety Check
        if ! php -l "$app_dir/wp-config.php" > /dev/null; then
            echo "----------------------------------------------------------------"
            echo "CRITICAL ERROR: Syntax check failed for $app_dir"
            echo "Restoring backup from $BAK_FILE"
            cp "$BAK_FILE" "$app_dir/wp-config.php"
            echo "----------------------------------------------------------------"
            continue 
        else
            # Only delete the backup if the syntax check passes
            rm -f "$BAK_FILE"
        fi
        
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
