# Sentry integration

Sentry is a service that helps you monitor and fix crashes in real time. The server is in Python, but it contains a full API for sending events from any language, in any application.

## Sentry service configuration

### SaaS

1. Navigate to `https://sentry.io` and create a new account
2. Go to step 10 of the Self-Hosted Sentry instruction

### [Self-Hosted Sentry](https://develop.sentry.dev/self-hosted/)

1. Download sentry release from [GitHub](https://github.com/getsentry/onpremise/releases/latest).
2. Extract the archive to the `/opt` directory for example. Sentry will load config from this directory.
3. Run `./install.sh`.
4. Update SMTP server config in `sentry/config.yml`.
5. For integration with 3th-party services ([GitHub](https://develop.sentry.dev/integrations/github/)/[Slack](https://develop.sentry.dev/integrations/slack/)) update corresponding field in `sentry/config.yml`.
6. Use `docker-compose up -d` to start the sentry server.
7. Setup HTTPS reverse proxy (optional, but required for integration with Slack, etc).
8. Navigate to `http://<sentry_host>:9000/` or HTTPS proxy (if available).
9. Accept EULA and finish server configuration.
10. Create new Ruby project `http://<sentry_host>:9000/organizations/sentry/projects/new/`.
11. Copy the DSN value from the 'configuration' section.
12. Set SENTRY_DSN environment via `.env` or `.bashrc` files or any other way.
