import * as fs from 'fs';
import * as path from 'path';

type AddOn = {compute(this: void, n: number): number};
type WASM = {instance: {exports: AddOn}};
let ADDON: AddOn | undefined = undefined;
let loading: Promise<void> | undefined = undefined;

export async function initialize(addon?: 'node' | 'wasm') {
  if (loading) throw new Error('Cannot call initialize more than once');
  loading = load(addon);
  loading.catch(() => {
    loading = undefined;
  });
  return loading;
}

async function load(addon?: 'node' | 'wasm') {
  const src = /src[/\\]pkg$/.test(__dirname);
  if (!addon || addon == 'node') {
    try {
      ADDON = require(src ? `../../build/lib/zigpkg.node` : `../lib/zigpkg.node`) as AddOn;
      return;
    } catch {
      if (addon == 'node') {
        throw new Error('Native addon not found - did you run `npm exec install-zigpkg`?');
      }
    }
  }
  try {
    const buf = fs.readFileSync(
      path.resolve(__dirname, src ? `../../build/lib/zigpkg.wasm` : `../lib/zigpkg.wasm`));
    const wasm =  await WebAssembly.instantiate(buf, {env: {overflow}}) as unknown as WASM
    ADDON = wasm.instance.exports;
  } catch (err) {
    const message = addon ? 'Unable to find addons' : 'WASM addon not found';
    throw new Error(`${message} - did you run \`npm exec install-zigpkg\`?`);
  }
}

export function compute(n: number) {
  if (!ADDON) throw new Error('You must call and wait for initialize before calling compute');
  return ADDON.compute(n);
}

function overflow() {
  throw new Error('Result overflow');
}

// test only
export function deinitialize() {
  loading = undefined;
}