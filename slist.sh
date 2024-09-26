#!/bin/bash

git clone --branch feat/docker-image https://github.com/Odonno/surrealist.git
cd surrealist
docker build -t surrealist .
docker run -p 8080:8080 surrealist
