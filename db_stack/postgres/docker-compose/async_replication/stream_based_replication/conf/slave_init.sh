#!/bin/bash
set -e

# Configuration variables
MASTER_HOST="${MASTER_HOST:-master_db}"
MASTER_PORT="${MASTER_PORT:-5432}"

bash -c "
rm -rf /var/lib/postgresql/data/*
until pg_basebackup --pgdata=/var/lib/postgresql/data -R --slot=replication_slot_${CONTAINER_NAME} --host=${MASTER_HOST} --port=${MASTER_PORT}
do
echo 'Waiting for primary to connect...'
sleep 1s
done
echo 'Backup done, starting replica...'
chmod 0700 /var/lib/postgresql/data
postgres
"