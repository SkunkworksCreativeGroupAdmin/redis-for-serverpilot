# Redis for ServerPilot
Installs and configures Redis Object Caching for ServerPilot servers and all Apps running on them.

Assumes the username for all Apps is "serverpilot"

Installs and activates required Wordpress plugin as well.

Basically an automated combination of the manual steps detailed at:
1. https://serverpilot.io/docs/guides/servers/packages/redis/
2. https://serverpilot.io/docs/guides/php/extensions/redis/
3. https://serverpilot.io/docs/guides/apps/wordpress/plugins/redis/

This script is run remotely via Shuttle App with the command
````json
{
  "name": "Server - Connect and install Redis",
  "cmd": "ssh -t root@XXXXXXXXX 'wget https://raw.githubusercontent.com/SkunkworksCreativeGroupAdmin/redis-for-serverpilot/refs/heads/main/redis-for-serverpilot.sh -O setup.sh && bash setup.sh && rm setup.sh'",
  "inTerminal": "new"
},
````
