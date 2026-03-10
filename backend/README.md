# Netty Echo Service

This repository holds the HTTP echo service implemented using [Netty](https://github.com/netty/netty).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Steps to run the application](#steps-to-run-the-application)

## Prerequisites

- Maven
- Java 21

## Steps to run the application

1. Build the project using the following command:

   ```shell
   mvn clean install
   ```

2. Run the application using the following command:

   ```shell
   java -jar target/netty-http-echo-service.jar --ssl false --http2 false
   ```

   > **Note:** The `--ssl` flag enables SSL (disabled here so the Ballerina scenario services can connect via plain HTTP). The `--http2` flag enables HTTP/2.

3. The application will start on port 8688. Test it using the following command:

   ```shell
   curl -v http://localhost:8688/service/EchoService -d "Hello Netty"
   ```
