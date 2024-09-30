# Setting up Read Replicas with Bitnami PostgreSQL Docker Image

This tutorial walks through the setup of PostgreSQL replication (master-slave) using Docker and Bitnami’s PostgreSQL image.

## TL;DR

This guide walks you through setting up **read replicas** using the Bitnami PostgreSQL Docker image. The setup includes one master and two read replicas, with **HAProxy** as a load balancer to route **read** requests to the `replicas` and **write** requests to the `master_db`. The configuration is managed via a `docker-compose.yml` file.

**working**: uses streaming replication to sync replicas to master asynchronously(default).

You can find the full code and configuration from Link below:

[Check out the GitHub repository for the code](https://github.com/vKrypto/deploy-your-server/tree/main/db_stack/postgres/docker-compose/async_replication/streaming_replication_using_bitnami)

---

## Step by step Guide

### 1. Create Docker Compose File
Begin by creating a `docker-compose.yml` file in your project directory. This file contains the configuration for a master PostgreSQL database and two read replica databases, along with HAProxy for load balancing between the replicas.

**Architecture of docker-compose**

<image name="designed" src="./design.webp" />

### 2. Set Up PostgreSQL Master (master_db)
To start the containers, run the following command in your project directory:Define the master database configuration. This will serve as the primary write database, from which the read replicas will replicate data.

```
master_db:
  container_name: master_db
  <<: *postgres-common
  volumes:
    - 'postgresql_master_data:/bitnami/postgresql'
  environment:
    POSTGRESQL_USERNAME:  ${POSTGRES_USER:-postgres}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-postgres}
    POSTGRESQL_REPLICATION_USER: ${REPLICATION_USER:-replication_user}
    POSTGRESQL_REPLICATION_PASSWORD: ${REPLICATION_PASSWORD:-replication_password}
    POSTGRESQL_DATABASE: ${DB_NAME}
    POSTGRESQL_REPLICATION_MODE: master
```


### 3. Set Up PostgreSQL Replicas (Read Replicas)
Define two replicas (slave databases) that will replicate data from the master. Use the POSTGRESQL_REPLICATION_MODE to configure the replicas.
```
slave_db1:
  container_name: slave_db1
  <<: *postgres-common
  environment:
    <<: *postgres-environment
    POSTGRESQL_MASTER_HOST: master_db
    POSTGRESQL_MASTER_PORT_NUMBER: 5432
    POSTGRESQL_REPLICATION_MODE: slave
  depends_on:
    - master_db

slave_db2:
  container_name: slave_db2
  <<: *postgres-common
  environment:
    <<: *postgres-environment
    POSTGRESQL_MASTER_HOST: master_db
    POSTGRESQL_MASTER_PORT_NUMBER: 5432
    POSTGRESQL_REPLICATION_MODE: slave
  depends_on:
    - master_db

..... add as many as you want
```

### 4. Add Load Balancer (HAProxy)
HAProxy will act as the load balancer, routing read queries to the replicas while sending write queries to the master.

```
haproxy:
  image: haproxy:latest
  container_name: haproxy
  ports:
    - "5423:5432"  # HAProxy
  volumes:
    - ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg
  depends_on:
    - master_db
    - slave_db1
    - slave_db2
```
### 5. Add a haproxy.cfg file (routing rules)
create a file in the same dir with following routing rules(feel free to tweak it accordingly).
Note: using docker NS-Resolver to auto resolve ip addresses.

```
# haproxy.cfg

global
    log 127.0.0.1 local0
    maxconn 4096

defaults
    log global
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

frontend pgsql
    bind *:5432
    mode tcp
    default_backend pgsql-backend

backend pgsql-backend
    mode tcp
    balance roundrobin
    option tcp-check

    # Define the master database for write queries
    server master_db master_db:5432 check port 5432

    # Define the slave databases for read queries
    server slave_db1 slave_db1:5432 check port 5432
    server slave_db2 slave_db2:5432 check port 5432

    # Automatically route read queries (SELECT) to slaves
    acl is_read_query req.payload(0,256) -m sub SELECT
    use-server slave_db1 if is_read_query
    use-server slave_db2 if is_read_query

    # Route write queries (INSERT/UPDATE/DELETE) to the master
    acl is_write_query req.payload(0,256) -m sub INSERT
    acl is_write_query req.payload(0,256) -m sub UPDATE
    acl is_write_query req.payload(0,256) -m sub DELETE
    use-server master_db if is_write_query
```

## Conclusion

By following this guide, you've successfully set up a PostgreSQL master-replica architecture using Docker and Bitnami's PostgreSQL image. This setup efficiently handles **read-heavy** workloads by distributing read queries to the replicas while maintaining a single, writable master database, enhancing both performance and scalability. You can easily extend this configuration by adding more replicas or customizing HAProxy to suit your requirements.

### Recommended Usage:
- For **strong consistency**, connect directly to the `master_db` on port **5432**.
- For **read operations** with better scalability, use **HAProxy** as the database server to distribute the load across replicas.

---

## Pros and Cons of PostgreSQL Master-Replica Architecture with Bitnami and HAProxy

### Pros
- **Improved Read Performance**: Read-heavy queries are offloaded to replicas, reducing the load on the master database.
- **Scalability**: Easily add more replicas to handle increasing read traffic without affecting write performance.
- **High Availability**: In case of a replica failure, HAProxy can route traffic to other available replicas.
- **Load Balancing**: HAProxy routes read queries across replicas, improving performance and fault tolerance.
- **Simple Setup**: Bitnami Docker images simplify deploying a master-replica setup with minimal configuration.

### Cons
- **Eventual Consistency**: Replication is asynchronous, so there might be slight delays before data written to the master appears on replicas.
- **Increased Complexity**: Managing and monitoring multiple replicas increases operational complexity, especially in larger setups.
- **Resource Overhead**: Replicas require additional storage, CPU, and memory, which increases infrastructure costs.
- **No Write Load Balancing**: All writes are handled by the master, which can become a bottleneck if write traffic increases significantly.
- **HAProxy Configuration**: Proper HAProxy configuration is required to ensure optimal load balancing and fault tolerance.
- **No Table-Level or Database-Level Replication**: WAL logs record changes at the disk block level, not at the individual table or database level. This means there’s no way to filter out specific tables or databases during replication. we can explore logical replication if selective replication is our use-case.

---


## Under the Hood: Streaming Asynchronous Replication

In this setup, **streaming asynchronous replication** is used to replicate data from the master to the replicas. Here’s a breakdown of how this process works under the hood:

### 1. Write-Ahead Logging (WAL)
- **WAL Logs**: PostgreSQL uses Write-Ahead Logging (WAL) to maintain durability. All changes to the database are first written to a WAL log on the master.
- **WAL Segments**: WAL files are stored in segments on the master (`pg_wal` directory). These segments contain information about every data modification in the database.
  
### 2. Replication Slot
- **Replication Slot Creation**: When a replica (slave) connects to the master for the first time, a **replication slot** is created. This ensures the master keeps WAL segments available until the replica has processed them, preventing WAL logs from being prematurely deleted.
- **Slot Management**: The slot tracks the last position read by each replica, allowing the master to keep the necessary logs available.

### 3. Streaming WAL Logs to Replicas
- **WAL Stream**: Once a change is logged on the master, PostgreSQL begins streaming WAL data over a **TCP connection** to each replica.
- **Asynchronous Replication**: Since this is an asynchronous process, the master does not wait for the replicas to confirm they’ve applied the changes. This enhances performance but can lead to **replication lag** if the replica falls behind.
  
### 4. Application of WAL Logs on Replicas
- **WAL Playback**: On the replica, the streamed WAL logs are written to the replica’s `pg_wal` directory and then replayed to update the replica’s data.
- **Continuous Replay**: WAL logs are continuously replayed on the replicas, keeping them updated with the master’s changes but with a slight delay.

### 5. Replication Lag
- **Eventual Consistency**: The replicas are typically a few milliseconds to seconds behind the master, depending on the replication lag. This is a trade-off for higher performance.
- **Monitoring Lag**: Lag can be monitored using `pg_stat_replication`, which reports the amount of data the replica is behind.

### 6. Replication Conflicts
- **Read-Only Mode on Replicas**: The replicas are in **read-only mode**, meaning they cannot accept write queries. Replication conflicts (e.g., deadlocks) are avoided since only the master handles writes.
  
### 7. HAProxy Load Balancing
- **HAProxy**: In this setup, **HAProxy** acts as the **load balancer**. It routes **read** queries to the replicas and ensures **write** queries are directed to the master. HAProxy can also handle failover to another replica in case the master becomes unavailable (if configured).
- **Custom Routing**: You can customize HAProxy’s configuration to route specific queries or manage replica failures with health checks and retry mechanisms.

---

## Key Points of Streaming Asynchronous Replication

1. **Write-Ahead Logging (WAL)**: All changes on the master are first written to a WAL file before being replicated.
2. **Replication Slot**: Ensures the master keeps WAL logs until all replicas have applied them.
3. **WAL Streaming**: WAL logs are streamed over TCP to the replicas asynchronously.
4. **WAL Application on Replicas**: The replicas apply the WAL logs to keep themselves updated with the master.
5. **Replication Lag**: Replicas might fall behind slightly, causing a few milliseconds or seconds of delay.
6. **Read-Only Replicas**: Replicas cannot accept write queries, preventing write conflicts.
7. **HAProxy Load Balancing**: Routes read requests to replicas and write requests to the master, optimizing performance.

---

## Future Considerations

1. **Synchronous Replication**: If consistency is more critical than performance, consider enabling **synchronous replication**, where the master waits for the replica to acknowledge changes.
2. **Automatic Failover**: Use tools like **Patroni** or **pg_auto_failover** to automate failover in case the master goes down.
3. **Scaling Write Traffic**: Explore sharding or multi-master setups to scale write performance beyond a single master.

4. **Monitoring and Alerting**: Implement monitoring tools like **pg_stat_replication** or **Prometheus + Grafana** to gain insights into replication lag, query performance, and overall health of the databases.

5. **Read-Replica Auto-scaling**: Automate the scaling of read replicas based on query load using container orchestration platforms like **Kubernetes**.

6. **Advanced HAProxy Features**: Utilize HAProxy’s advanced features, such as health checks, retry mechanisms, and custom routing algorithms, to further optimize traffic distribution and improve fault tolerance.

7. **Database Backup and Restore Automation**: Automate backups and disaster recovery processes using tools like **pgBackRest** or **WAL-G**, ensuring minimal downtime in case of failure.

