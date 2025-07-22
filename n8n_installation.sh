#!/bin/bash

# --- Variables ---
N8N_DOMAIN="n8nserver.leadchoose.com" # Your n8n domain
YOUR_EMAIL="aiagency0001@gmail.com"    # Your email for Let's Encrypt

# --- Helper Functions ---
log_info() {
    echo "INFO: $1"
}

log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# --- 1. Check for Docker and Docker Compose ---
log_info "Checking for Docker installation..."
if ! command -v docker &> /dev/null; then
    log_info "Docker not found. Installing Docker..."
    # Update and install Docker (assuming Amazon Linux 2/CentOS-like environment)
    sudo yum update -y || log_error "Failed to update system."
    sudo yum install -y docker || log_error "Failed to install Docker."
    sudo systemctl start docker || log_error "Failed to start Docker daemon."
    sudo systemctl enable docker || log_error "Failed to enable Docker at boot."
    log_info "Docker installed and started."
else
    log_info "Docker is already installed."
fi

# Add current user to docker group to avoid sudo for docker commands
if ! getent group docker | grep -qw "$USER"; then
    log_info "Adding $USER to the docker group..."
    sudo usermod -aG docker "$USER" || log_error "Failed to add user to docker group."
    log_info "Please log out and log back in for docker group changes to take effect, then re-run this script."
    exit 0
else
    log_info "$USER is already in the docker group."
fi


log_info "Checking for Docker Compose installation..."
# Check if docker compose plugin is installed (modern docker versions)
if docker compose version &> /dev/null; then
    log_info "Docker Compose (plugin) is already installed."
elif command -v docker-compose &> /dev/null; then
    log_info "Docker Compose (standalone) is already installed."
else
    log_info "Docker Compose not found. Installing Docker Compose (plugin)..."
    # Install Docker Compose as a plugin for Docker
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p $DOCKER_CONFIG/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m) -o $DOCKER_CONFIG/cli-plugins/docker-compose
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    log_info "Docker Compose installed."
fi


# --- 2. Prepare Nginx and Certbot directories ---
log_info "Preparing Nginx and Certbot configuration directories..."
mkdir -p nginx-conf || log_error "Failed to create nginx-conf directory."
mkdir -p certbot/conf || log_error "Failed to create certbot/conf directory."
mkdir -p certbot/www || log_error "Failed to create certbot/www directory."

# Create n8n.conf if it doesn't exist or ensure it has the correct content
# This ensures that even if the curl command misses it, the file is created.
# However, for a repo, it's better to simply ensure it's cloned.
# For simplicity, we assume 'n8n.conf' is already in 'nginx-conf' via git clone.

# Ensure the Nginx config is present (assuming it's cloned from the repo)
if [ ! -f "nginx-conf/n8n.conf" ]; then
    log_error "nginx-conf/n8n.conf not found. Ensure it's in your repository."
fi

# --- 3. Initial Certbot run to get certificates (without Nginx running on port 80/443 initially) ---
log_info "Attempting to obtain initial SSL certificates using Certbot..."
# It's crucial that nothing else is running on port 80/443 on the host for this step.
# For the very first run, Nginx won't be serving anything.
# We'll use the --standalone authenticator for the first certificate acquisition.
# If you prefer the --webroot method, you'd need a temporary web server.
# For simplicity and to avoid port conflicts, standalone is often easier for initial setup.

# Stop any running Nginx service on the host if it's there, to free port 80/443
log_info "Stopping any host-level Nginx to free up port 80/443 for Certbot's standalone authenticator..."
if sudo systemctl is-active --quiet nginx; then
    sudo systemctl stop nginx
    # If using systemctl, make sure it's not enabled to restart automatically during certbot run
    # sudo systemctl disable nginx # Only if you want to permanently disable it
fi


# Run Certbot to get initial certificates
# We use 'docker compose run --rm certbot' but with a command that uses standalone or temporary webroot
# For standalone, it temporarily binds to 80/443.
# For webroot, the Nginx container would need to be up serving the webroot.
# Let's stick to the webroot approach as it aligns with the docker-compose setup later.
# This means Nginx needs to be running *without* SSL for the initial cert acquisition, serving port 80.

log_info "Starting Nginx initially on port 80 for Certbot challenges..."
# Temporarily modify docker-compose.yml or use a specific command to bring up Nginx only on port 80
# The cleanest way is to ensure your `nginx-conf/n8n.conf` redirects all traffic to HTTPS *after* certs are obtained.
# For initial cert, it must serve the .well-known path.

# Bring up Nginx service temporarily (it will listen on port 80)
# Ensure your n8n.conf serves the /.well-known path from /var/www/certbot
docker compose up -d nginx || log_error "Failed to start Nginx for Certbot challenge."

log_info "Running Certbot to obtain certificates..."
# Use the 'docker compose' syntax
docker compose run --rm certbot certonly --webroot -w /var/www/certbot --email "$YOUR_EMAIL" --agree-tos --no-eff-email -d "$N8N_DOMAIN" || log_error "Certbot failed to obtain certificates."

log_info "Certificates obtained. Stopping Nginx for full restart with SSL."
docker compose stop nginx # Stop Nginx to apply new SSL certs

# --- 4. Bring up all services with Docker Compose ---
log_info "Bringing up all Docker Compose services (n8n, Nginx, Certbot)..."
docker compose up -d || log_error "Failed to start Docker Compose services."

log_info "Docker Compose services are running."
log_info "You can verify the status with: docker compose ps"
log_info "n8n should be accessible at: https://$N8N_DOMAIN"

# Re-enable host-level Nginx if it was disabled (optional, only if you have other stuff on it)
# if [ -f "/etc/nginx/nginx.conf.bak" ]; then
#     log_info "Restoring and restarting host-level Nginx (if applicable)."
#     sudo systemctl enable nginx
#     sudo systemctl start nginx
# fi

log_info "Installation script finished."

# Reminder for renewals (optional, can be done via cron on host or a separate container)
log_info "Remember to set up a cron job or a separate Docker Compose service for Certbot renewals:"
log_info "  For example, add a cron job to run 'docker compose run --rm certbot renew && docker compose restart nginx' periodically."
