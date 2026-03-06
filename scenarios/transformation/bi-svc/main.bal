import ballerina/data.xmldata;
import ballerina/http;

configurable string nettyUrl = ?;

listener http:Listener securedEP = new (9090,
    httpVersion = http:HTTP_1_1
);

final http:Client nettyEP = check new (nettyUrl,
    httpVersion = http:HTTP_1_1
);

service /jsonToXml on securedEP {
    
    resource function post .(@http:Payload json data) returns xml|error {
        json payload = check data.payload;
        xml xmlPayload = check xmldata:fromJson(payload);
        return nettyEP->/'service/EchoService.post(xmlPayload);
    }
}
