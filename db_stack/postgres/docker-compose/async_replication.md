# PostgreSQL Asynchronous Replication

PostgreSQL supports asynchronous replication, a powerful feature that allows you to maintain standby replicas of a primary database for fault tolerance, load balancing, and scalability. In this guide, we cover various replication methods, focusing on **streaming replication**, **replication slots**, and **logical replication**.

## Table of Contents
- [Introduction](#introduction)
- [Streaming Replication](#streaming-replication)
  - [Step-by-Step Setup](#step-by-step-setup)
- [Replication Slot](#replication-slot)
  - [Benefits of Replication Slots](#replication-slot-setup)
  - [Types of Replication Slots](#replication-slot-setup)
- [Physical Replication Slot](#replication-slot)
  - [Step-by-Step Setup](#replication-slot-setup)
- [Logical Replication Slot](#logical-replication-slot)
  - [Step-by-Step Setup](#logical-replication-slot-setup)
- [Best Practices for Replication Slot](#other-replication-methods)
- [Archiving (WAL Shipping)](#best-practices)
- [Conclusion](#conclusion)

## Introduction

PostgreSQL asynchronous replication allows data changes made on a primary database to be replicated to one or more standby databases asynchronously. This setup ensures that the standbys are slightly behind the primary but can still serve as reliable backups. Here, we’ll walk through multiple replication strategies, their use cases, and how to implement them in PostgreSQL.

## Streaming Replication

Streaming replication is the most common form of PostgreSQL replication. In this setup, the primary database continuously streams write-ahead log (WAL) changes to the standby database, which applies these changes asynchronously.

### Benefits of Streaming Replication:
- Near real-time data replication.
- Efficient and lightweight for data consistency.
- Supports read scaling by allowing standby servers to serve read-only queries.

### Step-by-Step Setup

1. **Configure Primary Database**:
   - Open `postgresql.conf` and modify the following parameters:
     ```conf
     wal_level = replica
     max_wal_senders = 10
     wal_keep_size = 64MB
     ```

   - In `pg_hba.conf`, configure replication permissions for the standby:
     ```conf
     host replication all 0.0.0.0/0 md5
     ```

2. **Create Replication User**:
   ```sql
   CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'password';
   ```

3. **Configure Standby**:
    - On the standby server, initialize the standby database by using pg_basebackup:
    ```bash
    pg_basebackup -h primary_ip -D /path/to/data -P -U replicator --wal-method=stream
    ```

4. **Start Standby**:
    - Create a recovery.conf file or add the equivalent settings to postgresql.conf:

    ```
    primary_conninfo = 'host=primary_ip port=5432 user=replicator password=password'
    standby_mode = on
    ```
    - Start the PostgreSQL service on the standby:
    ```
    systemctl start postgresql
    ```
## Replication Slot

Replication slots are a crucial feature in PostgreSQL that ensure the retention of WAL (Write-Ahead Log) segments needed by standby servers until they are safely replicated. This prevents WAL segments from being removed before a standby server or other consumers have fully processed them. Replication slots help maintain continuity, even when standbys are temporarily disconnected.

### Benefits of Replication Slots:
- Prevents WAL files from being removed before the standby has received them.
- Ensures continuous replication even if a standby goes offline.
- Avoids data loss during temporary disconnects.

### Types of Replication Slots:
1. **Physical Replication Slot**: Retains WAL data for physical replication (standby servers).
2. **Logical Replication Slot**: Retains changes for logical replication (subscriptions to specific data changes).

## Physical Replication Slot
Retains WAL data for physical replication (standby servers).

### Step-by-Step Setup for Physical Replication Slot

1. **Create a Replication Slot on Primary**:
   - Use the following SQL command on the primary server to create a physical replication slot:
     ```sql
     SELECT * FROM pg_create_physical_replication_slot('slot_name');
     ```
   - This ensures that WAL files are retained until the standby connected to this slot has processed them.

2. **Configure the Standby to Use the Slot**:
   - On the standby server, modify the `primary_conninfo` configuration to include the slot name:
     ```conf
     primary_conninfo = 'host=primary_ip port=5432 user=replicator password=password application_name=standby1'
     primary_slot_name = 'slot_name'
     ```

3. **Restart the Standby**:
   - Apply the changes by restarting the standby server:
     ```bash
     systemctl restart postgresql
     ```

4. **Verify Replication**:
   - Ensure that the replication slot is active and that the standby is using it:
     ```sql
     SELECT slot_name, active FROM pg_replication_slots;
     ```

5. **Monitor WAL Retention**:
   - You can monitor the retention of WAL files by querying the `pg_stat_replication` view:
     ```sql
     SELECT * FROM pg_stat_replication;
     ```

   - Additionally, you can check if the replication slot is holding WAL segments:
     ```sql
     SELECT * FROM pg_replication_slots WHERE slot_name = 'slot_name';
     ```

## Logical Replication Slot
Retains changes for logical replication (subscriptions to specific data changes).
### Step-by-Step Setup for Logical Replication Slot

1. **Enable Logical Replication on Primary**:
   - Update `postgresql.conf` to enable logical replication by setting the `wal_level`:
     ```conf
     wal_level = logical
     max_replication_slots = 4
     ```

   - Reload the configuration:
     ```bash
     systemctl reload postgresql
     ```

2. **Create a Logical Replication Slot**:
   - Create a logical replication slot for streaming changes:
     ```sql
     SELECT * FROM pg_create_logical_replication_slot('logical_slot', 'pgoutput');
     ```

3. **Subscribe to the Logical Slot on the Standby**:
   - Create a subscription on the standby server to receive changes from the logical slot:
     ```sql
     CREATE SUBSCRIPTION my_subscription
     CONNECTION 'host=primary_ip dbname=primary_db user=replicator password=password'
     PUBLICATION my_publication;
     ```

4. **Monitor the Logical Replication Slot**:
   - Check the activity of the logical replication slot:
     ```sql
     SELECT * FROM pg_stat_replication;
     ```

5. **Managing Slot Retention**:
   - Replication slots can consume disk space if they retain too many WAL files. Use the following command to drop an unused slot:
     ```sql
     SELECT pg_drop_replication_slot('slot_name');
     ```

### Best Practices for Replication Slots:
- **Avoid Over Retention**: Monitor disk space to ensure that WAL files are not held indefinitely due to inactive slots.
- **Monitor Slot Usage**: Regularly check `pg_stat_replication` to track replication lag and slot activity.
- **Slot Cleanup**: Remove unused slots to avoid unnecessary WAL retention.
- **Use Replication Slots**: Always use replication slots to ensure WAL retention for disconnected standbys.
- **Consider Failover Strategies**: Implement automated failover mechanisms for high availability setups.
- **Tune WAL Parameters**: Adjust WAL settings based on network performance and replication lag tolerance.


## Archiving (WAL Shipping)

**WAL archiving** or **WAL shipping** is a form of replication where the primary database archives WAL files to a designated directory. These files are then shipped and applied to standby servers at regular intervals.

### Benefits of WAL Shipping:
- Suitable for environments where continuous streaming is not possible.
- Reduces the need for high-bandwidth connections.

### Step-by-Step Setup for WAL Shipping

1. **Enable WAL Archiving on Primary**:
   - Modify the `postgresql.conf` file to enable archiving:
     ```conf
     archive_mode = on
     archive_command = 'cp %p /path/to/archive/%f'
     ```

2. **Apply WAL Files on Standby**:
   - On the standby server, periodically apply the archived WAL files using the following:
     ```bash
     pg_standby /path/to/archive %f %r %d
     ```

3. **Automate WAL Shipping**:
   - Use a cron job or similar automation to transfer WAL files to the standby server.

#### Use Cases:
- **Low Bandwidth Connections**: Scenarios where streaming replication is impractical due to limited bandwidth.
- **Cold Standbys**: Setting up a cold standby that periodically catches up with the primary.

---



Replication slots provide a robust mechanism for ensuring that standby servers or logical replication subscribers receive the necessary WAL data without risking data loss during temporary disconnects.
