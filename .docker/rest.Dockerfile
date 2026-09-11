FROM postgrest/postgrest:v14.17 AS original
FROM scratch
COPY --from=original / /
EXPOSE 8080
ENTRYPOINT ["postgrest"]
