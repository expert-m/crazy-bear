#!/bin/bash

# Clear up unused image
docker rmi $(docker images -q)

# Remove build cache
docker builder prune -f

# Clean up unused docker volumes
docker volume rm $(docker volume ls -qf dangling=true)

# Clear docker logs
truncate -s 0 /var/lib/docker/containers/**/*-json.log

sudo apt --purge autoremove -y

# Clear the journal log
sudo journalctl --vacuum-time=7days
