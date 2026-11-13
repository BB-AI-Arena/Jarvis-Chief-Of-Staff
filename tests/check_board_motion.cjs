const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
let JSDOM;
try { ({JSDOM} = require('jsdom')); } catch { ({JSDOM} = require('../.build/test-deps/node_modules/jsdom')); }

const root = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'Resources/index.html'), 'utf8');
const script = fs.readFileSync(path.join(root, 'Resources/app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'Resources/style.css'), 'utf8');
const dom = new JSDOM(html, {url: 'https://jarvis.test/', runScripts: 'outside-only'});
const w = dom.window;
const timers = new Map();
let nextTimer = 0;
Object.defineProperty(w.document, 'hidden', {value: false});
w.localStorage.setItem('jarvis.motion', 'false'); // The orb preference must not freeze directors.
w.JARVIS_MODE = 'workspace';
w.requestAnimationFrame = () => 0;
w.ResizeObserver = class { observe() {} };
w.HTMLCanvasElement.prototype.getContext = () => ({});
w.webkit = {messageHandlers: {jarvis: {postMessage() {}}}};
w.matchMedia = () => ({matches: false});
w.Math.random = () => 0.25; // Deterministic pose timing; production remains randomized.
w.setTimeout = (callback, delay) => { const id = ++nextTimer; timers.set(id, {callback, delay}); return id; };
w.clearTimeout = id => timers.delete(id);
w.eval(script);
const seats = w.document.querySelectorAll('#voiceGrid .seat');
assert.equal(seats.length, 6, 'board initialization rendered all directors');
assert.ok(timers.size >= 12, 'board initialization scheduled poses and blinks');
const poseTimer = [...timers.values()].find(t => t.delay >= 400 && t.delay < 900);
assert.ok(poseTimer, 'a director pose is scheduled on startup');
poseTimer.callback();
assert.ok([...seats].some(seat => seat.style.getPropertyValue('--body-turn')), 'scheduled pose updates a director');
assert.match(css, /\.seat \.sway\{transform:rotate\(var\(--body-turn/);
assert.match(css, /\.seat \.bob\{animation:breathe/);
assert.doesNotMatch(css, /\.no-motion \.board-stage/, 'orb preference does not suppress board CSS');
assert.match(css, /@media \(prefers-reduced-motion:reduce\)\{\.board-stage/, 'system reduced motion is respected');
dom.window.close();
console.log('PASS: the board renders, schedules visible poses and is independent of the orb motion preference');
