import json
import boto3
import datetime


def lambda_handler_ingrerss(event, context):
    for record in event["detail"]["requestParameters"]["ipPermissions"]["items"]:
        for ip_range in record.get("ipRanges", {}).get("items", []):
            cidr_ip = ip_range["cidrIp"]
            if cidr_ip.startswith(("10.", "172.16.", "192.168.")):  # Skip private ranges
                continue

            port = record.get("fromPort", "Unknown")
            group_id = event["detail"]["requestParameters"]["groupId"]
            user = event["detail"]["userIdentity"]["arn"]

            message = f"Security Group Rule Change Detected! \n\n"
            message += f"Security Group: {group_id}\nPort: {port}\nCIDR: {cidr_ip}\nUser: {user}"

            subject = "Security Group Ingress Alert"

    return (message,subject)

def lambda_handler_s3(event, context):
    for record in event["detail"]:
        bucket_name = record["requestParameters"]["bucketName"]
        event_name = record["eventName"]
        user = record["userIdentity"]["arn"]

        message = f"S3 Bucket Policy Changed!\n\nBucket: {bucket_name}\nEvent: {event_name}\nUser: {user}"
        subject = "S3 Bucket Policy Change Alert"

    return (message,subject)

def lambda_handler_user(event, context):

    for record in event.get("detail", {}):
        event_name = event["detail"].get("eventName")
        user_name = event["detail"].get("requestParameters", {}).get("userName")

        if event_name == "CreateUser":
            message = f"IAM User Created: {user_name}"
            subject="IAM create user alert"

        elif event_name == "CreateAccessKey":
            access_key_id = event["detail"].get("responseElements", {}).get("accessKey", {}).get("accessKeyId")
            message = f"New Access Key Created for: {user_name}, Access Key ID: {access_key_id}"
            subject="IAM create access key alert"


    return (message,subject)



def lambda_handler(event, context):
    sns_client = boto3.client('sns')
    sns_topic_arn = "arn:aws:sns:eu-north-1:183295413583:mySnsHomeTask"  # Replace with your SNS topic ARN

    try:
        detail = event.get('detail', {})
        event_name = detail.get('eventName', 'Unknown')

        if  event_name == "CreateUser" or event_name == "CreateAccessKey":
            message,subject = lambda_handler_user(event, context)
        elif  event_name == "AuthorizeSecurityGroupIngress":
            message,subject = lambda_handler_ingrerss(event, context)
        elif  event_name == "PutBucketPolicy":
            message,subject = lambda_handler_s3(event, context)
        else:
            message = "Unknown event"
            subject = "Unknown event"

        event_time = detail.get('eventTime', 'N/A')
        resource = detail.get('requestParameters', 'Unknown').get("Resource")

        message = f"{message}\n\nEvent Time: {event_time}\nResource: {resource}"


        sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject=subject
        )

        return {
            'statusCode': 200,
            'body': json.dumps('Alert sent successfully!')
        }
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps('Error processing event.')
        }
