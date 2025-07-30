FROM supabase/gotrue:v2.151.0 AS original
FROM scratch
COPY --from=original / /

# Make the PORT overrideable so the platform can do its thing
ENV PORT=9999
ENV GOTRUE_API_PORT=9999

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:9999/health || exit 1

ENTRYPOINT ["/usr/local/bin/gotrue"]
