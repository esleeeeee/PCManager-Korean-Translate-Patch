const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');

const source = readFileSync(join(__dirname, '../src/agent.ps1'), 'utf8');
const script = source.match(/\$InjectionScript = @"\r?\n([\s\S]*?)\r?\n"@/)[1];
function harness(late = false) {
  const calls = [];
  const webview = { postMessage(value) { calls.push(value); return 'sent'; } };
  let retry;
  const context = vm.createContext({
    window: { chrome: late ? {} : { webview } },
    setInterval(fn) { retry = fn; return 1; }, clearInterval() {}, setTimeout() {},
  });
  vm.runInContext(script, context);
  return { calls, webview, context, retry: () => retry() };
}

test('missing language in a JSON request becomes Korean and retains the text', () => {
  const h = harness();
  assert.equal(h.webview.postMessage(JSON.stringify({ type: 'SmartTranslateRequest', message: { text: 'Hello' } })), 'sent');
  assert.deepEqual(JSON.parse(h.calls[0]), { type: 'SmartTranslateRequest', message: { text: 'Hello', targetLanguage: 'ko' } });
});
test('object requests and an absent message also default to Korean', () => {
  const h = harness();
  h.webview.postMessage({ type: 'SmartTranslateRequest' });
  assert.equal(h.calls[0].message.targetLanguage, 'ko');
});
test('explicit English, Japanese and Chinese selections remain unchanged', () => {
  for (const language of ['en', 'ja', 'zh-Hans']) {
    const h = harness();
    for (const value of [{ type: 'SmartTranslateRequest', message: { targetLanguage: language } },
      JSON.stringify({ type: 'SmartTranslateRequest', message: { targetLanguage: language } })]) {
      h.webview.postMessage(value);
    }
    assert.equal(h.calls[0].message.targetLanguage, language);
    assert.equal(JSON.parse(h.calls[1]).message.targetLanguage, language);
  }
});
test('unrelated messages pass through unchanged', () => {
  const h = harness();
  const request = { type: 'OtherRequest', message: { text: 'Keep me' } };
  h.webview.postMessage(request);
  assert.equal(h.calls[0], request);
  assert.equal(request.message.targetLanguage, undefined);
});
test('invalid JSON and null pass through without breaking the host', () => {
  const h = harness();
  for (const value of ['not JSON', null]) h.webview.postMessage(value);
  assert.deepEqual(h.calls, ['not JSON', null]);
});
test('repeated injection does not double wrap the bridge', () => {
  const h = harness();
  const first = h.webview.postMessage;
  vm.runInContext(script, h.context);
  assert.equal(h.webview.postMessage, first);
  h.webview.postMessage({ type: 'SmartTranslateRequest' });
  assert.equal(h.calls.length, 1);
});
test('a bridge created after injection is patched on retry', () => {
  const h = harness(true);
  h.context.window.chrome.webview = h.webview;
  h.retry();
  h.webview.postMessage({ type: 'SmartTranslateRequest' });
  assert.equal(h.calls[0].message.targetLanguage, 'ko');
});
