#!/usr/bin/env python3

import sys
from pyspark.sql import SparkSession

def main():
    # Initialize Spark session with external Hive Metastore
    spark = SparkSession.builder \
        .appName("CreateExternalAnalyticsDatabase") \
        .config("hive.metastore.uris", "thrift://hive-metastore.hive.svc.cluster.local:9083") \
        .config("spark.sql.warehouse.dir", "s3a://data-platform-iceberg-3e1b0c/warehouse") \
        .enableHiveSupport() \
        .getOrCreate()

    try:
        print("=== Creating analytics database in EXTERNAL Hive Metastore ===")
        
        # Create the analytics database
        create_db_sql = """
        CREATE DATABASE IF NOT EXISTS analytics
        LOCATION 's3a://data-platform-iceberg-3e1b0c/warehouse/analytics'
        """
        
        spark.sql(create_db_sql)
        print("✅ Analytics database created successfully in external Hive Metastore!")
        
        # Verify it was created
        databases = spark.sql("SHOW DATABASES")
        print("\n=== Available databases in external Hive Metastore ===")
        databases.show()
        
        # Check the database location
        spark.sql("USE analytics")
        print("✅ Successfully switched to analytics database")
        
        # Show current database
        current_db = spark.sql("SELECT current_database()").collect()[0][0]
        print(f"✅ Current database: {current_db}")
        
    except Exception as e:
        print(f"❌ Error creating database: {str(e)}")
        import traceback
        traceback.print_exc()
        raise e
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
