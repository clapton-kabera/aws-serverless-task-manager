import json
import pytest
from app import lambda_handler

# Fixture to generate a baseline API Gateway event payload
@pytest.fixture
def api_gateway_event():
    def _make_event(method="GET"):
        return {
            "httpMethod": method,  # REST API Format
            "requestContext": {    # HTTP API Format (covers both bases)
                "http": {
                    "method": method
                }
            },
            "path": "/hello",
            "headers": {
                "Accept": "application/json"
            }
        }
    return _make_event

def test_lambda_handler_handles_get_request(api_gateway_event):
    # Arrange: Build a fake GET event
    event = api_gateway_event(method="GET")
    
    # Act: Invoke the handler
    response = lambda_handler(event, context=None)
    
    # Assert: Verify success
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["message"] == "hello"

def test_lambda_handler_rejects_post_request(api_gateway_event):
    # Arrange: Build a fake POST event
    event = api_gateway_event(method="POST")
    
    # Act: Invoke the handler
    response = lambda_handler(event, context=None)
    
    # Assert: Verify method not allowed
    assert response["statusCode"] == 405
    body = json.loads(response["body"])
    assert "not allowed" in body["message"]
