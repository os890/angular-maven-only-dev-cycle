# Hello-world demo

The smallest possible project for a try-run of the
[tutorial](../README.md): an Angular "Hello World" packaged into a WAR by the
frontend-maven-plugin. It is in the state of **step 0** — the tutorial's steps 1–4
are meant to be applied to it.

```
demo/
├── pom.xml                       step 0: Node + npm, npm ci, ng build, WAR
├── src/main/java/…               GET /api/hello (for a real deployment of the WAR)
├── rest-stub/myapp/api/hello     stand-in REST API for the try-run
└── frontend/                     one component that calls api/hello
```

Needs only Java 18+ (it brings `jwebserver`) and Maven.

## 1. The starting point

```bash
cd demo
mvn package        # → target/myapp.war, deployable to any Jakarta EE 10 server under /myapp
```

## 2. Apply the tutorial

Work through steps 1–4 of the [tutorial](../README.md). Shortcut: replace `pom.xml`
with the one from the tutorial's appendix and add the files from steps 1, 3 and 4 —
`.tooling/` in `.gitignore`, `frontend/.npmrc`, `frontend/proxy.conf.mjs`,
`proxyConfig` in `frontend/angular.json`, and `npmw`.

## 3. Try it

Terminal 1 — the REST stub, served by the web server that ships with the JDK:

```bash
jwebserver -p 8080 -d "$(pwd)/rest-stub"
```

Terminal 2 — the Angular dev server:

```bash
mvn -Png-serve
```

Open http://localhost:4200 — it shows **Hello World** and
*Backend says: Hello from the REST stub*. Change the heading in
`frontend/src/app/app.ts` and save: the page updates without a reload.

Port 8080 already taken? Use another one for both:

```bash
jwebserver -p 8190 -d "$(pwd)/rest-stub"
mvn -Png-serve -Dbackend.url=http://localhost:8190/myapp
```

More to try:

```bash
mvn package                                        # now also runs the frontend unit test
./npmw test -- --watch                             # unit test in watch mode
./npmw exec -- ng generate component greeting      # Angular CLI without a global install
```
