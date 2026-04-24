FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -o /bin/server .

FROM alpine:3.19
RUN apk add --no-cache curl
COPY --from=build /bin/server /usr/local/bin/server
EXPOSE 8080
CMD ["/usr/local/bin/server"]
