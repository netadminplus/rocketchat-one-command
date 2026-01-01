# 🔧 Troubleshooting Guide

Common issues and their solutions for RocketChat deployment.

---

## 🚫 Installation Issues

### "Script must be run as root"

**Problem**: Running script without sudo/root privileges

**Solution**:
```bash
sudo ./rocketchat-installer.sh
```

---

### "System requirements not met"

**Problem**: Server doesn't meet minimum requirements

**Solutions**:

**RAM Issue (less than 2GB)**:
- Upgrade server to at least 2GB RAM (4GB recommended)
- Or use a swap file (not recommended for production):
```bash
  sudo fallocate -l 2G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

**Disk Space Issue (less than 20GB)**:
- Free up disk space
- Use larger volume/disk
- Clean Docker: `docker system prune -a`

---

### "Docker Hub is not accessible"

**Problem**: Cannot reach Docker Hub (common in Iran)

**Solution**:
- Provide a Docker registry mirror when prompted
- Popular Iranian mirrors:
  - `https://registry.docker.ir`
  - `https://docker.arvancloud.ir`

---

### "DNS mismatch" or "Domain does not resolve"

**Problem**: Domain not pointing to server

**Solution**:

1. Check your DNS settings at your domain registrar
2. Add/Update A record:
```
   Type: A
   Name: @ (or subdomain)
   Value: YOUR_SERVER_IP
   TTL: 3600
```
3. Wait for DNS propagation (can take 1-48 hours)
4. Verify DNS:
```bash
   dig +short your-domain.com
   nslookup your-domain.com
```

---

## 🐳 Docker Issues

### "Cannot connect to Docker daemon"

**Problem**: Docker service not running

**Solution**:
```bash
# Start Docker
sudo systemctl start docker

# Enable Docker on boot
sudo systemctl enable docker

# Check status
sudo systemctl status docker
```

---

### "docker compose: command not found"

**Problem**: Docker Compose not installed or old Docker version

**Solution**:
```bash
# Check Docker version
docker --version

# If old, reinstall using installer script
sudo ./rocketchat-installer.sh
```

---

### Images Won't Pull (Mirror Issues)

**Problem**: Cannot pull images even with mirror

**Solution**:

1. Test mirror connectivity:
```bash
   curl -I https://your-mirror-url
```

2. Try alternative mirror in `/etc/docker/daemon.json`:
```json
   {
     "registry-mirrors": ["https://alternative-mirror.com"]
   }
```

3. Restart Docker:
```bash
   sudo systemctl restart docker
```

---

## 🚀 RocketChat Issues

### RocketChat Won't Start

**Check logs**:
```bash
cd /path/to/rocketchat-deploy
docker compose logs rocketchat
```

**Common causes**:

**MongoDB not ready**:
```bash
# Check MongoDB status
docker compose logs mongodb

# Restart services
docker compose restart
```

**Port conflict**:
```bash
# Check if ports 80/443 are in use
sudo netstat -tulpn | grep -E ':(80|443)'

# Stop conflicting service or change ports
```

**Environment variables**:
```bash
# Verify .env file
cat .env

# Ensure no spaces around '='
# Ensure passwords don't have special characters that need escaping
```

---

### "502 Bad Gateway" Error

**Problem**: Traefik can't reach RocketChat

**Solutions**:

1. Check all containers are running:
```bash
   docker compose ps
```

2. Check RocketChat logs:
```bash
   docker compose logs rocketchat
```

3. Restart services:
```bash
   docker compose restart
```

4. Check network:
```bash
   docker network ls
   docker network inspect rocketchat-deploy_rocketchat-network
```

---

### SSL Certificate Issues

**Let's Encrypt rate limit**:
- Wait 1 week for rate limit to reset
- Use staging server for testing
- Ensure DNS is correct before running installer

**Certificate not obtained**:
```bash
# Check Traefik logs
docker compose logs traefik

# Verify domain points to server
dig +short your-domain.com

# Ensure ports 80/443 are open
sudo ufw status
```

**Force certificate renewal**:
```bash
# Stop services
docker compose down

# Remove old certificates
rm -rf data/certs/acme.json

# Start services (will request new cert)
docker compose up -d

# Watch Traefik logs
docker compose logs -f traefik
```

---

### MongoDB Connection Issues

**Check MongoDB health**:
```bash
docker compose exec mongodb mongosh --eval "db.adminCommand('ping')"
```

**Replica set issues**:
```bash
# Access MongoDB
docker compose exec mongodb mongosh -u root -p YOUR_PASSWORD --authenticationDatabase admin

# Check replica set status
rs.status()

# If not initialized, reinitialize
rs.initiate({
  _id: 'rs0',
  members: [{ _id: 0, host: 'mongodb:27017' }]
})

exit
```

**Connection string issues**:
```bash
# Verify credentials in .env
cat .env | grep MONGO

# Recreate containers
docker compose down
docker compose up -d
```

---

## 🔥 Firewall Issues

### Cannot Access RocketChat

**Check firewall status**:

**UFW**:
```bash
sudo ufw status

# If ports not open
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload
```

**Firewalld**:
```bash
sudo firewall-cmd --list-all

# If ports not open
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

**iptables**:
```bash
sudo iptables -L -n

# If ports not open
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables-save
```

---

## 💾 Data Issues

### Lost MongoDB Password

**Problem**: Cannot find MongoDB credentials

**Solution**:
```bash
# Check .env file
cat /path/to/rocketchat-deploy/.env

# If lost, reset MongoDB:
cd /path/to/rocketchat-deploy
docker compose down
rm -rf data/mongodb/*
# Run installer again (will regenerate)
```

---

### Database Corruption

**Symptoms**: RocketChat crashes, data inconsistencies

**Solution**:

1. Stop services:
```bash
   docker compose down
```

2. Repair MongoDB:
```bash
   docker compose run --rm mongodb mongod --repair --dbpath /data/db
```

3. Start services:
```bash
   docker compose up -d
```

4. If repair fails, restore from backup

---

### Disk Full

**Check disk usage**:
```bash
df -h
du -sh /path/to/rocketchat-deploy/data/*
```

**Clean up**:
```bash
# Clean Docker system
docker system prune -a

# Clean old logs
docker compose logs rocketchat > /dev/null 2>&1

# Clean old uploads (be careful!)
# Backup first!
```

---

## 🔍 Performance Issues

### Slow Response Times

**Solutions**:

1. Check resource usage:
```bash
   docker stats
```

2. Increase server resources (RAM/CPU)

3. Optimize MongoDB:
```bash
   # Access MongoDB
   docker compose exec mongodb mongosh -u root -p PASSWORD --authenticationDatabase admin
   
   use rocketchat
   
   # Check indexes
   db.getCollectionNames().forEach(function(collection) {
      print("Indexes for " + collection + ":");
      printjson(db[collection].getIndexes());
   })
```

4. Enable MongoDB caching (add to docker-compose.yml):
```yaml
   mongodb:
     command: mongod --oplogSize 128 --replSet rs0 --wiredTigerCacheSizeGB 1
```

---

### High Memory Usage

**Check memory**:
```bash
free -h
docker stats
```

**Solutions**:
- Restart containers: `docker compose restart`
- Increase server RAM
- Limit container memory in docker-compose.yml:
```yaml
  rocketchat:
    deploy:
      resources:
        limits:
          memory: 2G
```

---

## 📱 Client Issues

### Mobile App Won't Connect

**Checklist**:
- [ ] SSL certificate is valid (HTTPS required)
- [ ] Domain is accessible from internet
- [ ] Websocket connections allowed
- [ ] Firewall not blocking connections

**Test**:
```bash
# Test from another machine
curl -I https://your-domain.com

# Check SSL
openssl s_client -connect your-domain.com:443
```

---

### Upload Issues

**Problem**: Cannot upload files

**Solutions**:

1. Check upload directory permissions:
```bash
   ls -la /path/to/rocketchat-deploy/data/uploads
   sudo chmod -R 755 /path/to/rocketchat-deploy/data/uploads
```

2. Check disk space:
```bash
   df -h
```

3. Check RocketChat upload settings:
   - Login as admin
   - Administration → File Upload
   - Increase max file size

---

## 🆘 Emergency Recovery

### Complete System Failure

If everything is broken:

1. **Stop all services**:
```bash
   cd /path/to/rocketchat-deploy
   docker compose down
```

2. **Backup current state** (even if broken):
```bash
   tar -czf rocketchat-emergency-backup-$(date +%Y%m%d).tar.gz data/ .env docker-compose.yml
```

3. **Check logs for errors**:
```bash
   docker compose logs > emergency-logs.txt
```

4. **Try clean restart**:
```bash
   docker compose up -d
```

5. **If still broken, reinstall**:
```bash
   # Backup data
   cp -r data/ data.backup/
   
   # Remove everything except data
   docker compose down -v
   rm docker-compose.yml .env
   
   # Run installer again
   sudo ./rocketchat-installer.sh
   
   # Restore data if needed
```

---

## 📞 Get Help

If you're still stuck:

- 📺 **YouTube**: [@netadminplus](https://youtube.com/@netadminplus) - Tutorial videos
- 🌐 **Website**: [netadminplus.com](https://netadminplus.com) - Contact form
- 📸 **Instagram**: [@netadminplus](https://instagram.com/netadminplus) - DM for support
- 🐛 **GitHub Issues**: Report bugs on the repository
- 💬 **RocketChat Community**: [forums.rocket.chat](https://forums.rocket.chat)

---

**Created by Ramtin - NetAdminPlus**

*Helping the Iranian tech community deploy reliable communication tools* 🚀