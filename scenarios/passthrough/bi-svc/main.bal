// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

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
