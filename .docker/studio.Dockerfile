FROM ghcr.io/supabase/studio:v1.24.05 AS original
FROM scratch
COPY --from=original / /
ENTRYPOINT ["docker-entrypoint.sh"]
# Make the PORT overrideable so the platform can do its thing
ENV PORT=8080
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "require('http').get('http://localhost:8080/api/profile', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})" ]
CMD ["node", "apps/studio/server.js"]
