"""
Simplified Iceberg Ingest Script using DataFrame API
"""

import logging
import time
import random
from pyspark.sql import SparkSession
from pyspark.sql.functions import current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, TimestampType

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_spark_session():
    """Create Spark session with Iceberg and Hive support"""
    return SparkSession.builder \
        .appName("SimpleIcebergIngest") \
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

def main():
    """Main ingestion function"""
    spark = create_spark_session()
    
    try:
        logger.info("Starting simplified Iceberg ingest")
        
        # Define schema for logs
        log_schema = StructType([
            StructField("timestamp", TimestampType(), True),
            StructField("level", StringType(), True),
            StructField("service", StringType(), True),
            StructField("message", StringType(), True),
            StructField("metadata", StringType(), True)
        ])
        
        # Generate sample data for testing
        logger.info("Creating sample data DataFrame")
        from pyspark.sql.functions import to_timestamp
        
        # Create DataFrame with string timestamps first, then convert
        sample_data = [
            ("2024-08-25 12:00:00", "INFO", "web-service", "User login successful", '{"user_id": "123", "ip": "192.168.1.1"}'),
            ("2024-08-25 12:01:00", "WARN", "api-service", "High latency detected", '{"endpoint": "/api/users", "latency_ms": 1500}'),
            ("2024-08-25 12:02:00", "ERROR", "db-service", "Connection timeout", '{"database": "main", "timeout_ms": 5000}'),
            ("2024-08-25 12:03:00", "INFO", "web-service", "User logout", '{"user_id": "123", "session_duration": 180}'),
            ("2024-08-25 12:04:00", "DEBUG", "cache-service", "Cache miss", '{"key": "user:123", "cache_type": "redis"}')
        ]
        
        # Create initial schema with string timestamps
        temp_schema = StructType([
            StructField("timestamp_str", StringType(), True),
            StructField("level", StringType(), True),
            StructField("service", StringType(), True),
            StructField("message", StringType(), True),
            StructField("metadata", StringType(), True)
        ])
        
        # Create DataFrame and convert string timestamp to timestamp type
        df = spark.createDataFrame(sample_data, temp_schema)
        df = df.withColumn("timestamp", to_timestamp(df.timestamp_str, "yyyy-MM-dd HH:mm:ss")) \
              .drop("timestamp_str") \
              .withColumn("ingestion_time", current_timestamp())
        
        logger.info(f"Sample data created with {df.count()} records")
        df.show(5, truncate=False)
        
        # Try simple write operation without explicit table creation
        logger.info("Writing data to Iceberg table using DataFrame API")
        
        # Use writeTo API which is more compatible with Iceberg
        df.writeTo("iceberg.analytics.logs") \
          .option("write-audit-publish.enabled", "true") \
          .createOrReplace()
        
        logger.info("✅ Data successfully written to Iceberg table using DataFrame API")
        
        # Verify the data
        logger.info("Verifying written data")
        result_df = spark.table("iceberg.analytics.logs")
        logger.info(f"Table has {result_df.count()} records")
        result_df.show(10, truncate=False)
        
        logger.info("✅ Simple Iceberg ingest completed successfully")
        
    except Exception as e:
        logger.error(f"❌ Simple Iceberg ingest failed: {e}")
        import traceback
        traceback.print_exc()
        raise
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
