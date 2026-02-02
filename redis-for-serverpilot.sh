# 1. Install System Dependencies & Redis Server
export DEBIAN_FRONTEND=noninteractive && \
sudo apt-get update && \
sudo apt-get -y install gcc g++ make autoconf libc-dev pkg-config redis-server && \
\
# 2. Loop through PHP versions to install/enable Redis extension
for ver in 8.4 8.3 8.2 8.1 8.0 7.4 7.3 7.2; do \
    if [ -d "/etc/php${ver}-sp" ]; then \
        echo "Processing PHP $ver..." && \
        yes '' | sudo pecl${ver}-sp install redis && \
        sudo bash -c "echo extension=redis.so > /etc/php${ver}-sp/conf.d/redis.ini" && \
        sudo service php${ver}-fpm-sp restart && \
        echo "PHP $ver Redis extension is ready."; \
    fi \
done && \
\
# 3. Find every WordPress App and activate the Redis Plugin via WP-CLI
echo "Searching for WordPress apps to enable Redis..." && \
for app_dir in /srv/users/*/apps/*/public; do \
    if [ -f "$app_dir/wp-config.php" ]; then \
        echo "Installing Redis Plugin in $app_dir..." && \
        # Determine the system user who owns the app to run wp-cli safely
        app_user=$(stat -c '%U' "$app_dir") && \
        sudo -u "$app_user" -i -- wp --path="$app_dir" plugin install redis-cache --activate && \
        sudo -u "$app_user" -i -- wp --path="$app_dir" redis enable && \
        echo "Redis enabled for $(basename $(dirname "$app_dir"))."; \
    fi \
done && \
echo "SUCCESS: Server, Extensions, and all WP Apps are now using Redis."
