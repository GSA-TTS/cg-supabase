FROM supabase/storage-api:v1.74.0 AS original
FROM scratch
COPY --from=original / /
EXPOSE 8080
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node", "/app/dist/start/server.js"]
