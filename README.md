# Laravel Server Setup — DigitalOcean + Ubuntu 24.04

One-script setup for deploying a Laravel on a fresh DigitalOcean droplet. Installs and configures Nginx, PHP, MySQL, Composer, Supervisor, and UFW — then clones your project, sets up `.env`, runs migrations, and gets your APP live.

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

## Step 3: Generate an SSH Key (for GitHub)

Your droplet needs an SSH key to clone private repos from GitHub.

**3a. Generate the key:**

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
```

Press **Enter** through all prompts (default path, no passphrase).

**3b. Copy the public key:**

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the entire output (starts with `ssh-ed25519`).

**3c. Add it to GitHub:**

1. Go to [github.com/settings/keys](https://github.com/settings/keys)
2. Click **New SSH key**
3. **Title**: something like `DigitalOcean - laravel-api`
4. **Key**: paste the public key
5. Click **Add SSH key**

**3d. Test the connection:**

```bash
ssh -T git@github.com
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
3. Clone your Laravel project
4. Install PHP + all required extensions
5. Install Composer + run `composer install`
6. Install MySQL + create database & user
7. Configure `.env` (app key, DB credentials, production mode)
8. Run migrations
9. Configure Nginx with security headers, gzip, proper routing
10. Set up UFW firewall (SSH, HTTP, HTTPS only)
11. Configure Supervisor queue workers
12. Install Node.js 24 LTS
13. Create a `deploy-laravel` helper command

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

### Deploying updates

After pushing code to GitHub, just run:

```bash
deploy-laravel
```

This pulls the latest code, installs dependencies, runs migrations, rebuilds caches, and restarts workers + PHP-FPM.

### Editing environment variables

```bash
nano /var/www/your-app/.env
```

After editing, rebuild the config cache:

```bash
cd /var/www/your-app && php artisan config:cache
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
| **Composer**  | Latest                                       |
| **Node.js**   | 24 LTS                                       |
| **Queue**     | Supervisor (2 workers, auto-restart)         |
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
chown -R www-data:www-data /var/www/your-app/storage /var/www/your-app/bootstrap/cache
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
