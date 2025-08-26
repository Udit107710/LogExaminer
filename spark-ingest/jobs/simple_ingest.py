"""
Simple Log Ingestion Script for testing connectivity
"""

import logging
from pyspark.sql import SparkSession
from pyspark.sql.functions import current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, TimestampType

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_spark_session():
    """Create basic Spark session with Hive support"""
    return SparkSession.builder \
        .appName("SimpleLogIngest") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .enableHiveSupport() \
        .getOrCreate()

def main():
    """Main ingestion function"""
    spark = create_spark_session()
    
    try:
        logger.info("Starting simple log ingestion test")
        
        # Test Hive Metastore connection
        try:
            logger.info("Testing connection to Hive Metastore")
            databases = spark.sql("SHOW DATABASES").collect()
            logger.info(f"Available databases: {[row.databaseName for row in databases]}")
        except Exception as e:
            logger.error(f"Failed to connect to Hive Metastore: {e}")
            raise
        
        # Test if analytics database exists
        try:
            spark.sql("USE analytics")
            logger.info("Successfully switched to analytics database")
            tables = spark.sql("SHOW TABLES").collect()
            logger.info(f"Tables in analytics database: {[row.tableName for row in tables]}")
        except Exception as e:
            logger.warning(f"Could not use analytics database: {e}")
        
        # Generate sample data for testing
        sample_data = [
            ("2024-08-25 12:00:00", "INFO", "web-service", "User login successful", '{"user_id": "123"}'),
            ("2024-08-25 12:01:00", "WARN", "api-service", "High latency detected", '{"endpoint": "/api/users"}'),
            ("2024-08-25 12:02:00", "ERROR", "db-service", "Connection timeout", '{"database": "main"}'),
        ]
        
        log_schema = StructType([
            StructField("timestamp", TimestampType(), True),
            StructField("level", StringType(), True),
            StructField("service", StringType(), True),
            StructField("message", StringType(), True),
            StructField("metadata", StringType(), True)
        ])
        
        logger.info("Creating sample data DataFrame")
        df = spark.createDataFrame(sample_data, log_schema)
        df = df.withColumn("ingestion_time", current_timestamp())
        
        logger.info(f"Sample data created with {df.count()} records")
        df.show(truncate=False)
        
        # Test S3 access (optional - will fail gracefully if not configured)
        try:
            logger.info("Testing S3 access...")
            # Just attempt to write a small test file
            df.write \
              .mode("overwrite") \
              .option("path", "s3a://logexaminer-data-dev/test-connectivity/") \
              .format("parquet") \
              .save()
            logger.info("✅ S3 write test successful")
        except Exception as e:
            logger.warning(f"S3 write test failed (may be expected): {e}")
        
        logger.info("✅ Simple ingest test completed successfully")
        
    except Exception as e:
        logger.error(f"❌ Simple ingest test failed: {e}")
        raise
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
