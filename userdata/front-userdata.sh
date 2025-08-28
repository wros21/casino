#!/bin/bash

# Actualizar el sistema
yum update -y

# Instalar Docker
yum install -y docker
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Instalar Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Instalar CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
rpm -U ./amazon-cloudwatch-agent.rpm

# Crear directorio de aplicación
mkdir -p /app
cd /app

# Crear archivo de configuración de la aplicación
cat << EOF > /app/.env
REDIS_ENDPOINT=$${redis_endpoint}
REDIS_PORT=6379
NODE_ENV=production
PORT=80
EOF

# Crear archivo Docker Compose para frontsite
cat << 'EOF' > /app/docker-compose.yml
version: '3.8'
services:
  frontsite:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
      - ./nginx.conf:/etc/nginx/nginx.conf
    environment:
      - REDIS_ENDPOINT=${redis_endpoint}
    restart: unless-stopped
    
  app:
    image: node:18-alpine
    working_dir: /app
    volumes:
      - ./app:/app
    environment:
      - REDIS_ENDPOINT=${redis_endpoint}
      - NODE_ENV=production
    command: ["node", "server.js"]
    restart: unless-stopped
EOF

# Crear configuración de Nginx
cat << 'EOF' > /app/nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream app_servers {
        server app:3000;
    }

    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass http://app_servers;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /health {
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Crear directorio HTML básico
mkdir -p /app/html
cat << 'EOF' > /app/html/index.html
<!DOCTYPE html>
<html>
<head>
    <title>Casino Online - Site</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body>
    <h1>Bienvenido al Casino Online</h1>
    <p>Aplicación funcionando correctamente - Wilhelm Otzoy</p>
    <p>Servidor: $(hostname)</p>
    <p>Fecha: $(date)</p>
</body>
</html>
EOF

# Crear aplicación Node.js básica
mkdir -p /app/app
cat << 'EOF' > /app/app/server.js
const http = require('http');
const os = require('os');

const server = http.createServer((req, res) => {
    if (req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('healthy');
        return;
    }

    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`
        <!DOCTYPE html>
        <html>
        <head>
            <title>Casino Online - site App</title>
        </head>
        <body>
            <h1>Casino Online - site</h1>
            <p>Aplicación funcionando - Wilhelm Otzoy - hagamos equipo</p>
            <p>Hostname: $${os.hostname()}</p>
            <p>Timestamp: $${new Date().toISOString()}</p>
        </body>
        </html>
    `);
});

const port = process.env.PORT || 3000;
server.listen(port, () => {
    console.log(`Server running on port ${port}`);
});
EOF

cat << 'EOF' > /app/app/package.json
{
  "name": "casino-frontsite",
  "version": "1.0.0",
  "description": "Casino Online Frontsite Application",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {}
}
EOF

# Configurar permisos
chown -R ec2-user:ec2-user /app
chmod +x /app

# Iniciar servicios
cd /app
docker-compose up -d

# Configurar logs
mkdir -p /var/log/casino-app
chown ec2-user:ec2-user /var/log/casino-app

# Crear script de monitoreo
cat << 'EOF' > /usr/local/bin/health-check.sh
#!/bin/bash
response=$(curl -o /dev/null -s -w "%%{http_code}\n" http://localhost/health)
if [ $response -eq 200 ]; then
    echo "Health check passed"
    exit 0
else
    echo "Health check failed with code: $response"
    exit 1
fi
EOF

chmod +x /usr/local/bin/health-check.sh

# Configurar cron para health check
echo "*/5 * * * * /usr/local/bin/health-check.sh >> /var/log/casino-app/health-check.log 2>&1" | crontab -

# Configurar CloudWatch Agent
cat << 'EOF' > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
    "metrics": {
        "namespace": "CasinoOnline/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/casino-app/*.log",
                        "log_group_name": "/aws/ec2/casino-online",
                        "log_stream_name": "{instance_id}/casino-app"
                    }
                ]
            }
        }
    }
}
EOF

# Iniciar CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

echo "Userdata script completed successfully" >> /var/log/userdata.log