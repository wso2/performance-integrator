import ballerina/http;
import ballerina/log;

configurable string nettyUrl = ?;

final http:Client nettyEP = check new (nettyUrl,
    httpVersion = http:HTTP_1_1
);

listener http:Listener httpListener = new (9090,
    httpVersion = http:HTTP_1_1
);

service /passthrough on httpListener {

    isolated resource function post .(http:Request req) returns http:Response {
        do {
            return check nettyEP->forward("/", req);
        } on fail error e {
            log:printError("Error at h1_h1_passthrough", 'error = e);
            http:Response res = new;
            res.statusCode = 500;
            res.setPayload(e.message());
            return res;
        }
    }
}
