from mitmproxy import http

def response(flow):
    flow.response.headers["Access-Control-Allow-Origin"] = "*"

    # Use this if the application sends auth info via header
    flow.response.headers["Access-Control-Expose-Headers"] = "Authorization"

def request(flow):
    # Hijack CORS OPTIONS request
    if flow.request.method == "OPTIONS":
        flow.response = http.Response.make(200, b"",
            {"Access-Control-Allow-Origin": "*",
             "Access-Control-Allow-Methods": "GET,POST",
             "Access-Control-Allow-Headers": "Authorization, Content-Type",
             "Access-Control-Max-Age": "1728000"})
