# Laravel API Server Setup — DigitalOcean + Ubuntu 24.04

One-script setup for deploying a Laravel API on a fresh DigitalOcean droplet. Installs and configures Nginx, PHP, MySQL, Composer, Supervisor, and UFW — then clones your project, sets up `.env`, runs migrations, and gets your API live.

The script creates a dedicated `deploy` user for application tasks (git, composer, artisan) so nothing runs as root unnecessarily.

---

## Prerequisites

- A [DigitalOcean](https://www.digitalocean.com/) account
- A Laravel project hosted on GitHub (private or public)
- A domain name pointed to your droplet's IP (optional but recommended for SSL)

---

## Step 1: Create a Droplet

1. Log in to DigitalOcean → click **Create** → **Droplets**
2. **Region** — pick the closest to your users (e.g. Singapore, Bangalore)
3. **Image** — Ubuntu **24.04 LTS**
4. **Size** — Basic, Regular SSD:
   - **$6/mo** (1 vCPU, 1 GB RAM) — development / low traffic
   - **$12/mo** (1 vCPU, 2 GB RAM) — recommended for production
5. **Authentication** — SSH Key (recommended) or Password
6. **Hostname** — give it a name (e.g. `laravel-api`)
7. Check **Monitoring** and **IPv6** (both free)
8. Click **Create Droplet** and wait for the IP address

---

## Step 2: SSH Into Your Droplet

```bash
ssh root@YOUR_DROPLET_IP
```

---

## Step 3: Create the Deploy User & SSH Key (for GitHub)

The script will create a `deploy` user automatically, but the SSH key for GitHub needs to be set up **before** running the script so it can clone your repo.

**3a. Create the deploy user:**

```bash
adduser --disabled-password --gecos "" deploy
```

**3b. Generate an SSH key for the deploy user:**

```bash
sudo -u deploy ssh-keygen -t ed25519 -C "your-email@example.com"
```

Press **Enter** through all prompts (default path, no passphrase).

**3c. Copy the public key:**

```bash
cat /home/deploy/.ssh/id_ed25519.pub
```

Copy the entire output (starts with `ssh-ed25519`).

**3d. Add it to GitHub:**

1. Go to [github.com/settings/keys](https://github.com/settings/keys)
2. Click **New SSH key**
3. **Title**: something like `DigitalOcean - laravel-api`
4. **Key**: paste the public key
5. Click **Add SSH key**

**3e. Test the connection:**

```bash
sudo -u deploy ssh -T git@github.com
```

You should see: `Hi <username>! You've successfully authenticated...`

---

## Step 4: Configure & Upload the Script

Clone this repo or download `laravel-server-setup.sh`. You can edit the config **before** copying it to your droplet, or edit it **on the droplet** after copying — whichever you prefer.

**Option A: Edit locally first, then copy**

Open the file on your local machine and update the configuration block at the top, then copy it to your droplet:

```bash
scp laravel-server-setup.sh root@YOUR_DROPLET_IP:~/
```

**Option B: Copy first, then edit on the droplet**

```bash
scp laravel-server-setup.sh root@YOUR_DROPLET_IP:~/
ssh root@YOUR_DROPLET_IP
nano laravel-server-setup.sh
```

Either way, update these values:

```bash
APP_DOMAIN="your-domain.com"           # Your domain or droplet IP
APP_DIR="/var/www/your-app"            # Where to install the app
DB_NAME="your_db"                      # MySQL database name
DB_USER="your_user"                    # MySQL username
DB_PASS="your_strong_password"         # MySQL password
PHP_VERSION="8.4"                      # PHP version
DEPLOY_USER="deploy"                   # Non-root user (default is fine)
GIT_REPO=""                            # Repo URL — leave empty to enter during setup
```

> **Tip:** If you set `GIT_REPO=""`, the script will prompt you for the URL when it runs. Use the SSH format: `git@github.com:username/repo.git`

---

## Step 5: Run the Script

```bash
chmod +x laravel-server-setup.sh
./laravel-server-setup.sh
```

The script will:

1. Update system packages
2. Install Git, Supervisor, utilities
3. Create `deploy` user (skips if already created in Step 3)
4. Clone your Laravel project as the deploy user
5. Install PHP + all required extensions
6. Install Composer + run `composer install` as the deploy user
7. Install MySQL + create database & user
8. Configure `.env` (app key, DB credentials, production mode)
9. Run migrations as the deploy user
10. Configure Nginx with security headers, gzip, proper routing
11. Set up UFW firewall (SSH, HTTP, HTTPS only)
12. Configure Supervisor queue workers (run as deploy user)
13. Install Node.js 24 LTS
14. Create a `deploy-laravel` helper command

---

## Step 6: Add SSL (HTTPS)

Make sure your domain's DNS A record points to the droplet IP, then:

```bash
apt install certbot python3-certbot-nginx
certbot --nginx -d your-domain.com
```

Certbot will auto-renew via a systemd timer.

---

## After Setup

### User roles

| User | Used for |
|------|----------|
| `root` | System admin — installing packages, Nginx config, firewall, SSL, running `deploy-laravel` |
| `deploy` | App tasks — git pull, composer, artisan, owns all app files |

You can SSH in as either user:

```bash
ssh root@YOUR_IP        # system admin
ssh deploy@YOUR_IP      # app tasks
```

### Deploying updates

After pushing code to GitHub, run as root:

```bash
deploy-laravel
```

This pulls the latest code, installs dependencies, runs migrations, rebuilds caches, and restarts workers + PHP-FPM — all app commands run as the `deploy` user automatically.

### Editing environment variables

```bash
nano /var/www/your-app/.env
```

After editing, rebuild the config cache:

```bash
cd /var/www/your-app && sudo -u deploy php artisan config:cache
```

### Checking logs

```bash
# Laravel logs
tail -f /var/www/your-app/storage/logs/laravel.log

# Nginx logs
tail -f /var/log/nginx/laravel-error.log

# Queue worker logs
tail -f /var/www/your-app/storage/logs/worker.log
```

### Restarting services

```bash
systemctl restart nginx
systemctl restart php8.4-fpm
supervisorctl restart laravel-worker:*
```

---

## What's Installed

| Component     | Details                                      |
|---------------|----------------------------------------------|
| **OS**        | Ubuntu 24.04 LTS                             |
| **Web Server**| Nginx (gzip, security headers, Laravel routing) |
| **PHP**       | 8.4 FPM + OPcache, mysql, redis, gd, intl, etc. |
| **Database**  | MySQL 8 (utf8mb4)                            |
| **Composer**  | Latest (runs as `deploy` user)               |
| **Node.js**   | 24 LTS                                       |
| **Queue**     | Supervisor (2 workers, auto-restart, runs as `deploy`) |
| **Firewall**  | UFW (SSH + HTTP + HTTPS only)                |

---

## Troubleshooting

**502 Bad Gateway** — PHP-FPM isn't running or socket path is wrong:
```bash
systemctl status php8.4-fpm
# check the socket exists:
ls /var/run/php/php8.4-fpm.sock
```

**Permission denied on storage/** — fix ownership:
```bash
chown -R deploy:www-data /var/www/your-app/storage /var/www/your-app/bootstrap/cache
chmod -R 775 /var/www/your-app/storage /var/www/your-app/bootstrap/cache
```

**Queue workers not running:**
```bash
supervisorctl status
# restart them:
supervisorctl restart laravel-worker:*
```

**MySQL connection refused** — check credentials in `.env` match what the script set up, and verify MySQL is running:
```bash
systemctl status mysql
```

---

## License

MIT — use it however you want.
