"""
Enhanced Log Ingestion Script for Iceberg with retry and lock handling
"""

import logging
import time
import random
from pyspark.sql import SparkSession
from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql.types import StructType, StructField, StringType, TimestampType

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_spark_session():
    """Create Spark session with Iceberg and Hive support"""
    return SparkSession.builder \
        .appName("LogIngestWithRetry") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.type", "hive") \
        .config("spark.sql.catalog.iceberg.uri", "thrift://hive-metastore.hive.svc.cluster.local:9083") \
        .config("spark.sql.catalog.iceberg.warehouse", "s3a://logexaminer-data-dev/ingestion/") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .enableHiveSupport() \
        .getOrCreate()

def ensure_table_exists_with_retry(spark, table_name, schema, max_retries=5):
    """Ensure table exists with retry logic for lock contention"""
    
    for attempt in range(max_retries):
        try:
            logger.info(f"Attempt {attempt + 1}: Checking if table {table_name} exists")
            
            # Check if table already exists
            try:
                spark.sql(f"DESCRIBE TABLE {table_name}")
                logger.info(f"Table {table_name} already exists")
                return True
            except Exception:
                logger.info(f"Table {table_name} does not exist, attempting to create")
            
            # Create table with simplified approach to avoid locking issues
            logger.info(f"Creating table {table_name}")
            
            # Use spark.sql instead of DataFrame API to avoid complex locking
            create_sql = f"""
            CREATE TABLE IF NOT EXISTS {table_name} (
                timestamp TIMESTAMP,
                level STRING,
                service STRING,
                message STRING,
                metadata STRING,
                ingestion_time TIMESTAMP
            ) USING ICEBERG
            LOCATION 's3a://logexaminer-data-dev/ingestion/{table_name.split(".")[1]}/'
            TBLPROPERTIES (
                'write.format.default' = 'parquet',
                'write.metadata.compression-codec' = 'gzip',
                'commit.retry.num-retries' = '10',
                'commit.retry.min-wait-ms' = '100',
                'commit.retry.max-wait-ms' = '60000'
            )
            """
            
            spark.sql(create_sql)
            logger.info(f"Successfully created table {table_name}")
            return True
            
        except Exception as e:
            logger.warning(f"Attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                # Exponential backoff with jitter
                wait_time = (2 ** attempt) + random.uniform(0, 1)
                logger.info(f"Waiting {wait_time:.2f} seconds before retry")
                time.sleep(wait_time)
            else:
                logger.error(f"All {max_retries} attempts failed for table creation")
                raise

def main():
    """Main ingestion function"""
    spark = create_spark_session()
    
    try:
        logger.info("Starting log ingestion with retry logic")
        
        # Define schema for logs
        log_schema = StructType([
            StructField("timestamp", TimestampType(), True),
            StructField("level", StringType(), True),
            StructField("service", StringType(), True),
            StructField("message", StringType(), True),
            StructField("metadata", StringType(), True)
        ])
        
        table_name = "iceberg.analytics.logs"
        
        # Ensure table exists with retry logic
        if not ensure_table_exists_with_retry(spark, table_name, log_schema):
            raise RuntimeError(f"Failed to create table {table_name}")
        
        logger.info("Table creation/verification completed successfully")
        
        # Generate sample data for testing
        sample_data = [
            ("2024-08-25 12:00:00", "INFO", "web-service", "User login successful", '{"user_id": "123", "ip": "192.168.1.1"}'),
            ("2024-08-25 12:01:00", "WARN", "api-service", "High latency detected", '{"endpoint": "/api/users", "latency_ms": 1500}'),
            ("2024-08-25 12:02:00", "ERROR", "db-service", "Connection timeout", '{"database": "main", "timeout_ms": 5000}'),
            ("2024-08-25 12:03:00", "INFO", "web-service", "User logout", '{"user_id": "123", "session_duration": 180}'),
            ("2024-08-25 12:04:00", "DEBUG", "cache-service", "Cache miss", '{"key": "user:123", "cache_type": "redis"}')
        ]
        
        logger.info("Creating sample data DataFrame")
        df = spark.createDataFrame(sample_data, log_schema)
        df = df.withColumn("ingestion_time", current_timestamp())
        
        logger.info(f"Sample data created with {df.count()} records")
        df.show(5, truncate=False)
        
        # Write data with retry logic
        max_write_retries = 3
        for attempt in range(max_write_retries):
            try:
                logger.info(f"Write attempt {attempt + 1}: Inserting data into {table_name}")
                
                df.write \
                  .format("iceberg") \
                  .mode("append") \
                  .option("write-audit-publish.enabled", "true") \
                  .option("commit.retry.num-retries", "10") \
                  .option("commit.retry.min-wait-ms", "100") \
                  .option("commit.retry.max-wait-ms", "60000") \
                  .saveAsTable(table_name)
                
                logger.info("Data successfully written to Iceberg table")
                break
                
            except Exception as e:
                logger.warning(f"Write attempt {attempt + 1} failed: {e}")
                if attempt < max_write_retries - 1:
                    wait_time = (2 ** attempt) + random.uniform(0, 2)
                    logger.info(f"Waiting {wait_time:.2f} seconds before retry")
                    time.sleep(wait_time)
                else:
                    logger.error(f"All {max_write_retries} write attempts failed")
                    raise
        
        # Verify the data
        logger.info("Verifying written data")
        result_df = spark.sql(f"SELECT * FROM {table_name} ORDER BY timestamp DESC LIMIT 10")
        result_df.show(truncate=False)
        
        record_count = spark.sql(f"SELECT COUNT(*) as count FROM {table_name}").collect()[0]['count']
        logger.info(f"Total records in table: {record_count}")
        
        logger.info("✅ Log ingestion completed successfully")
        
    except Exception as e:
        logger.error(f"❌ Ingestion failed: {e}")
        raise
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
