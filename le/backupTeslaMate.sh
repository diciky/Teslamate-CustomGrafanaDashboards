#!/bin/bash
#
# Description: Script to backup the TeslaMate database
#
# Author: Carlos Cuezva
# Created: 23/04/2021
# Last update: 07/04/2023

PATH_COMPOSE='/volume1/docker/teslamate' #改成自己存放docker-compose.yml文件的位置
PATH_BACKUP='/volume1/bak' #改成自己期望存放备份文件的位置
REMOVE_OLDER=7 

echo -e '\n---- Starting the backup ----\n'

cd $PATH_COMPOSE
FILENAME=`date +"%Y%m%d_%H%M"`_teslamate.bck
docker-compose exec -T database pg_dump -U teslamate teslamate > $PATH_BACKUP/$FILENAME

cd $PATH_BACKUP
gzip -9 -f $FILENAME

FILESIZE=`du -h "$FILENAME.gz" | cut -f1`
echo -e "\nThe size of the backup is $FILESIZE\n"

#echo -e "\nRemoving backups older than $REMOVE_OLDER days\n"
#find $PATH_BACKUP -name '*_teslamate.bck.gz' -type f -mtime +$REMOVE_OLDER -delete

echo -e '\n---- Backup finished ----\n'

# docker compose exec -T database pg_dump -U teslamate teslamate > /volume1/docker/teslamate/bak/teslamate.bck