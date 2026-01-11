import json
import pandas as pd
from pandas import json_normalize
import boto3 
import io
import datetime

def flatten(data): 
    df = pd.json_normalize(
    data,
    record_path="products",
    meta=[
        "order_id",
        "order_date",
        "total_amount",
        ["customer", "customer_id"],
        ["customer", "name"],
        ["customer", "email"],
        ["customer", "address"],
    ],
)
    print(df.head())

def lambda_handler(event, context): 
    bucket_name = event['Records'][0]['s3']['bucket']['name']
    key=event['Records'][0]['s3']['object']['key']
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=bucket_name, Key=key)
    content = response["Body"].read().decode('utf-8')
    data = json.loads(content)
    df = flatten(data)
    print(df)
    parquet_buffer = io.BytesIO()
    df.to_parquet(parquet_buffer, index=False, engine='pyarrow')

    now = datetime.now()
    timestamp = now.strftime("%Y%m%d_%H%M%S")

    key_staging=f'orders_parquet_datalake/orders_ETL_{timestamp}.parquet'
    

    s3.put_object(Bucket=bucket_name, Key=key_staging, Body=parquet_buffer.getvalue())

    return {
        'statusCode': 200, 
        'body': json.dumps("Hello from lambda handler")
    }

# def check():
#     content = open("data/orders_etl.json", "r") 
#     data = json.load(content)  
#     df = json_normalize(data, 
#         record_path="products",
#         meta=[
#             "order_id",
#             "order_date",
#             "total_amount",
#             ["customer", "customer_id"],
#             ["customer", "name"],
#             ["customer", "email"],
#             ["customer", "address"],
#         ]
#     )
    
#     print(df.head())
#     print(df.shape)
#     print(df.columns)

# if __name__ == "__main__": 
#     check()