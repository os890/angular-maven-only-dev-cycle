# Angular dev cycle with Maven only

**From "the frontend-maven-plugin packs Angular into the WAR" to a full daily
frontend development setup — on a machine that has nothing but Java and Maven.**

Many Jakarta EE teams already use the
[frontend-maven-plugin](https://github.com/eirslett/frontend-maven-plugin)
("eirslett plugin") to build an Angular app and package it into a WAR. That solves the
*build*. This tutorial adds the frontend *development cycle* on top of it:

- the Angular dev server (`ng serve`) with live reload and hot module replacement,
- REST calls from the dev server forwarded to the server that provides the REST APIs,
- the Angular CLI (`ng generate`, `ng update`, …) and npm for daily work,
- unit tests in the build and in watch mode,

…without anyone installing Node.js, npm or the Angular CLI by hand. Maven downloads
a pinned Node.js (npm is bundled with it) into the project; the Angular CLI is an
ordinary dev dependency in `node_modules`. Nothing is installed globally.

The backend is out of scope: the tutorial assumes there is a running server that
provides the REST APIs (locally, started from the IDE, or a shared dev/test server).

> **Verified setup.** Every command in this tutorial was run against a sample WAR
> project with: Maven 3.9.14 · frontend-maven-plugin 1.15.1 · Node.js 24.15.0 ·
> npm 11.12.1 (bundled) · Angular 22.3.0 · macOS.
> The Windows wrapper script in step 4 was **not** tested.

## The result at a glance

| You want to … | Command (from the WAR module) |
|---|---|
| start the Angular dev server (live reload, `/api` proxy) | `mvn -Png-serve` |
| run any Angular CLI command | `./npmw exec -- ng generate component features/foo` |
| run any npm command | `./npmw install date-fns` |
| run unit tests in watch mode | `./npmw test -- --watch` |
| build the deployable WAR (incl. frontend tests) | `mvn package` |

Daily work happens on **http://localhost:4200** (Angular dev server). It serves the
frontend from memory and forwards every `/api/**` call to the REST server.

```
browser ──► localhost:4200                      ng serve
               │                                frontend/src, hot reload
               │
               └── /api/** ──► localhost:8080/myapp/api/**
                                                REST server (already running)
```

> **npm and `--`.** npm reads options before a `--` as its *own* options. Everything
> meant for the script or tool goes after `--`: `npm start -- --port 4300`,
> `npm test -- --watch`, `npm exec -- ng generate … --skip-tests`. Without the `--`,
> npm silently swallows options such as `--skip-tests` (verified: the spec file was
> generated anyway).

---

## 0. The starting point

The tutorial assumes a WAR module with the Angular app in a `frontend/` subfolder.
Adapt paths if your layout differs (e.g. a separate frontend module).

```
myapp/
├── pom.xml                      packaging: war
├── src/main/…                   server side (not touched by this tutorial)
└── frontend/
    ├── package.json
    ├── package-lock.json
    ├── angular.json
    └── src/…
```

This is what "already works" with the plugin: Node and npm are downloaded, the
Angular app is built, and the Maven WAR plugin copies the build output into the WAR.

```xml
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <version>1.15.1</version>
    <configuration>
        <workingDirectory>frontend</workingDirectory>
        <installDirectory>target</installDirectory>
    </configuration>
    <executions>
        <execution>
            <id>install-node-and-npm</id>
            <goals>
                <goal>install-node-and-npm</goal>
            </goals>
            <configuration>
                <nodeVersion>v24.15.0</nodeVersion>
            </configuration>
        </execution>
        <execution>
            <id>npm-ci</id>
            <goals>
                <goal>npm</goal>
            </goals>
            <configuration>
                <arguments>ci --ignore-scripts</arguments>
            </configuration>
        </execution>
        <execution>
            <id>npm-build</id>
            <goals>
                <goal>npm</goal>
            </goals>
            <configuration>
                <arguments>run build</arguments>
            </configuration>
        </execution>
    </executions>
</plugin>
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-war-plugin</artifactId>
    <version>3.4.0</version>
    <configuration>
        <webResources>
            <resource>
                <directory>frontend/dist/frontend/browser</directory>
            </resource>
        </webResources>
    </configuration>
</plugin>
```

`npm ci` installs exactly what `package-lock.json` says and fails if `package.json`
and the lock file disagree — the right choice for a build. `--ignore-scripts` keeps
the lifecycle scripts of dependencies from running.

The WAR is deployed under a context root (here `/myapp`), so the production build
uses that as base href. Only the **production** configuration in `angular.json`
gets it; the dev server keeps `/`:

```json
"configurations": {
  "production": {
    "baseHref": "/myapp/",
    "outputHashing": "all"
  }
}
```

**What is missing for daily work:**

| Need | Status with the plugin alone |
|---|---|
| Angular dev server with live reload | ✗ only full builds; every change = `mvn package` + redeploy |
| Frontend talks to the REST server during development | ✗ |
| Angular CLI (`ng generate`, `ng update`) | ✗ Node is only reachable from inside Maven |
| Unit tests | ✗ not part of the build |
| IDE support (Node interpreter) | ✗ Node lives in `target/` and disappears with `mvn clean` |

---

## 1. Plugin-level configuration and a stable tool location

Two small changes make the plugin usable for more than the build.

**a) The Node version and the directories move to the plugin-level `<configuration>`.**
Settings inside an `<execution>` only apply to that execution. Command-line calls such
as `mvn frontend:npm …` (step 4) run as execution `default-cli` and only see the
plugin-level configuration.

**b) The tools move from `target/` to `.tooling/`.** `mvn clean` deletes `target/`,
and with it Node and npm. Maven caches the downloads in `~/.m2`, so a reinstall is
quick, but the IDE's Node interpreter path (step 5) and the `npmw` wrapper (step 4)
need a path that stays put.

```xml
<properties>
    <!-- frontend toolchain: Node.js (npm is bundled with it) -->
    <node.version>v24.15.0</node.version>
</properties>
```

```xml
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <version>1.15.1</version>
    <!-- plugin-level: also used by command-line calls (mvn frontend:npm ...) -->
    <configuration>
        <workingDirectory>frontend</workingDirectory>
        <installDirectory>.tooling</installDirectory>
        <nodeVersion>${node.version}</nodeVersion>
    </configuration>
    <executions>
        <execution>
            <id>install-node-and-npm</id>
            <goals>
                <goal>install-node-and-npm</goal>
            </goals>
        </execution>
        <!-- npm-ci and npm-build: unchanged -->
    </executions>
</plugin>
```

The npm version is the one bundled with the Node version. To pin a different one, add
`<npmVersion>` next to `<nodeVersion>`.

Ignore the new directory in git (`.gitignore` next to the `pom.xml`):

```
.tooling/
```

**Supply-chain safety net.** Put an `.npmrc` into `frontend/`:

```
ignore-scripts=true
```

With it, *every* npm call — also the ones you type in step 4, such as
`npmw install …`, and the `npm install` that `ng update` runs — skips the lifecycle
scripts of dependencies, not just the calls in the pom. Scripts you call explicitly
(`npm start`, `npm run build`, `npm test`) still run.

**Check:**

```bash
mvn package
ls .tooling/node          # node, npm, npx, node_modules/
```

---

## 2. Unit tests in the build

One more execution runs the Angular unit tests (Vitest, via `ng test`) in Maven's
`test` phase:

```xml
<execution>
    <id>npm-test</id>
    <phase>test</phase>
    <goals>
        <goal>npm</goal>
    </goals>
    <configuration>
        <arguments>test</arguments>
    </configuration>
</execution>
```

Under Maven there is no interactive terminal, so `ng test` runs once and ends (no
watch mode). A failing test fails the build.

The plugin honours the usual Maven switches: `mvn package -DskipTests` skips only this
execution; install and build still run.

**Check:**

```bash
mvn test
# [INFO] --- frontend:1.15.1:npm (npm-test) @ myapp ---
# [INFO]       Tests  1 passed (1)
```

---

## 3. The Angular dev server via Maven

The Angular dev server runs on port 4200, the REST server somewhere else (here
`localhost:8080`). The browser only talks to 4200; the dev server forwards REST calls
to the REST server (no CORS setup needed).

**a) Use relative API URLs in the Angular code** — `api/hello`, not `/api/hello`:

```ts
@Component({
  selector: 'app-root',
  template: `<h1>MyApp</h1><p>Backend says: {{ greeting() ?? '…' }}</p>`,
})
export class App {
  // relative URL: resolves against <base href> → /myapp/api/hello in the WAR, /api/hello on ng serve
  readonly greeting = toSignal(inject(HttpClient).get('api/hello', { responseType: 'text' }));
}
```

A relative URL resolves against `<base href>`: in the WAR that is `/myapp/`, on the
dev server `/`. The same code works in both places.

**b) Add a proxy configuration** — `frontend/proxy.conf.mjs`:

```js
// ng serve forwards every /api/** call to the running REST server.
// BACKEND_URL includes the context root, e.g. http://localhost:8080/myapp
//   → /api/hello is forwarded to http://localhost:8080/myapp/api/hello
const target = process.env['BACKEND_URL'] ?? 'http://localhost:8080/myapp';

export default {
  '/api': { target, secure: false, changeOrigin: true },
};
```

The path of `target` (`/myapp`) is put in front of the request path, so the context
root is handled here and the Angular code never needs to know it.

**c) Register it** in `angular.json` under `serve`:

```json
"serve": {
  "builder": "@angular/build:dev-server",
  "options": {
    "proxyConfig": "proxy.conf.mjs"
  }
}
```

**d) Add two properties to the pom:**

```xml
<properties>
    <!-- where ng serve forwards /api to: the running REST server incl. context root -->
    <backend.url>http://localhost:8080/myapp</backend.url>
    <!-- port of the Angular dev server -->
    <ng.port>4200</ng.port>
</properties>
```

**e) …and the profile `ng-serve`:**

```xml
<profiles>
    <!-- mvn -Png-serve : Angular dev server (http://localhost:4200, live reload, /api proxy) -->
    <profile>
        <id>ng-serve</id>
        <build>
            <defaultGoal>validate</defaultGoal>
            <plugins>
                <plugin>
                    <groupId>com.github.eirslett</groupId>
                    <artifactId>frontend-maven-plugin</artifactId>
                    <executions>
                        <execution>
                            <id>ng-serve-install-node-and-npm</id>
                            <phase>validate</phase>
                            <goals>
                                <goal>install-node-and-npm</goal>
                            </goals>
                        </execution>
                        <execution>
                            <id>ng-serve-npm-install</id>
                            <phase>validate</phase>
                            <goals>
                                <goal>npm</goal>
                            </goals>
                            <configuration>
                                <!-- install, not ci: fast when nothing changed, keeps node_modules -->
                                <arguments>install --ignore-scripts</arguments>
                            </configuration>
                        </execution>
                        <execution>
                            <id>ng-serve</id>
                            <phase>validate</phase>
                            <goals>
                                <goal>npm</goal>
                            </goals>
                            <configuration>
                                <arguments>start -- --port ${ng.port}</arguments>
                                <environmentVariables>
                                    <BACKEND_URL>${backend.url}</BACKEND_URL>
                                    <NG_CLI_ANALYTICS>false</NG_CLI_ANALYTICS>
                                </environmentVariables>
                            </configuration>
                        </execution>
                    </executions>
                </plugin>
            </plugins>
        </build>
    </profile>
</profiles>
```

How it works:

- **`<defaultGoal>validate</defaultGoal>`** — `mvn -Png-serve` needs no goal. Only
  `validate` runs: no compilation, no WAR.
- **Three executions, all bound to `validate`**, in this order: install Node and npm,
  run `npm install`, start `ng serve`. The first two finish in about a second when
  nothing changed, but they make sure a fresh checkout — or a `git pull` that brought
  new dependencies — just works.
- **`npm install` here, `npm ci` in the build:** `npm ci` deletes `node_modules` and
  reinstalls everything on every start (about 6 s instead of 1 s in the sample) — and
  it would pull `node_modules` away from a test watcher running in another terminal.
  The build keeps `npm ci`, so a lock file that is out of sync still fails there.
- **`npm start -- --port …`** runs the `start` script of `package.json` (`ng serve`);
  everything after `--` is passed on to it.
- **`BACKEND_URL`** reaches `proxy.conf.mjs` as an environment variable;
  `-Dbackend.url=…` changes it from the command line.
- **`NG_CLI_ANALYTICS=false`** — the Angular CLI may ask whether to share usage data.
  Under Maven nobody can answer that prompt and the start would hang.
- The `ng-serve` goal **keeps running** — that is the dev server. **Ctrl-C** stops Maven
  and the Node processes together (verified: nothing is left running).

**Run it:**

```bash
mvn -Png-serve
# [INFO] > ng serve --port 4200
# [INFO] Watch mode enabled. Watching for file changes...
# [INFO]   ➜  Local:   http://localhost:4200/

mvn -Png-serve -Dng.port=4300                                   # 4200 taken
mvn -Png-serve -Dbackend.url=http://localhost:8190/myapp        # REST server on another port
```

Edit a component and save — the dev server rebuilds in a fraction of a second and
pushes the change into the open browser tab:

```
[INFO] ✔ Changes detected. Rebuilding...
[INFO] Component update sent to client(s).
```

"Component update sent" is hot module replacement: templates and styles are swapped
without a page reload, form input and component state stay.

---

## 4. Angular CLI and npm for daily work

All CLI commands run through the Node and npm in `.tooling/`. There are two ways.

**a) Pure Maven** — no extra files, but verbose:

```bash
mvn frontend:npm -Dfrontend.npm.arguments="exec -- ng generate component features/greeting"
# [INFO] CREATE src/app/features/greeting/greeting.ts (165 bytes)
# …
```

This works because of step 1: the command-line call sees the plugin-level
configuration (working directory, install directory, Node version).

**b) A wrapper script `npmw`** — like `mvnw`, committed next to the `pom.xml`. It runs
the project's own npm inside `frontend/` and installs Node and npm through Maven
first, if they are missing:

```sh
#!/bin/sh
# npmw – runs the project's own npm (the one Maven installed into .tooling/)
# inside frontend/. Installs Node + npm via Maven first if they are missing.
#   ./npmw exec -- ng generate component features/foo
#   ./npmw install date-fns
set -e
BASE=$(cd "$(dirname "$0")" && pwd)
NODE_DIR="$BASE/.tooling/node"
if [ ! -x "$NODE_DIR/node" ]; then
  mvn -q -f "$BASE/pom.xml" frontend:install-node-and-npm
fi
PATH="$NODE_DIR:$PATH"
export PATH
cd "$BASE/frontend"
exec "$NODE_DIR/node" "$NODE_DIR/node_modules/npm/bin/npm-cli.js" "$@"
```

```bash
chmod +x npmw
git add npmw && git update-index --chmod=+x npmw   # keep the executable bit in git
```

Windows variant `npmw.cmd` (**not tested** — same logic):

```bat
@echo off
setlocal
set "BASE=%~dp0"
set "NODE_DIR=%BASE%.tooling\node"
if not exist "%NODE_DIR%\node.exe" (
  call mvn -q -f "%BASE%pom.xml" frontend:install-node-and-npm || exit /b 1
)
set "PATH=%NODE_DIR%;%PATH%"
cd /d "%BASE%frontend"
"%NODE_DIR%\node.exe" "%NODE_DIR%\node_modules\npm\bin\npm-cli.js" %*
```

Because the wrapper puts `.tooling/node` first on the `PATH`, tools that call `node` or
`npm` themselves (e.g. `ng update`, which runs `npm install`) use the same versions.

`npm exec -- ng …` runs the Angular CLI from `frontend/node_modules` — the version in
`package.json`, never a global one.

**Check:**

```bash
./npmw --version                 # 11.12.1
./npmw exec -- ng version        # Angular CLI 22.3.0, Node.js 24.15.0, Package Manager npm 11.12.1
```

---

## 5. IDE setup

**IntelliJ IDEA / WebStorm**

- *Settings → Languages & Frameworks → Node.js*:
  Node interpreter `<project>/.tooling/node/node` (Windows: `node.exe`),
  package manager `<project>/.tooling/node/node_modules/npm`.
  Code completion, the Angular language service, running single tests from the
  gutter — all with the project's versions.
- *Run configuration* (type Maven) **ng serve** with command line `-Png-serve`.

**VS Code**

- Run `mvn -Png-serve` in a terminal, or add it as an entry in `.vscode/tasks.json`.
- Use `./npmw …` in the integrated terminal for CLI commands.

---

## 6. Daily work — cheat sheet

**Start of the day** — make sure the REST server is reachable, then:

```bash
mvn -Png-serve        # Angular dev server → open http://localhost:4200
```

| Task | Command |
|---|---|
| Work on the UI | edit `frontend/src/**` — the browser updates itself |
| New component / service / … | `./npmw exec -- ng generate component features/foo` |
| Add a library | `./npmw install date-fns` (commit `package.json` **and** `package-lock.json`) |
| Unit tests while coding | `./npmw test -- --watch` (second terminal, re-runs on save) |
| Unit tests once | `./npmw test` |
| After `git pull` | nothing — `mvn -Png-serve` runs `npm install` on every start |
| Update Angular | `./npmw exec -- ng update @angular/core @angular/cli` |
| Update Node / npm | change `node.version` in the pom (npm comes with it) |
| Deployable WAR | `mvn package` → `target/myapp.war` (frontend built and tested) |

**Which URL?** During development always **http://localhost:4200**. A WAR that is
deployed somewhere contains the frontend of its last `mvn package` — usually an old one.

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `mvn -Png-serve` hangs before "Local:" | an interactive CLI prompt; keep `NG_CLI_ANALYTICS=false` in the profile |
| An option is ignored (`--port`, `--watch`, `--skip-tests`, …) | missing `--`: npm took the option for itself (see the note at the top) |
| `/api/...` returns 404 or 504 on port 4200 | REST server not running, or wrong `-Dbackend.url` (context root included?) |
| `Port 4200 is already in use` | another dev server is still running; stop it or use `-Dng.port=4300` |
| Build fails: `npm ci` "can only install packages when your package.json and package-lock.json … are in sync" | `package.json` changed without `package-lock.json`; run `./npmw install` and commit the lock file |
| `mvn frontend:npm …` uses wrong directory / version | the configuration is still inside an `<execution>`; move it to plugin level (step 1) |
| Company network: downloads blocked | Maven's proxy settings are passed on to npm automatically. For a Nexus/Artifactory mirror set `<nodeDownloadRoot>` (and `<serverId>` for credentials from `settings.xml`) at plugin level, and `registry=…` in `frontend/.npmrc` |

---

## Appendix: the complete `pom.xml`

The verified sample project, all steps applied:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>myapp</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>war</packaging>

    <properties>
        <maven.compiler.release>17</maven.compiler.release>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
        <failOnMissingWebXml>false</failOnMissingWebXml>

        <!-- frontend toolchain: Node.js (npm is bundled with it) -->
        <node.version>v24.15.0</node.version>
        <!-- where ng serve forwards /api to: the running REST server incl. context root -->
        <backend.url>http://localhost:8080/myapp</backend.url>
        <!-- port of the Angular dev server -->
        <ng.port>4200</ng.port>
    </properties>

    <dependencies>
        <dependency>
            <groupId>jakarta.platform</groupId>
            <artifactId>jakarta.jakartaee-api</artifactId>
            <version>10.0.0</version>
            <scope>provided</scope>
        </dependency>
    </dependencies>

    <build>
        <finalName>myapp</finalName>
        <plugins>
            <plugin>
                <groupId>com.github.eirslett</groupId>
                <artifactId>frontend-maven-plugin</artifactId>
                <version>1.15.1</version>
                <!-- plugin-level: also used by command-line calls (mvn frontend:npm ...) -->
                <configuration>
                    <workingDirectory>frontend</workingDirectory>
                    <installDirectory>.tooling</installDirectory>
                    <nodeVersion>${node.version}</nodeVersion>
                </configuration>
                <executions>
                    <execution>
                        <id>install-node-and-npm</id>
                        <goals>
                            <goal>install-node-and-npm</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>npm-ci</id>
                        <goals>
                            <goal>npm</goal>
                        </goals>
                        <configuration>
                            <arguments>ci --ignore-scripts</arguments>
                        </configuration>
                    </execution>
                    <execution>
                        <id>npm-build</id>
                        <goals>
                            <goal>npm</goal>
                        </goals>
                        <configuration>
                            <arguments>run build</arguments>
                        </configuration>
                    </execution>
                    <execution>
                        <id>npm-test</id>
                        <phase>test</phase>
                        <goals>
                            <goal>npm</goal>
                        </goals>
                        <configuration>
                            <arguments>test</arguments>
                        </configuration>
                    </execution>
                </executions>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-war-plugin</artifactId>
                <version>3.4.0</version>
                <configuration>
                    <webResources>
                        <resource>
                            <directory>frontend/dist/frontend/browser</directory>
                        </resource>
                    </webResources>
                </configuration>
            </plugin>
        </plugins>
    </build>

    <profiles>
        <!-- mvn -Png-serve : Angular dev server (http://localhost:4200, live reload, /api proxy) -->
        <profile>
            <id>ng-serve</id>
            <build>
                <defaultGoal>validate</defaultGoal>
                <plugins>
                    <plugin>
                        <groupId>com.github.eirslett</groupId>
                        <artifactId>frontend-maven-plugin</artifactId>
                        <executions>
                            <execution>
                                <id>ng-serve-install-node-and-npm</id>
                                <phase>validate</phase>
                                <goals>
                                    <goal>install-node-and-npm</goal>
                                </goals>
                            </execution>
                            <execution>
                                <id>ng-serve-npm-install</id>
                                <phase>validate</phase>
                                <goals>
                                    <goal>npm</goal>
                                </goals>
                                <configuration>
                                    <!-- install, not ci: fast when nothing changed, keeps node_modules -->
                                    <arguments>install --ignore-scripts</arguments>
                                </configuration>
                            </execution>
                            <execution>
                                <id>ng-serve</id>
                                <phase>validate</phase>
                                <goals>
                                    <goal>npm</goal>
                                </goals>
                                <configuration>
                                    <arguments>start -- --port ${ng.port}</arguments>
                                    <environmentVariables>
                                        <BACKEND_URL>${backend.url}</BACKEND_URL>
                                        <NG_CLI_ANALYTICS>false</NG_CLI_ANALYTICS>
                                    </environmentVariables>
                                </configuration>
                            </execution>
                        </executions>
                    </plugin>
                </plugins>
            </build>
        </profile>
    </profiles>
</project>
```
