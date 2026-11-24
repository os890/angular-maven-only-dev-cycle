# Angular dev cycle with Maven only

**From "the frontend-maven-plugin packs Angular into the WAR" to a full daily
frontend development setup — on a machine that has nothing but Java and Maven.**

Many Jakarta EE teams already use the
[frontend-maven-plugin](https://github.com/eirslett/frontend-maven-plugin)
("eirslett plugin") to build an Angular app and package it into a WAR. That solves the
*build*. This tutorial adds the frontend *development cycle* on top of it:

- the Angular dev server (`ng serve`) with live reload and hot module replacement,
- REST calls from the dev server forwarded to the server that provides the REST APIs,
- the Angular CLI (`ng generate`, `ng update`, …) and pnpm for daily work,
- unit tests in the build and in watch mode,

…without anyone installing Node.js, pnpm or the Angular CLI by hand. Maven downloads
a pinned Node.js and pnpm into the project; the Angular CLI is an ordinary dev
dependency in `node_modules`. Nothing is installed globally.

The backend is out of scope: the tutorial assumes there is a running server that
provides the REST APIs (locally, started from the IDE, or a shared dev/test server).

> **Verified setup.** Every command in this tutorial was run against a sample WAR
> project with: Maven 3.9.14 · frontend-maven-plugin 1.15.1 · Node.js 24.15.0 ·
> pnpm 11.10.0 · Angular 22.0.5 · macOS.
> The Windows wrapper script in step 4 was **not** tested.

## The result at a glance

| You want to … | Command (from the WAR module) |
|---|---|
| start the Angular dev server (live reload, `/api` proxy) | `mvn -Png-serve` |
| run any Angular CLI / pnpm command | `./pnpmw ng generate component features/foo` |
| run unit tests in watch mode | `./pnpmw test --watch` |
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

---

## 0. The starting point

The tutorial assumes a WAR module with the Angular app in a `frontend/` subfolder.
Adapt paths if your layout differs (e.g. a separate frontend module).

```
myapp/
├── pom.xml                      packaging: war
├── src/main/…                   server side (not touched by this tutorial)
└── frontend/
    ├── package.json             "packageManager": "pnpm@11.10.0"
    ├── pnpm-lock.yaml
    ├── angular.json
    └── src/…
```

This is what "already works" with the plugin: Node and pnpm are downloaded, the
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
            <id>install-node-and-pnpm</id>
            <goals>
                <goal>install-node-and-pnpm</goal>
            </goals>
            <configuration>
                <nodeVersion>v24.15.0</nodeVersion>
                <pnpmVersion>v11.10.0</pnpmVersion>
            </configuration>
        </execution>
        <execution>
            <id>pnpm-install</id>
            <goals>
                <goal>pnpm</goal>
            </goals>
            <configuration>
                <arguments>install --ignore-scripts --frozen-lockfile</arguments>
            </configuration>
        </execution>
        <execution>
            <id>pnpm-build</id>
            <goals>
                <goal>pnpm</goal>
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

**a) Versions and directories move to the plugin-level `<configuration>`.**
Settings inside an `<execution>` only apply to that execution. Command-line calls such
as `mvn frontend:pnpm …` (step 4) run as execution `default-cli` and only see the
plugin-level configuration.

**b) The tools move from `target/` to `.tooling/`.** `mvn clean` deletes `target/`,
and with it Node and pnpm. Maven caches the downloads in `~/.m2`, so a reinstall is
quick, but the IDE's Node interpreter path (step 5) and the `pnpmw` wrapper (step 4)
need a path that stays put.

```xml
<properties>
    <!-- frontend toolchain: keep in sync with "packageManager" in frontend/package.json -->
    <node.version>v24.15.0</node.version>
    <pnpm.version>v11.10.0</pnpm.version>
</properties>
```

```xml
<plugin>
    <groupId>com.github.eirslett</groupId>
    <artifactId>frontend-maven-plugin</artifactId>
    <version>1.15.1</version>
    <!-- plugin-level: also used by command-line calls (mvn frontend:pnpm ...) -->
    <configuration>
        <workingDirectory>frontend</workingDirectory>
        <installDirectory>.tooling</installDirectory>
        <nodeVersion>${node.version}</nodeVersion>
        <pnpmVersion>${pnpm.version}</pnpmVersion>
    </configuration>
    <executions>
        <execution>
            <id>install-node-and-pnpm</id>
            <goals>
                <goal>install-node-and-pnpm</goal>
            </goals>
        </execution>
        <!-- pnpm-install and pnpm-build: unchanged -->
    </executions>
</plugin>
```

Ignore the new directory in git (`.gitignore` next to the `pom.xml`):

```
.tooling/
```

**Supply-chain safety net.** Put an `.npmrc` into `frontend/`:

```
ignore-scripts=true
```

With it, *every* pnpm call — also the ones you type in step 4, such as `pnpmw add …` —
skips the lifecycle scripts of dependencies, not just the `install` in the pom.
Scripts you call explicitly (`pnpm start`, `pnpm run build`, `pnpm test`) still run.

**Check:**

```bash
mvn package
ls .tooling/node          # node, pnpm, node_modules/
```

---

## 2. Unit tests in the build

One more execution runs the Angular unit tests (Vitest, via `ng test`) in Maven's
`test` phase:

```xml
<execution>
    <id>pnpm-test</id>
    <phase>test</phase>
    <goals>
        <goal>pnpm</goal>
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
# [INFO] --- frontend:1.15.1:pnpm (pnpm-test) @ myapp ---
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
                            <id>ng-serve-install-node-and-pnpm</id>
                            <phase>validate</phase>
                            <goals>
                                <goal>install-node-and-pnpm</goal>
                            </goals>
                        </execution>
                        <execution>
                            <id>ng-serve-pnpm-install</id>
                            <phase>validate</phase>
                            <goals>
                                <goal>pnpm</goal>
                            </goals>
                            <configuration>
                                <arguments>install --ignore-scripts --frozen-lockfile</arguments>
                            </configuration>
                        </execution>
                        <execution>
                            <id>ng-serve</id>
                            <phase>validate</phase>
                            <goals>
                                <goal>pnpm</goal>
                            </goals>
                            <configuration>
                                <arguments>start --port ${ng.port}</arguments>
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
- **Three executions, all bound to `validate`**, in this order: install Node and pnpm,
  run `pnpm install`, start `ng serve`. The first two finish in about a second when
  nothing changed, but they make sure a fresh checkout — or a `git pull` that brought
  new dependencies — just works.
- **`pnpm start --port …`** runs the `start` script of `package.json` (`ng serve`);
  pnpm appends `--port` to it.
- **`BACKEND_URL`** reaches `proxy.conf.mjs` as an environment variable;
  `-Dbackend.url=…` changes it from the command line.
- **`NG_CLI_ANALYTICS=false`** — the Angular CLI may ask whether to share usage data.
  Under Maven nobody can answer that prompt and the start would hang.
- The `ng-serve` goal **keeps running** — that is the dev server. **Ctrl-C** stops Maven
  and the Node processes together (verified: nothing is left running).

**Run it:**

```bash
mvn -Png-serve
# [INFO] $ ng serve --port 4200
# [INFO] Watch mode enabled. Watching for file changes...
# [INFO]   ➜  Local:   http://localhost:4200/

mvn -Png-serve -Dng.port=4300                                   # 4200 taken
mvn -Png-serve -Dbackend.url=http://localhost:8190/myapp        # REST server on another port
```

Edit a component and save — the dev server rebuilds in a fraction of a second and
pushes the change into the open browser tab:

```
[INFO] ❯ Changes detected. Rebuilding...
[INFO] Application bundle generation complete. [0.183 seconds]
[INFO] Component update sent to client(s).
```

"Component update sent" is hot module replacement: templates and styles are swapped
without a page reload, form input and component state stay.

---

## 4. Angular CLI and pnpm for daily work

All CLI commands run through the Node and pnpm in `.tooling/`. There are two ways.

**a) Pure Maven** — no extra files, but verbose:

```bash
mvn frontend:pnpm -Dfrontend.pnpm.arguments="exec ng generate component features/greeting"
# [INFO] CREATE src/app/features/greeting/greeting.ts (198 bytes)
# …
```

This works because of step 1: the command-line call sees the plugin-level
configuration (working directory, install directory, versions).

**b) A wrapper script `pnpmw`** — like `mvnw`, committed next to the `pom.xml`. It runs
the project's own pnpm inside `frontend/` and installs Node and pnpm through Maven
first, if they are missing:

```sh
#!/bin/sh
# pnpmw – runs the project's own pnpm (the one Maven installed into .tooling/)
# inside frontend/. Installs Node + pnpm via Maven first if they are missing.
#   ./pnpmw ng generate component features/foo
#   ./pnpmw add date-fns
set -e
BASE=$(cd "$(dirname "$0")" && pwd)
NODE_DIR="$BASE/.tooling/node"
if [ ! -x "$NODE_DIR/node" ]; then
  mvn -q -f "$BASE/pom.xml" frontend:install-node-and-pnpm
fi
PATH="$NODE_DIR:$PATH"
export PATH
exec "$NODE_DIR/node" "$NODE_DIR/node_modules/pnpm/bin/pnpm.cjs" --dir "$BASE/frontend" "$@"
```

```bash
chmod +x pnpmw
git add pnpmw && git update-index --chmod=+x pnpmw   # keep the executable bit in git
```

Windows variant `pnpmw.cmd` (**not tested** — same logic):

```bat
@echo off
setlocal
set "BASE=%~dp0"
set "NODE_DIR=%BASE%.tooling\node"
if not exist "%NODE_DIR%\node.exe" (
  call mvn -q -f "%BASE%pom.xml" frontend:install-node-and-pnpm || exit /b 1
)
set "PATH=%NODE_DIR%;%PATH%"
"%NODE_DIR%\node.exe" "%NODE_DIR%\node_modules\pnpm\bin\pnpm.cjs" --dir "%BASE%frontend" %*
```

Because the wrapper puts `.tooling/node` first on the `PATH`, tools that call `node` or
`pnpm` themselves (e.g. `ng update`, which runs `pnpm install`) use the same versions.

**Check:**

```bash
./pnpmw --version              # 11.10.0
./pnpmw ng version             # Angular CLI 22.0.5, Node.js 24.15.0
```

---

## 5. IDE setup

**IntelliJ IDEA / WebStorm**

- *Settings → Languages & Frameworks → Node.js*:
  Node interpreter `<project>/.tooling/node/node` (Windows: `node.exe`),
  package manager `<project>/.tooling/node/node_modules/pnpm`.
  Code completion, the Angular language service, running single tests from the
  gutter — all with the project's versions.
- *Run configuration* (type Maven) **ng serve** with command line `-Png-serve`.

**VS Code**

- Run `mvn -Png-serve` in a terminal, or add it as an entry in `.vscode/tasks.json`.
- Use `./pnpmw …` in the integrated terminal for CLI commands.

---

## 6. Daily work — cheat sheet

**Start of the day** — make sure the REST server is reachable, then:

```bash
mvn -Png-serve        # Angular dev server → open http://localhost:4200
```

| Task | Command |
|---|---|
| Work on the UI | edit `frontend/src/**` — the browser updates itself |
| New component / service / … | `./pnpmw ng generate component features/foo` |
| Add a library | `./pnpmw add date-fns` (commit `package.json` **and** `pnpm-lock.yaml`) |
| Unit tests while coding | `./pnpmw test --watch` (second terminal, re-runs on save) |
| Unit tests once | `./pnpmw test` |
| After `git pull` | nothing — `mvn -Png-serve` runs `pnpm install` on every start |
| Update Angular | `./pnpmw ng update @angular/core @angular/cli` |
| Update Node / pnpm | change `node.version` / `pnpm.version` in the pom **and** `packageManager` in `package.json` |
| Deployable WAR | `mvn package` → `target/myapp.war` (frontend built and tested) |

**Which URL?** During development always **http://localhost:4200**. A WAR that is
deployed somewhere contains the frontend of its last `mvn package` — usually an old one.

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `mvn -Png-serve` hangs before "Local:" | an interactive CLI prompt; keep `NG_CLI_ANALYTICS=false` in the profile |
| `/api/...` returns 404 or 504 on port 4200 | REST server not running, or wrong `-Dbackend.url` (context root included?) |
| `Port 4200 is already in use` | another dev server is still running; stop it or use `-Dng.port=4300` |
| Build fails with `ERR_PNPM_OUTDATED_LOCKFILE` | `package.json` changed without `pnpm-lock.yaml`; run `./pnpmw install` and commit the lock file |
| `mvn frontend:pnpm …` uses wrong directory / version | the configuration is still inside an `<execution>`; move it to plugin level (step 1) |
| Company network: downloads blocked | Maven's proxy settings are passed on to pnpm automatically. For a Nexus/Artifactory mirror set `<nodeDownloadRoot>` / `<pnpmDownloadRoot>` (and `<serverId>` for credentials from `settings.xml`) at plugin level, and `registry=…` in `frontend/.npmrc` |

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

        <!-- frontend toolchain: keep in sync with "packageManager" in frontend/package.json -->
        <node.version>v24.15.0</node.version>
        <pnpm.version>v11.10.0</pnpm.version>
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
                <!-- plugin-level: also used by command-line calls (mvn frontend:pnpm ...) -->
                <configuration>
                    <workingDirectory>frontend</workingDirectory>
                    <installDirectory>.tooling</installDirectory>
                    <nodeVersion>${node.version}</nodeVersion>
                    <pnpmVersion>${pnpm.version}</pnpmVersion>
                </configuration>
                <executions>
                    <execution>
                        <id>install-node-and-pnpm</id>
                        <goals>
                            <goal>install-node-and-pnpm</goal>
                        </goals>
                    </execution>
                    <execution>
                        <id>pnpm-install</id>
                        <goals>
                            <goal>pnpm</goal>
                        </goals>
                        <configuration>
                            <arguments>install --ignore-scripts --frozen-lockfile</arguments>
                        </configuration>
                    </execution>
                    <execution>
                        <id>pnpm-build</id>
                        <goals>
                            <goal>pnpm</goal>
                        </goals>
                        <configuration>
                            <arguments>run build</arguments>
                        </configuration>
                    </execution>
                    <execution>
                        <id>pnpm-test</id>
                        <phase>test</phase>
                        <goals>
                            <goal>pnpm</goal>
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
                                <id>ng-serve-install-node-and-pnpm</id>
                                <phase>validate</phase>
                                <goals>
                                    <goal>install-node-and-pnpm</goal>
                                </goals>
                            </execution>
                            <execution>
                                <id>ng-serve-pnpm-install</id>
                                <phase>validate</phase>
                                <goals>
                                    <goal>pnpm</goal>
                                </goals>
                                <configuration>
                                    <arguments>install --ignore-scripts --frozen-lockfile</arguments>
                                </configuration>
                            </execution>
                            <execution>
                                <id>ng-serve</id>
                                <phase>validate</phase>
                                <goals>
                                    <goal>pnpm</goal>
                                </goals>
                                <configuration>
                                    <arguments>start --port ${ng.port}</arguments>
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
