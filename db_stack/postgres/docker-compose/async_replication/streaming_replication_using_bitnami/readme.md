# Setting up Read Replicas with Bitnami PostgreSQL Docker Image

This tutorial walks through the setup of PostgreSQL replication (master-slave) using Docker and Bitnami’s PostgreSQL image.

## TL;DR

This guide walks you through setting up **read replicas** using the Bitnami PostgreSQL Docker image. The setup includes one master and two read replicas, with **HAProxy** as a load balancer to route **read** requests to the `replicas` and **write** requests to the `master_db`. The configuration is managed via a `docker-compose.yml` file.

You can find the full code and configuration from Link below:

[Check out the GitHub repository for the code](https://github.com/your-username/your-repo-link)

---

### 1. Create Docker Compose File
Begin by creating a `docker-compose.yml` file in your project directory. This file contains the configuration for a master PostgreSQL database and two read replica databases, along with HAProxy for load balancing between the replicas.


### 2. Set Up PostgreSQL Master
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


### 3. Set Up PostgreSQL Replicas
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

## Conclusion

By following this guide, you've successfully set up a PostgreSQL master-replica architecture using Docker and Bitnami's PostgreSQL image. This setup efficiently handles **read-heavy** workloads by distributing read queries to the replicas while maintaining a single, writable master database, enhancing both performance and scalability. You can easily extend this configuration by adding more replicas or customizing HAProxy to suit your requirements.

### Recommended Usage:
- For **strong consistency**, connect directly to the `master_db` on port **5432**.
- For **read operations** with better scalability, use **HAProxy** as the database server to distribute the load across replicas.

---
<image name="designed" src="./design.webp" />

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

---

## Future Implementations

Here are some potential future improvements and extensions to this architecture which we will cover in next blog post.

1. **Automatic Failover**: Implement tools like **Patroni** or **pg_auto_failover** to automate failover from the master to a replica in case of a master database failure, ensuring higher availability.
   
2. **Synchronous Replication**: Enable synchronous replication to ensure data is written to at least one replica before being acknowledged by the master. This guarantees stronger consistency at the cost of performance.

3. **Horizontal Scaling for Writes**: Explore **multi-master replication** or sharding solutions like **Citus** to handle increasing write traffic by distributing write operations across multiple nodes.

4. **Monitoring and Alerting**: Implement monitoring tools like **pg_stat_replication** or **Prometheus + Grafana** to gain insights into replication lag, query performance, and overall health of the databases.

5. **Read-Replica Auto-scaling**: Automate the scaling of read replicas based on query load using container orchestration platforms like **Kubernetes**.

6. **Advanced HAProxy Features**: Utilize HAProxy’s advanced features, such as health checks, retry mechanisms, and custom routing algorithms, to further optimize traffic distribution and improve fault tolerance.

7. **Database Backup and Restore Automation**: Automate backups and disaster recovery processes using tools like **pgBackRest** or **WAL-G**, ensuring minimal downtime in case of failure.
