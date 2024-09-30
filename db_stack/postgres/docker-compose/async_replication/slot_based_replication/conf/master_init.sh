#!/bin/bash
set -e

# Configuration variables
REPLICATION_USER="${REPLICATION_USER:-replicator}"
REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-replicator_password}"

# Create replication user on the master
echo "Creating replication user on master..."
psql -U postgres -c "CREATE ROLE ${REPLICATION_USER} WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';"


# Add replication entries to pg_hba.conf
IFS=',' read -r -a SLAVE_LIST <<< "$SLAVE_CONTAINERS"

for SLAVE in "${SLAVE_LIST[@]}"; do
    echo "host replication ${REPLICATION_USER} ${SLAVE} md5" >> /var/lib/postgresql/data/pg_hba.conf
    psql -U postgres -c "SELECT pg_create_physical_replication_slot('replication_slot_${SLAVE}');"
done

pg_ctl reload
