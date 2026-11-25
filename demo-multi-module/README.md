# Multi-module variant of the demo

The [hello-world demo](../demo/README.md) has one pom: the WAR module *is* the
root. Many real projects have a **root pom that is a parent with modules**, and
the Angular app lives in one of them. This variant shows the
[tutorial](../README.md) applied to that layout, with all steps already applied.

```
demo-multi-module/
├── pom.xml                       parent + aggregator: versions, plugin-level config, ng-serve default goal
├── npmw, npmw.cmd                npm / Angular CLI wrapper, points at webapp/
├── api/                          jar: GET /api/hello (ends up in WEB-INF/lib)
├── webapp/
│   ├── pom.xml                   WAR: frontend executions + ng-serve profile
│   └── frontend/                 the Angular app (same as in demo/)
└── rest-stub/myapp/api/hello     stand-in REST API for the try-run
```

## Try it

Same as the single-module demo. Everything runs from the **root**.

```bash
cd demo-multi-module
jwebserver -p 8080 -d "$(pwd)/rest-stub"     # terminal 1
mvn -Png-serve                              # terminal 2 → http://localhost:4200
```

```bash
mvn package                                  # → webapp/target/myapp.war (incl. frontend test)
./npmw test -- --watch
./npmw exec -- ng generate component greeting
```

`-Dbackend.url=…` and `-Dng.port=…` work as in the tutorial.

## What differs from the single-module setup

**1. The plugin goes into `<pluginManagement>` of the root pom, not `<plugins>`.**
A plugin in `<build><plugins>` of a parent is inherited by *every* module. Each
one would install Node into its own `.tooling/` and look for its own `frontend/`
folder. In `<pluginManagement>`, the parent only fixes the version and the
plugin-level `<configuration>`. The executions are declared in `webapp/pom.xml`,
the only module that uses the plugin. `workingDirectory` and `installDirectory`
are relative to that module, so `webapp/frontend` and `webapp/.tooling`.

**2. The profile `ng-serve` exists in both poms.**

- `webapp/pom.xml` has the three executions, exactly as in the tutorial.
- The root pom only has `<defaultGoal>validate</defaultGoal>`.

Maven takes the default goal from the pom in the **current directory**. Without
the root's copy, `mvn -Png-serve` in the root fails with *"No goals have been
specified for this build"*. With it, the reactor runs `validate` for all
modules (quick: no compilation), and `ng serve` starts in `webapp` last.

`mvn -Png-serve -pl webapp` skips the other modules.

**3. `npmw` calls Maven with `-f webapp/pom.xml`.** This only installs Node and
npm for the module with the frontend, not for the whole reactor. It then runs
npm in `webapp/frontend`. The same applies to the pure-Maven way of the
tutorial's step 4:

```bash
mvn -f webapp/pom.xml frontend:npm -Dfrontend.npm.arguments="exec -- ng version"
```

**4. The WAR module needs the Jakarta EE API itself.** `provided`
dependencies are not transitive, so `webapp` does not get it through `api`.
Without its own dependency, `maven-war-plugin` 3.4.0 failed with *"webxml
attribute is required"*, even with `failOnMissingWebXml=false`.

## Frontend directly next to the root pom?

If `frontend/` sits next to a parent pom (not in a module), keep the plugin in
`<build><plugins>` of the root pom, but add `<inherited>false</inherited>` to it
(and to the `ng-serve` profile's plugin). Then call Maven non-recursively:
`mvn -N -Png-serve`, and `mvn -q -N -f "$BASE/pom.xml" …` in `npmw`. This layout
is not part of the demo and was not tested here.

## Other differences in existing projects

| Point | Tutorial / demos | Adjust when |
|---|---|---|
| Unit tests in the build | Vitest (Angular 21+): runs once, no browser | **Karma**: `test -- --watch=false --browsers=ChromeHeadless`, needs Chrome on the machine |
| WAR resource directory | `frontend/dist/frontend/browser` (application builder, Angular 17+) | old browser builder: `dist/<name>`, without `/browser` |
| Proxy file | `proxy.conf.mjs` (ES module, reads `BACKEND_URL`) | older CLIs: `proxy.conf.js` with `module.exports = …` |
| API URLs in the code | relative (`api/hello`) | absolute URLs (`http://localhost:8080/…` in `environment.ts`) bypass the proxy → CORS errors |
| Proxy prefix | `/api` | REST under `/rest`, `/resources`, … → change the key in `proxy.conf.mjs` |
| `start` script | `"start": "ng serve"` | missing or different: adjust it, or use `exec -- ng serve --port …` in the profile |
| Package manager | npm | yarn or pnpm: `install-node-and-yarn` / `install-node-and-pnpm` and their goals; adapt `npmw` |
| Node version | v24.15.0 | must be supported by the project's Angular version |

Verified for this variant: `mvn package` from the root (frontend test passes,
WAR contains the Angular build and `WEB-INF/lib/myapp-api-…jar`),
`mvn -Png-serve` from the root (app served, `/api/hello` proxied to the
`jwebserver` stub), `./npmw --version` and `./npmw exec -- ng version`, also
with `webapp/.tooling` deleted first. Maven 3.9.14, Node.js 24.15.0, npm
11.12.1, Angular 22.3.0, macOS. `npmw.cmd` was not tested.
