import json
import os
import boto3

s3 = boto3.client("s3")
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]


def handler(event, context):
    print("Received event:", json.dumps(event))

    for record in event.get("Records", []):
        # SNS->SQS payload ka format: Message body me SNS ka JSON hota hai
        body = json.loads(record["body"])
        msg = json.loads(body["Message"])

        bucket = msg["bucket"]
        key = msg["key"]
        size = msg.get("size", 0)

        result_key = f"processed/{key}.json"
        result_body = json.dumps({
            "original_bucket": bucket,
            "original_key": key,
            "size": size,
            "processed": True
        })

        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=result_key,
            Body=result_body.encode("utf-8")
        )

        print(f"Wrote processed result to s3://{OUTPUT_BUCKET}/{result_key}")

    return {"status": "processed"}
