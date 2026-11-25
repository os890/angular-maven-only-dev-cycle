import { Component, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { toSignal } from '@angular/core/rxjs-interop';

@Component({
  selector: 'app-root',
  template: `<h1>Hello World</h1><p>Backend says: {{ greeting() ?? '…' }}</p>`,
})
export class App {
  // relative URL: resolves against <base href> → /myapp/api/hello in the WAR, /api/hello on ng serve
  readonly greeting = toSignal(inject(HttpClient).get('api/hello', { responseType: 'text' }));
}
