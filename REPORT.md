# CityBike SDLC Lab Report - Mission 6 Deliverables

**Author:** Mohith Ayanuru  
**Email:** mohith.ayanuru@epita.fr  
**Date:** November 6, 2026  
**Repository:** `~/lab/dev-machine/citybike`  

---

## 1. Docker Optimization Matrix

| Image Target | Image Size | Initial Build Time | 1-Line Rebuild Time | Key Architectural Characteristic |
| :--- | :--- | :--- | :--- | :--- |
| **`citybike:naive`** | `~1.2 GB` | `~50s` | `50.265s` | `COPY . .` placed before `npm ci`. Cache invalidated on every code edit; full 443 packages reinstalled. |
| **`citybike:cached`** | `~1.2 GB` | `~50s` | `~2.5s` | Layer split (`package*.json` copied first) + `.dockerignore`. `RUN npm ci` is `CACHED` on code edits. |
| **`citybike:shortcut`** | *N/A (Failed)* | *Failed* | *Failed* | Ran `npm ci --omit=dev`. Build failed at `npm run build` because development tools were excluded. |
| **`citybike:v1`** | `~180 MB` | `~50s` | `~3s` | Two-stage build: `node:20` compiles manifest; minimal `node:20-alpine` runs as non-root user `node`. |

---

## 2. Technical Explanation Questions

### Question A: Why did `citybike:shortcut` fail?
* **Exact Error Log:**
```text
BUILD ERROR: Necessary devDependencies missing. Run npm run build in the builder stage.
The command '/bin/sh -c npm run build' returned a non-zero code: 1
```
* **Explanation:**
The command `npm run build` invokes `scripts/build-manifest.js`, which relies on compiler packages and development tooling listed under `devDependencies` to emit `/app/dist/build-manifest.json`. Passing `--omit=dev` stripped these packages from `node_modules`, causing the build script to throw an explicit error. DevDependencies are mandatory during the build phase even if unnecessary at runtime.

### Question B: Why does `citybike:v1` have no `node_modules` directory?
* **Verification Command & Output:**
```bash
$ docker run --rm citybike:v1 ls node_modules
ls: node_modules: No such file or directory
```
* **Explanation:**
The multi-stage `Dockerfile` uses `node:20 AS builder` in Stage 1 to install all dependencies and build the manifest. Stage 2 (`FROM node:20-alpine`) starts clean and selectively copies only the runtime artifacts (`server.js`, `public/`, and `dist/build-manifest.json`). Because `server.js` relies strictly on Node.js core modules (`http`, `fs`, `path`) to serve static assets and JSON endpoints, no external runtime packages are required. Omitting `node_modules` completely eliminates ~1 GB of disk footprint and attack surface.

### Question C: What role does `.dockerignore` play?
* **Explanation:**
Without `.dockerignore`, the Docker client transmits unnecessary host directories (`node_modules`, `.git`, temporary log files, and build folders) across the socket into the daemon context. More critically, copying local host `node_modules` directly into the container can overwrite Linux-compiled binaries with host-specific dependencies and breaks layer cache validation. `.dockerignore` guarantees a clean, minimal build context.

---

## 3. Mission 4 Pipeline Implementation (Path B)

* **Script Path:** `scripts/pipeline.sh`
* **Configuration:**
  - Environment variable for runtime staging/production modes: `APP_ENV`
  - Production gate secret key: `PROD_API_KEY`
* **Pipeline Execution Log:**
```text
=== STAGE 1: LOCAL BUILD & SMOKE CHECK ===
Successfully built 48e2c488dc8c
Successfully tagged citybike:v1
✓ Local health check passed
=== STAGE 2: DEVELOPMENT ENVIRONMENT ===
✓ Dev environment verified
=== STAGE 3: QA ENVIRONMENT ===
✓ QA station route verified
=== STAGE 4: STAGING ENVIRONMENT ===
✓ Staging environment verified
=== STAGE 5: PRODUCTION DEPLOYMENT ===
✓ Production deployment verified with PROD_API_KEY
=============================================
🎉 ALL 5 ENVIRONMENTS SUCCESSFULLY PROMOTED!
=============================================
```

---

## 4. Mission 5 Regression & Gatekeeper Interception

* **Injected Fault:**
An intentional runtime exception placed in `server.js` before returning `/api/stations`:
```javascript
if (req.method === 'GET' && pathname === '/api/stations') {
  throw new Error('Simulated QA regression: database connection failed');
  return send(res, 200, { stations: stationsSnapshot });
}
```
* **Failure Evidence:**
```text
=== STAGE 1: LOCAL BUILD & SMOKE CHECK ===
✓ Local health check passed
=== STAGE 2: DEVELOPMENT ENVIRONMENT ===
✓ Dev environment verified
=== STAGE 3: QA ENVIRONMENT ===
curl: (52) Empty reply from server
```
* **Root Cause & Prevention Mechanism:**
Stages 1 (Local) and 2 (Dev) passed because their automated smoke checks solely probed the `/health` endpoint. When the pipeline promoted the container to **Stage 3 (QA)**, the regression probe targeted `/api/stations`. The uncaught exception terminated the Node process, resulting in an empty response (`curl: 52`). Due to `set -euo pipefail` in `scripts/pipeline.sh`, the pipeline aborted instantly, and the bash `trap cleanup EXIT` purged the container. **Stages 4 (Staging) and 5 (Production) were never triggered**, protecting live systems from the broken build.

---

## 5. Repository Verification

```bash
$ git tag -l
v1

$ git status
On branch main
Your branch is up to date with 'ogn/main'.
nothing to commit, working tree clean
```
