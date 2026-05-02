# 🚀 ERPNext v16 Docker Deployment

> A complete, copy‑paste guide for deploying **ERPNext v16** with custom apps using Docker Compose. Written for **fish shell** and **Zed editor** (works equally well in **bash**).

> [!NOTE] 
> **How to read this guide:** Pick your shell, copy each block, and run it in order. All commands assume you are inside the `frappe_docker` repository directory. We keep everything localized here.

---

## ⚠️ Critical Concept: Docker Immutability

> [!WARNING]
> **Apps must be baked into the image at build time. You cannot install apps into a running container.**

*   App code lives **inside the Docker image** — not the container file-system.
*   Site data (database, uploaded files) lives in **Docker volumes** -> this is the only persistent part.
*   `bench get-app` inside a running container is **not supported** in production.
*   Changes made inside a container are **lost on recreation**.

**The correct workflow is always:**  
`Add app to apps.json` ➔ `Rebuild Image` ➔ `Redeploy Stack` ➔ `Run Migrations`

---

## 🛠️ 1. Prerequisites & Setup

Ensure your host machine (Ubuntu/Debian) is ready.

```bash
# Install Git
sudo apt update && sudo apt install git -y

# Install Docker (convenience script)
curl -fsSL https://get.docker.com | bash

# Add user to docker group (Log out and back in after running this)
sudo usermod -aG docker $USER
newgrp docker

# Check if its install properly
docker --version
docker compose version
```

Clone the repository and enter the directory:
```bash
git clone https://github.com/frappe/frappe_docker
cd frappe_docker
```

---

## 📦 2. Define Custom Apps

Create the `apps.json` file in the repository root. This tells the Docker build process which apps to bake into your image.

```bash
zed apps.json
```

Paste the following JSON:
```json[
  {
    "url": "https://github.com/frappe/erpnext",
    "branch": "version-16"
  },
  {
    "url": "https://github.com/resilient-tech/india-compliance",
    "branch": "version-16"
  },
  {
    "url": "https://github.com/frappe/ecommerce_integrations",
    "branch": "version-16"
  },
  {
    "url": "https://github.com/frappe/print_designer",
    "branch": "main"
  }
]
```

*(Save and close. We will pass this file as a secure secret during the build).*

---

## 🐳 3. Build Your Custom Image

We build using the `layered` approach, which caches Frappe layers from Docker Hub for significantly faster subsequent builds.

```bash
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --secret=id=apps_json,src=apps.json \
  --tag=riyann00b/erpnext:16.14.0 \
  --file=images/layered/Containerfile .
```

*(First build takes 5‑30 minutes. Future builds take only a few minutes).*

---

## ⚙️ 4. Configure Environment Variables

```bash
cp example.env .env
zed .env
```

Set **at minimum** these values:
```dotenv
# ── Image Config ───────────────────────────────────────────────────────────
CUSTOM_IMAGE=riyann00b/erpnext
CUSTOM_TAG=16.14.0
PULL_POLICY=missing

# ── Database Config ────────────────────────────────────────────────────────
DB_PASSWORD=admin
ROUTER=frappe

# ── ERPNext Version ────────────────────────────────────────────────────────
ERPNEXT_VERSION=v16.14.0
FRAPPE_BRANCH=version-16

# ── Networking (Required for Scenario A) ───────────────────────────────────
FRAPPE_SITE_NAME_HEADER=frontend
```

---
## 🌐 5. Generate Deployment Configuration

Pick **ONE** deployment scenario below. Run the command to generate `erpnext.yaml`.

### Scenario A — No Proxy (Local / LAN) 🌟 *Default*

Exposes ERPNext directly on port **8080**.

```bash
docker compose --project-name erpnext \
  --env-file .env \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.noproxy.yaml \
  config > erpnext.yaml
```

### Scenario B — HTTPS with Traefik (Production)
```bash
# First, append domain rules to .env:
echo "LETSENCRYPT_EMAIL=admin@your-domain.com" >> .env
echo "SITES_RULE=Host(\`frontend\`)" >> .env

# Generate config:
docker compose --project-name erpnext \
  --env-file .env \
  -f compose.yaml \
  -f overrides/compose.mariadb.yaml \
  -f overrides/compose.redis.yaml \
  -f overrides/compose.https.yaml \
  config > erpnext.yaml
```

<details>
<summary><b>View Scenario C (nginx-proxy) and D (Caddy)</b></summary>

**Scenario C — nginx-proxy + acme-companion**

```bash
echo "NGINX_PROXY_HOSTS=frontend,crm.your-domain.com" >> .env
echo "LETSENCRYPT_EMAIL=admin@your-domain.com" >> .env

docker compose --project-name erpnext --env-file .env \
  -f compose.yaml -f overrides/compose.mariadb.yaml -f overrides/compose.redis.yaml \
  -f overrides/compose.nginxproxy.yaml -f overrides/compose.nginxproxy-ssl.yaml \
  config > erpnext.yaml
```

**Scenario D — Local Caddy (HTTPS via self-signed LAN)**
1. Generate Scenario A config (`erpnext.yaml`).
2. Install Caddy on host: `sudo apt install caddy`
3. Edit `/etc/caddy/Caddyfile`:

```caddy
erp.localdev.net {
  tls internal
  reverse_proxy localhost:8080
}
```
4. Add to hosts: `echo "127.0.0.1 erp.localdev.net" | sudo tee -a /etc/hosts`
5. Start Caddy: `caddy trust && sudo systemctl reload caddy`
</details>

---

## 🚀 6. Start Containers & Install Site

Start the infrastructure:
```bash
docker compose --project-name erpnext -f erpnext.yaml up -d
```
> Wait ~10 seconds for the `configurator` container to finish initializing the database.

**Create the site and install apps in one command:**
```bash
docker compose --project-name erpnext exec backend bench new-site frontend \
  --mariadb-user-host-login-scope='%' \
  --db-root-password admin \
  --admin-password admin \
  --install-app erpnext \
  --install-app india_compliance \
  --install-app ecommerce_integrations \
  --install-app print_designer \
  --set-default \
  --force
```

**Finalize installation (Migrate, Build, Restart):**
```bash
docker compose --project-name erpnext exec backend bench --site frontend migrate
```

🎉 **Access ERPNext:** `http://localhost:8080` (or your domain/IP).  

**Login:** 
```bash
Administrator #user
```

```bash
admin #password
```

---

## 💾 7. Backups & Restores

### Automated Daily Backups

Create the backup script:

```bash
zed auto_backup.sh
```

Paste this script:

```bash
#!/bin/bash
cd "$(dirname "$0")" # Ensure we run in frappe_docker directory

HOST_BACKUP_DIR="./backups"
CONTAINER="erpnext-backend-1"
SITE="frontend"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
TARGET_DIR="$HOST_BACKUP_DIR/$TIMESTAMP"
LOG_FILE="./backup.log"

echo "[$TIMESTAMP] Starting backup..." >> $LOG_FILE
docker exec $CONTAINER bench --site $SITE backup --with-files >> $LOG_FILE 2>&1 || exit 1

mkdir -p "$TARGET_DIR"
docker cp $CONTAINER:/home/frappe/frappe-bench/sites/$SITE/private/backups/. "$TARGET_DIR/" >> $LOG_FILE 2>&1

# Retain only last 7 days of backups
find "$HOST_BACKUP_DIR" -maxdepth 1 -type d -mtime +7 -exec rm -rf {} + >> $LOG_FILE 2>&1
echo "[$TIMESTAMP] Done." >> $LOG_FILE
```

Make it executable and add to cron:
```bash
chmod +x ./auto_backup.sh

# Run `pwd` to get your exact path, e.g., /home/user/frappe_docker
pwd 

crontab -e
```

```bash
# Add this line (replace /PATH/TO with your actual output from `pwd`):
0 1,10,12,17,20,23 * * * /PATH/TO/frappe_docker/auto_backup.sh
```

### Restore a Backup

Place your `.sql.gz` and `.tar` files in the directory, then run:

```bash
docker cp database.sql.gz erpnext-backend-1:/home/frappe/frappe-bench/sites/
docker cp public_files.tar erpnext-backend-1:/home/frappe/frappe-bench/sites/
docker cp private_files.tar erpnext-backend-1:/home/frappe/frappe-bench/sites/
```

```bash
docker compose --project-name erpnext exec backend bench --site frontend restore \
  /home/frappe/frappe-bench/sites/database.sql.gz \
  --with-public-files /home/frappe/frappe-bench/sites/public_files.tar \
  --with-private-files /home/frappe/frappe-bench/sites/private_files.tar \
  --force
```

```
docker compose --project-name erpnext exec backend bench --site frontend migrate
```

---

## 🔄 8. Updating ERPNext (The Docker Way)

When you need to pull latest updates for Frappe, ERPNext, or Custom Apps:

```bash
# 1. Rebuild the image (using the same --secret)
docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --secret=id=apps_json,src=apps.json \
  --tag=riyann00b/erpnext:16.16.0 \ #Update to latest tag
  --file=images/layered/Containerfile .
```

```bash
# 2. Update environment variables in .env
zed .env

# Edit ERPNEXT_VERSION and FRAPPE_VERSION as needed
```

```bash
# ── Image ──────────────────────────────────────────────────────────────────
CUSTOM_TAG=16.14.0 #change this to the new version
```

```bash
# 3. Regenerate compose file with new versions
docker compose --env-file .env \
    -f compose.yaml \
    -f overrides/compose.mariadb.yaml \
    -f overrides/compose.redis.yaml \
    -f overrides/compose.noproxy.yaml \
    config > erpnext.yaml
```

```bash
# 4. Pull new images
docker compose --project-name erpnext -f erpnext.yaml pull
```

```bash
# 5. Stop containers
docker compose --project-name erpnext -f erpnext.yaml down
```

```bash
# 6. Restart containers
docker compose --project-name erpnext -f erpnext.yaml up -d
```


---

## 🔒 9. Version Control (GitOps)

Once everything is up, running, and tested, copy your configuration files to a local `gitops` folder strictly for safe keeping and version control.

```bash
mkdir -p gitops
cp .env gitops/
cp erpnext.yaml gitops/
cp apps.json gitops/
```
> [!TIP]
> Initialize a git repository inside the `gitops` folder and push it to GitHub/GitLab. Commit after every configuration change or version update to keep a perfect audit trail of your infrastructure.

---

## 📚 Appendix: Cheat Sheet & Troubleshooting

<details>
<summary><b>🛠️ Useful Commands</b></summary>

| Action | Command |
| :--- | :--- |
| **Stop** | `docker compose -p erpnext -f erpnext.yaml down` |
| **Logs** | `docker compose -p erpnext -f erpnext.yaml logs -f` |
| **Shell (Frappe)** | `docker compose -p erpnext exec backend bash` |
| **Shell (Root)** | `docker exec -u 0 -it erpnext-backend-1 bash` |
| **List Apps** | `docker compose -p erpnext exec backend bench --site frontend list-apps` |
| **Uninstall App** | `docker compose -p erpnext exec backend bench --site frontend uninstall-app app_name --force` |
| **Clean Docker** | `docker system prune -a --volumes` *(Warning: Deletes unused data)* |

</details>

<details>
<summary><b>🖨️ Print Designer Troubleshooting</b></summary>

If PDF generation produces blank output, the image lacks Chromium.

**1. Update `Containerfile`:**
Edit `images/layered/Containerfile` and add this line after the WeasyPrint section:
```dockerfile
RUN apt-get update && apt-get install -y chromium && apt-get clean
```

**2. Update `common_site_config.json`:**
```bash
docker exec -u 0 -it erpnext-backend-1 bash
cd /home/frappe/frappe-bench/sites
vi common_site_config.json
# Add: "chromium_binary_path": "/usr/bin/chromium"
```

**3. Rebuild and Reinstall:**
Follow the update steps to rebuild the image, then:
```bash
docker compose -p erpnext exec backend bench --site frontend uninstall-app print_designer --force
docker compose -p erpnext exec backend bench --site frontend install-app print_designer
```
</details>

<details>
<summary><b>🗄️ MariaDB "Access Denied" After Rebuild</b></summary>

If the container recreates and loses MariaDB permissions:
```bash
docker compose -p erpnext exec db mysql -uroot -padmin
```
```sql
SELECT User, Host FROM mysql.user;
DROP USER 'db_name'@'old_host';
UPDATE mysql.global_priv SET Host = '%' WHERE User = 'db_name';
FLUSH PRIVILEGES;
SET PASSWORD FOR 'db_name'@'%' = PASSWORD('db_password');
GRANT ALL PRIVILEGES ON `db_name`.* TO 'db_name'@'%' IDENTIFIED BY 'db_password' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EXIT;
```
</details>

<details>
<summary><b>🏢 Multi-Bench Single Server Setup</b></summary>

If you need multiple isolated ERPNext instances sharing Traefik and MariaDB:
```bash
# 1. Shared Networks
docker network create traefik-public
docker network create mariadb-network

# 2. Shared MariaDB
echo "DB_PASSWORD=admin" > mariadb.env
docker compose -p mariadb --env-file mariadb.env -f overrides/compose.mariadb-shared.yaml up -d

# 3. Deploy Bench One
cp example.env bench-one.env
# Edit bench-one.env: DB_HOST=mariadb-database, DB_PORT=3306, BENCH_NETWORK=bench-one
docker compose -p bench-one --env-file bench-one.env -f compose.yaml -f overrides/compose.redis.yaml -f overrides/compose.multi-bench.yaml config > bench-one.yaml
docker compose -p bench-one -f bench-one.yaml up -d
```
</details>

