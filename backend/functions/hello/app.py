"""
app.py
author: Kabera Clapton

description: Test endpoint behind the Cognito JWT authorizer. Returns the caller's Cognito user ID
             (sub) and groups, to prove that verified identity reaches the Lambda.
"""

import json


def lambda_handler(event, context):
    """Handle GET /hello from API Gateway (HTTP API, payload format 2.0).

    API Gateway only routes GET /hello here, so no method check is needed.
    """
    request_context = event["requestContext"]
    #claims = request_context["authorizer"]["jwt"]["claims"]

    if request_context["http"]["method"] != "GET":
        return {
            "statusCode": 405,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": f"{request_context['http']['method']} not allowed"}),
        }

    body = {
        "message": "hello",
        "method": request_context["http"]["method"],
     #   "sub": claims.get("sub"),
        # HTTP APIs pass list claims as a single string, e.g. "[admin]".
        # Returned raw on purpose; proper parsing and role checks come in step 6.
      #  "groups": claims.get("cognito:groups"),
    }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
