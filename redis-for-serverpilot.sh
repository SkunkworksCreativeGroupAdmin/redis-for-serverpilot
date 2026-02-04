#!/bin/bash

# 1. Install System Dependencies & Redis Server
export DEBIAN_FRONTEND=noninteractive && \
sudo apt-get update && \
sudo apt-get -y install gcc g++ make autoconf libc-dev pkg-config redis-server && \
\

# 2. DYNAMICALLY loop through all installed PHP versions
echo "Scanning for installed PHP versions..."
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
shopt -u nullglob

# 3. Find every WordPress App and activate Redis
echo "Searching for WordPress apps to enable Redis..."
for app_dir in /srv/users/serverpilot/apps/*/public; do
    if [ -f "$app_dir/wp-config.php" ]; then
        echo "Processing $app_dir..."

        # SAFETY: Create a timestamped backup
        BAK_FILE="$app_dir/wp-config.php.bak.$(date +%F_%H%M%S)"
        cp "$app_dir/wp-config.php" "$BAK_FILE"

        # CLEANUP: Remove any existing exclusion lines (Robust match)
        # This prevents duplicate blocks if the script is run multiple times
        sed -i '/\/\/ Redis Object Cache Exclusions/,/\] );/d' "$app_dir/wp-config.php"

        # Create the formatted exclusion block in a temp file
        cat << 'EOF' > /tmp/redis_excludes.txt
// Redis Object Cache Exclusions - Updated Feb 2026
define( 'WP_REDIS_IGNORED_GROUPS', [
    // Core & Authentication: Ensuring logins and updates are real-time
    'transient',          // Core: Temporary data (MainWP syncs)
    'site-transient',     // Core: Network-wide temporary data
    'site-options',       // Core/WPML: Site options and operational settings
    'wp_cron',            // Core: Scheduled tasks (Gravity Forms emails)
    'counts',             // Core: Comment/Post counts
    'plugins',            // Core: Active plugin list (MainWP updates)
    'themes',             // Core: Active theme list
    'user_meta',          // Core: User authentication data
    'users',              // Core: User authentication data

    // Management & Security: Preventing bypasses and sync lags
    'action_scheduler',   // Management: Background tasks (Woo/MainWP)
    'wordfence',          // Security: Wordfence firewall/scans
    'itsec',              // Security: Solid Security settings
    'itsec_lockout',      // Security: Solid Security lockouts
    'itsec-storage',      // Security: Solid Security Brute Force logs
    'limit-login-attempts', // Security: Brute force protection
    'userlogins',         // Security: User session logs

    // Commerce & Sessions: Preventing "stuck" carts and session data
    'session',            // Commerce: User sessions (WooCommerce)
    'wc_session_queries', // Commerce: Database session lookups
    'wc_cache_keys',      // Commerce: WooCommerce internal keys

    // Forms: Ensuring nonces and entries are never stale
    'wpforms',            // Forms: WPForms entries/nonces
    'formidable',         // Forms: Formidable entries/logic
    'contact-form-7',     // Forms: CF7 nonces
    'gravityforms',       // Forms: Gravity Forms nonces
    'gf_entries',         // Forms: Gravity Forms entry data

    // Infrastructure & Technical
    'query_monitor',      // Debug: Prevents Redis RAM bloat during dev
    'cloudflare',         // Infra: Cloudflare API & APO settings
    'wpml',               // Trans: WPML Language mapping
    'wp_cache_keys'       // Technical: Internal Redis cache tracking
] );
EOF

        # INJECTION: Use the 'e cat' command to pull in the file content
        # This places the contents BEFORE the "Happy blogging" line
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
            rm -f "$BAK_FILE"
        fi
        
        # Ensure ownership is correct
        chown serverpilot:serverpilot "$app_dir/wp-config.php"
        echo "Applied latest Redis group exclusions to wp-config.php."

        # NEW: Create Standalone Health Check File
        cat << 'EOF' > "$app_dir/redis-status.php"
<?php
/**
 * Redis Health Check Dashboard
 * Provides a visual status for humans and a "PONG" string for StatusCake.
 * Written for Skunkworks by Gemini 2.0.
 */

// --- Explicit No-Cache Headers ---
// These headers instruct browsers and proxies not to cache this page.
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");
header("Expires: Sat, 26 Jul 1997 05:00:00 GMT"); // A date in the past

// --- Configuration & Domain Logic ---
$fullHostname = $_SERVER['HTTP_HOST'] ?? 'localhost';
$portPos = strpos($fullHostname, ':');
if ($portPos !== false) { $fullHostname = substr($fullHostname, 0, $portPos); }

// --- Redis Connection Logic ---
$redisStatus = 'UNKNOWN';
$messageType = 'info';
$statusMessage = 'Initializing check...';
$debugInfo = '';

if (!class_exists('Redis')) {
    $redisStatus = 'MISSING_EXTENSION';
    $messageType = 'error';
    $statusMessage = 'The PHP Redis extension is not installed on this server.';
} else {
    $redis = new Redis();
    try {
        // 0.5s timeout to keep the page snappy
        if (@$redis->connect('127.0.0.1', 6379, 0.5)) {
            $ping = $redis->ping();
            if ($ping == '+PONG' || $ping === true) {
                $redisStatus = 'RUNNING';
                $messageType = 'success';
                $statusMessage = 'Redis is active and responding to commands.';
            } else {
                $redisStatus = 'INVALID_RESPONSE';
                $messageType = 'warning';
                $statusMessage = 'Redis connected but returned an unexpected response.';
            }
        } else {
            $redisStatus = 'CONNECTION_FAILED';
            $messageType = 'error';
            $statusMessage = 'Could not connect to Redis at 127.0.0.1:6379.';
        }
    } catch (Exception $e) {
        $redisStatus = 'CRITICAL_ERROR';
        $messageType = 'error';
        $statusMessage = 'A PHP exception occurred: ' . $e->getMessage();
    }
}

$formattedTimestamp = date('Y-m-d H:i:s T');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Redis Status: <?php echo htmlspecialchars($fullHostname); ?></title>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>
        body { font-family: 'Inter', sans-serif; background-color: #f0f4f8; }
        .container { max-width: 600px; margin: 4rem auto; padding: 2rem; background: #fff; box-shadow: 0 10px 15px -3px rgba(0,0,0,0.1); border-radius: 1rem; }
        .status-blob { font-family: monospace; padding: 1rem; border-radius: 0.5rem; background: #1a202c; color: #4fd1c5; text-align: center; font-size: 1.5rem; font-weight: bold; }
        .message-box.success { background-color: #f0fdf4; color: #166534; border: 1px solid #bbf7d0; }
        .message-box.error { background-color: #fef2f2; color: #991b1b; border: 1px solid #fecaca; }
        .message-box.warning { background-color: #fffbeb; color: #92400e; border: 1px solid #fde68a; }
    </style>
</head>
<body class="p-4">
    <div class="container">
        <h1 class="text-2xl font-bold text-center text-gray-800 mb-2">Redis Health Check</h1>
        <p class="text-center text-gray-500 mb-8"><?php echo htmlspecialchars($fullHostname); ?></p>

        <div class="status-blob mb-6">
            <?php echo $redisStatus; ?>
        </div>

        <div class="message-box <?php echo $messageType; ?> p-4 rounded-lg text-center mb-6">
            <?php echo htmlspecialchars($statusMessage); ?>
        </div>

        <p class="text-xs text-center text-gray-400">
            Last Checked: <?php echo $formattedTimestamp; ?>
        </p>
    </div>

    <footer class="text-center text-gray-500 text-xs mt-8">
        This status page is monitored by <a href="https://statuscake.com/" target="_blank" class="text-indigo-600 font-semibold">StatusCake</a> for any <a href="https://www.statuscake.com/kb/knowledge-base/how-does-content-match-work/" target="_blank" class="text-indigo-600 font-semibold">changes</a>.<br>
    </footer>
</body>
</html>
EOF
        chown serverpilot:serverpilot "$app_dir/redis-status.php"
        echo "Created external health check at /redis-status.php"

        # Plugin Installation and Activation
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
