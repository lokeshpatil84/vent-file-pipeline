import json
import os
import boto3

sns = boto3.client("sns")
TOPIC_ARN = os.environ["TOPIC_ARN"]


def handler(event, context):
    print("Received event:", json.dumps(event))

    records = event.get("Records", [])
    for r in records:
        s3_info = r["s3"]
        bucket = s3_info["bucket"]["name"]
        key = s3_info["object"]["key"]
        size = s3_info["object"].get("size", 0)

        message = {
            "bucket": bucket,
            "key": key,
            "size": size,
        }

        sns.publish(
            TopicArn=TOPIC_ARN,
            Message=json.dumps(message),
            Subject="New file uploaded"
        )

        print(f"Published message to SNS for {bucket}/{key}")

    return {"status": "ok"}
