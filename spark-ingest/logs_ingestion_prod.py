#!/usr/bin/env python3
"""
Production Log Ingestion Job
Ingests log data into Iceberg tables with enhanced error handling and monitoring
"""
import os
import sys
import uuid
from datetime import datetime, timezone
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit, current_timestamp, to_timestamp
from pyspark.sql.types import StructType, StructField, StringType, TimestampType, IntegerType

def create_spark_session():
    """Create Spark session with Iceberg support"""
    return SparkSession.builder \
        .appName(f"LogsIngestionProd-{uuid.uuid4().hex[:8]}") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.type", "hive") \
        .config("spark.sql.catalog.iceberg.uri", os.getenv('HIVE_METASTORE_URIS', 'thrift://localhost:9083')) \
        .config("spark.sql.catalog.iceberg.warehouse", "s3a://data-platform-iceberg-3e1b0c/warehouse/") \
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
        .config("spark.hadoop.fs.s3a.aws.credentials.provider", "com.amazonaws.auth.WebIdentityTokenCredentialsProvider") \
        .getOrCreate()

def get_log_schema():
    """Define the log schema for structured ingestion"""
    return StructType([
        StructField("timestamp", TimestampType(), True),
        StructField("level", StringType(), True),
        StructField("message", StringType(), True),
        StructField("source", StringType(), True),
        StructField("user_id", StringType(), True),
        StructField("session_id", StringType(), True),
        StructField("ip_address", StringType(), True),
        StructField("ingested_at", TimestampType(), True),
        StructField("batch_id", StringType(), True)
    ])

def generate_sample_data(spark, num_records=1000):
    """Generate sample log data for ingestion"""
    print(f"Generating {num_records} sample log records...")
    
    # Generate more realistic sample data
    import random
    from datetime import timedelta
    
    levels = ["INFO", "WARN", "ERROR", "DEBUG"]
    sources = ["web-server", "api-gateway", "database", "cache", "auth-service"]
    messages = [
        "User login successful",
        "Database connection established",
        "Cache miss for key",
        "API request processed",
        "Session expired",
        "File uploaded successfully",
        "Payment processed",
        "Error connecting to external service",
        "Memory usage high",
        "Disk space low"
    ]
    
    current_time = datetime.now(timezone.utc)
    batch_id = str(uuid.uuid4())
    
    # Generate data
    data = []
    for i in range(num_records):
        timestamp = current_time - timedelta(minutes=random.randint(0, 1440))  # Last 24 hours
        level = random.choice(levels)
        message = random.choice(messages)
        source = random.choice(sources)
        user_id = f"user_{random.randint(1000, 9999)}"
        session_id = str(uuid.uuid4())
        ip_address = f"192.168.{random.randint(1,255)}.{random.randint(1,255)}"
        
        data.append({
            "timestamp": timestamp,
            "level": level,
            "message": message,
            "source": source,
            "user_id": user_id,
            "session_id": session_id,
            "ip_address": ip_address,
            "ingested_at": current_time,
            "batch_id": batch_id
        })
    
    return spark.createDataFrame(data, get_log_schema())

def ensure_database_exists(spark):
    """Ensure the analytics database exists"""
    print("Ensuring analytics database exists...")
    spark.sql("CREATE DATABASE IF NOT EXISTS analytics")
    print("✅ Analytics database ready")

def ingest_logs(spark, batch_size=1000):
    """Main ingestion function"""
    job_start = datetime.now(timezone.utc)
    print(f"🚀 Starting log ingestion job at {job_start}")
    
    try:
        # Ensure database exists
        ensure_database_exists(spark)
        
        # Generate sample data (in production, this would read from source systems)
        df = generate_sample_data(spark, batch_size)
        
        print(f"📊 Processing {df.count()} log records")
        
        # Show sample of data being ingested
        print("📋 Sample of data being ingested:")
        df.show(5, truncate=False)
        
        # Partition by date for better query performance
        df_partitioned = df.withColumn("date_partition", col("timestamp").cast("date"))
        
        # Write to Iceberg table with append mode
        print("💾 Writing data to Iceberg table...")
        
        df_partitioned.write \
            .format("iceberg") \
            .mode("append") \
            .option("write.parquet.compression-codec", "snappy") \
            .partitionBy("date_partition") \
            .saveAsTable("analytics.logs")
        
        job_end = datetime.now(timezone.utc)
        duration = (job_end - job_start).total_seconds()
        
        print(f"✅ Ingestion completed successfully!")
        print(f"⏱️  Duration: {duration:.2f} seconds")
        print(f"📈 Records processed: {batch_size}")
        print(f"💽 Target table: analytics.logs")
        
        # Verify the data was written
        total_count = spark.sql("SELECT COUNT(*) as count FROM analytics.logs").collect()[0]['count']
        print(f"🔍 Total records in table: {total_count}")
        
        # Show distribution by level
        print("📊 Log level distribution:")
        spark.sql("SELECT level, COUNT(*) as count FROM analytics.logs GROUP BY level ORDER BY count DESC").show()
        
        return True
        
    except Exception as e:
        print(f"❌ Error during ingestion: {e}")
        print(f"Error type: {type(e).__name__}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """Main function"""
    print("=" * 60)
    print("🔧 Production Log Ingestion Job")
    print("=" * 60)
    
    spark = None
    try:
        # Create Spark session
        spark = create_spark_session()
        
        # Set log level to reduce verbosity
        spark.sparkContext.setLogLevel("WARN")
        
        print(f"✅ Spark session created: {spark.version}")
        print(f"🎯 Application ID: {spark.sparkContext.applicationId}")
        print(f"🏷️  Application Name: {spark.sparkContext.appName}")
        
        # Run ingestion
        success = ingest_logs(spark, batch_size=1000)
        
        if success:
            print("🎉 Job completed successfully!")
            sys.exit(0)
        else:
            print("💥 Job failed!")
            sys.exit(1)
            
    except Exception as e:
        print(f"💥 Fatal error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
    finally:
        if spark:
            spark.stop()

if __name__ == "__main__":
    main()
