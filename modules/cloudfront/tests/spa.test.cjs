const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { resolve } = require('node:path');
const { test } = require('node:test');
const { runInNewContext } = require('node:vm');

const context = {};
runInNewContext(readFileSync(resolve(__dirname, '../spa.js'), 'utf8'), context);

for (const uri of ['/', '/dashboard', '/users/123', '/users/', '/team.v2/dashboard']) {
  test(`SPA route ${uri} resolves to index.html`, () => {
    const request = { uri, method: 'GET', querystring: { tab: { value: 'profile' } }, headers: {} };
    const query = request.querystring;
    assert.equal(context.handler({ request }), request);
    assert.equal(request.uri, '/index.html');
    assert.equal(request.querystring, query);
  });
}

for (const uri of ['/index.html', '/assets/app.abc123.js', '/static/style.css', '/favicon.ico', '/api', '/api/', '/api/users', '/api/export.csv']) {
  test(`Asset or API route ${uri} stays unchanged`, () => {
    const request = {
      uri, method: 'POST', querystring: { limit: { value: '10' } },
      headers: { authorization: { value: 'test-token' } },
      cookies: { session: { value: 'test-session' } }, body: { data: 'test-payload' },
    };
    const original = structuredClone(request);
    assert.equal(context.handler({ request }), request);
    assert.deepEqual(request, original);
  });
}

test('The apiary frontend route is not mistaken for the API prefix', () => {
  const request = { uri: '/apiary' };
  assert.equal(context.handler({ request }).uri, '/index.html');
});
