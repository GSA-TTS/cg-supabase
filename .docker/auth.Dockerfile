FROM supabase/gotrue:v2.196.0 AS original
FROM scratch
COPY --from=original / /

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["/usr/local/bin/gotrue"]
