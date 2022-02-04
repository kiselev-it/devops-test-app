FROM golang:1.14 as builder
WORKDIR /app
COPY . .
RUN go build -o app
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/app /app/app
CMD ["/app/app"]