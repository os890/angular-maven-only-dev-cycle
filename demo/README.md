# Hello-world demo

The smallest possible project for a try-run of the
[tutorial](../README.md): an Angular "Hello World" packaged into a WAR by the
frontend-maven-plugin, with **all steps of the tutorial already applied**. It runs
as checked out.

```
demo/
├── pom.xml                       the tutorial's appendix pom (steps 1–3)
├── npmw, npmw.cmd                wrapper for npm / Angular CLI (step 4)
├── src/main/java/…               GET /api/hello (for a real deployment of the WAR)
├── rest-stub/myapp/api/hello     stand-in REST API for the try-run
└── frontend/
    ├── .npmrc                    ignore-scripts=true (step 1)
    ├── proxy.conf.mjs            /api → REST server (step 3)
    ├── angular.json              proxyConfig under serve (step 3)
    └── src/…                     one component that calls api/hello
```

Needs only Java 18+ (it brings `jwebserver`) and Maven. Node.js, npm and the
Angular CLI are downloaded by Maven into `.tooling/` and `frontend/node_modules/`.

## Try it

Terminal 1 — the REST stub, served by the web server that ships with the JDK:

```bash
cd demo
jwebserver -p 8080 -d "$(pwd)/rest-stub"
```

Terminal 2 — the Angular dev server:

```bash
cd demo
mvn -Png-serve
```

Open http://localhost:4200 — it shows **Hello World** and
*Backend says: Hello from the REST stub*. Change the heading in
`frontend/src/app/app.ts` and save: the page updates without a reload.

Port 8080 already taken? Use another one for both:

```bash
jwebserver -p 9191 -d "$(pwd)/rest-stub"
mvn -Png-serve -Dbackend.url=http://localhost:9191/myapp
```

`-Dng.port=4300` moves the dev server itself off 4200.

More to try:

```bash
mvn package                                        # → target/myapp.war, incl. the frontend unit test
./npmw test -- --watch                             # unit test in watch mode
./npmw exec -- ng generate component greeting      # Angular CLI without a global install
```

`target/myapp.war` is deployable to any Jakarta EE 10 server under `/myapp`; there
`api/hello` is answered by `HelloResource` instead of the stub.

## Want to apply the steps yourself?

Start from the plugin-only state the tutorial calls step 0: replace `pom.xml`
with the plugin block from [step 0](../README.md#0-the-starting-point), and delete
`npmw`, `npmw.cmd`, `frontend/.npmrc`, `frontend/proxy.conf.mjs` and the
`"options": { "proxyConfig": … }` line in `frontend/angular.json`. Then work
through steps 1–4. `git checkout -- .` brings the finished state back.
