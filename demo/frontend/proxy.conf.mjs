// ng serve forwards every /api/** call to the running REST server.
// BACKEND_URL includes the context root, e.g. http://localhost:8080/myapp
//   → /api/hello is forwarded to http://localhost:8080/myapp/api/hello
const target = process.env['BACKEND_URL'] ?? 'http://localhost:8080/myapp';

export default {
  '/api': { target, secure: false, changeOrigin: true },
};
