#第一阶段：构建
FROM golang:1.22 AS build
WORKDIR /home/app
RUN wget https://gist.githubusercontent.com/abhishekkr/3beebbc1db54b3b54914/raw/16f13fe1d4d222df0ff21db0e1265c5b583c7477/tcp_server.go
RUN go mod init
RUN go mod download
RUN go build -o /home/app/tcp_server tcp_server.go

#第二阶段：运行
FROM debian:10-slim
WORKDIR /home/app
COPY --from=build /home/app/tcp_server ./tcp_server
CMD [ "./example" ]