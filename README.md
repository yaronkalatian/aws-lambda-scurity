# aws-lambda-scurity

The AWS Lambda function  monitor and alert on specific security-related events in AWS environment.
The function is triggered by EventBridge (CloudWatch Events) rules that capture events:
"CreateUser" for IAM User Creation. 
"CreateAccessKey" for IAM User Creating New Programmatic Access Keys.
"PutBucketPolicy" for S3 Bucket Policy Changes.
"AuthorizeSecurityGroupIngress" for Security Group Ingress Rule Changes.

after processing the event by its type as describe above the lambda send SNS alret notification (which is subscribe to email)
containing:
 Time
 Resource
 Initiator 
 Action 

 the lambda is written in python
 The entire solution is deployed with Terraform  

deploy:
1. pull the files to directory home_task
2. cd home_task
3. terraform init
4. terraform apply 

how to test 
1. pull the event.json
2. run lamda-invoke:

aws lambda invoke \
  --function-name SecurityMonitoring \
  --payload fileb://event.json \
  response.json

3. check for new email  or cloudwatch log group /aws/lambda/SecurityMonitoring  