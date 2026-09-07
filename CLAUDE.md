# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gokapi is a self-hosted file-sharing server written in Go (module `github.com/forceu/gokapi`, Go 1.25+). It supports expiring file shares, user management with roles, file upload requests, deduplication, local or S3-compatible cloud storage, multiple encryption levels (including end-to-end), OpenID Connect, and a REST API.

## Common Commands

Always run `go generate ./...` before building or testing — it regenerates version numbers, protected URL lists, env-var docs, API routing tables, and (re)compiles the WASM downloader/E2E-encryption binaries that the webserver embeds. All `make` targets below already do this for you.

```bash
# Build the main server binary (./gokapi)
make build

# Build the CLI uploader client (./gokapi-cli)
make build-cli

# Run the standard test suite (AWS S3 calls mocked)
make test

# Run every test permutation used in CI (noaws, awsmock, awstest)
make test-all

# Run tests for a single package, e.g. TEST_PACKAGE=internal/storage
make test-specific TEST_PACKAGE=<path relative to module root>

# Generate HTML coverage report (opens browser)
make coverage
make coverage-specific TEST_PACKAGE=<path>

# Format code before committing
go fmt ./...

# Build the local Docker image
make docker-build
```

Equivalent raw `go test` invocations (useful for running a single test with `-run`):

```bash
go generate ./...
go test ./internal/storage/... -run TestSomething -tags=test,awsmock -v
```

### Build tags that matter

- `test` — required for any test run; gates the shared test-helper packages (`internal/test`, `internal/test/testconfiguration`).
- `awsmock` — S3 storage tests run against `gofakes3`, no real AWS credentials needed. Used by `make test`.
- `awstest` — S3 storage tests run against real AWS; requires `GOKAPI_AWS_BUCKET`, `GOKAPI_AWS_REGION`, `GOKAPI_AWS_KEY`, `GOKAPI_AWS_KEY_SECRET` env vars.
- `noaws` — builds/tests the AWS-free slim variant (`Aws_slim.go`) of the S3 driver.
- `integration` — enables slower integration tests (excluded from the default `Webserver_test.go` run via `!integration`).
- `tools` — gates the `build/go-generate/*.go` code-generation scripts; not part of normal builds.

CI (`.github/workflows/test-code.yml`) runs all four permutations (`awsmock`, `noaws`, `noaws+integration`, `awstest`), so don't assume `make test` alone covers everything before pushing.

## Architecture

### Startup sequence (`cmd/gokapi/Main.go`)
`main()` parses CLI flags → handles service install/DB migration flags → runs first-time `setup` wizard if needed → loads config (`internal/configuration`) → connects the database → initializes encryption, authentication, SSL, cloud config → runs `storage.CleanUp` → starts `webserver.Start()` in a goroutine → blocks on SIGINT/SIGTERM for graceful shutdown.

### Storage abstraction (`internal/storage`)
`internal/storage/filesystem` defines a `System` driver interface (`internal/storage/filesystem/interfaces`) implemented by `localstorage` and `s3filesystem`. The active driver is selected at runtime (`filesystem.SetAws()` if cloud config is present and reachable, otherwise local disk). File request uploads, chunked uploads (`internal/storage/chunking`), and presigned download links (`internal/storage/presign`) all go through this abstraction so callers don't need to know which backend is active.

### Database abstraction (`internal/configuration/database`)
`dbabstraction` defines the `Database` interface, implemented by providers in `database/provider/{sqlite,redis}`. `dbcache` provides an in-memory caching layer in front of the active provider. `database.Migrate()` can copy all data (API keys, users, files, hotlinks, file requests) between two database backends — this backs the `--migrate-db` CLI flow (`database/migration`).

### Encryption levels (`internal/encryption`)
Encryption is a single numeric level stored in config, checked throughout the webserver/storage layers:
- `NoEncryption` (0)
- `LocalEncryptionStored` (1) / `LocalEncryptionInput` (2) — local files only, cipher stored vs. entered at startup
- `FullEncryptionStored` (3) / `FullEncryptionInput` (4) — local + cloud files
- `EndToEndEncryption` (5) — browser-side encryption via the E2E WASM module; server never sees plaintext

### Webserver (`internal/webserver`)
Single `net/http` `ServeMux` wired up in `Webserver.go`, using embedded `web/static` and `web/templates` (via `//go:embed`) unless a local `templates`/`static` folder overrides them (dev convenience). `requireLogin()` wraps handlers needing authentication, distinguishing UI calls (redirect to `/login`) from API calls (401 JSON). Admin views are rendered through a single `AdminView` struct populated by `convertGlobalConfig()` based on which sub-view (`ViewMain`, `ViewLogs`, `ViewAPI`, `ViewUsers`, `ViewFileRequests`) is requested.

Two WASM binaries are embedded and served: `main.wasm` (client-side download/decryption) and `e2e.wasm` (end-to-end encryption on upload), built by `cmd/wasmdownloader` and `cmd/wasme2e` respectively via the `go generate` pipeline (`build/go-generate/buildWasm.go`).

### REST API (`internal/webserver/api`)
`Api.go` + `routing.go` (routing table auto-generated by `build/go-generate/updateApiRouting.go` from route doc comments) dispatch `/api/` requests. `openapi.json` at the repo root documents the API and is validated by `internal/webserver/api/openapi_test.go`.

### Other entry points (`cmd/`)
- `cmd/gokapi` — the main server.
- `cmd/cli-uploader` — standalone CLI client (`gokapi-cli`) that talks to a running Gokapi server's API to log in, upload, archive, and download files.
- `cmd/wasmdownloader`, `cmd/wasme2e` — compiled to WASM (`GOOS=js GOARCH=wasm`) and embedded into the webserver binary; not run as native binaries.
- `cmd/demoData` — populates a database with demo content, used for screenshots/demos.

### Configuration & environment
Runtime config is a mix of a persisted JSON config file (`internal/configuration`, `internal/models/Configuration.go`) managed via a first-run setup wizard (`internal/configuration/setup`) and environment variables (`internal/environment/Environment.go`, struct tags parsed by `caarlos0/env`). `configupgrade` handles migrating the on-disk config schema across versions. `.env.dist` documents available env vars — regenerate its reference docs with `go generate` (`updateEnvVariables.go`) after adding/changing an `Environment` field.

## Testing Conventions

- No third-party assertion library — use the hand-rolled helpers in `internal/test/TestHelper.go` (`IsEqualString`, `IsNil`, `HttpPageResult`, etc.), all gated behind the `test` build tag. Add `//go:build test` (or `//go:build !integration && test`) to the top of new test files as appropriate.
- `internal/test/testconfiguration` provides shared setup/teardown for tests that need a real config + database on disk.
- Tests that touch S3 storage must work under both `awsmock` (default, via `gofakes3`) and `awstest` (real AWS, gated by env vars) tags — check `internal/storage/filesystem/s3filesystem/aws` for the pattern (`Aws.go` / `Aws_mock.go` / `Aws_slim.go` split by build tag).
