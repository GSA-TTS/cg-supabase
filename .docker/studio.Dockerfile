FROM supabase/studio:2026.09.07-sha-7996410 AS original
FROM scratch
COPY --from=original / /
WORKDIR /app
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "require('http').get('http://localhost:8080/api/profile', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})" ]
CMD ["node", "apps/studio/server.js"]
