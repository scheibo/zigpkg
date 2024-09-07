
import {AddOn, Argument, overflow} from '.';

import * as fs from 'fs';
import * as path from 'path';

const ROOT = path.join(__dirname, '..', '..');

// @test-only
export const WASM = path.join(ROOT, 'build', 'lib', 'zigpkg.wasm');
export const NODE = path.join(ROOT, 'build', 'lib', 'zigpkg.node')

export async function load(addon?: Argument): Promise<AddOn> {
  if (addon == undefined || typeof addon === 'string' && addon !== 'wasm') {
    try {
      return require(!addon || addon === 'node' ? NODE: addon) as AddOn;
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      const message = addon && addon !== 'node'
        ? `Unable to load native addon: '${addon}'`
        : 'Native addon not found - did you run `npx install-zigpkg`?'
      throw new Error(`${message}\n${err.message}`);
    }
  }

  let wasm: WebAssembly.Instance;
  if (addon === 'wasm') {
    try {
      wasm = (await WebAssembly.instantiate(fs.readFileSync(WASM), {env: {overflow}})).instance;
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`WASM addon not found - did you run \`npx install-zigpkg\`?\n${err.message}`);
    }
  } else if (addon instanceof WebAssembly.Module) {
    try {
      wasm = (await WebAssembly.instantiate(addon, {env: {overflow}}));
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`Could not instanstiate WASM module!\n${err.message}`);
    }
  } else {
    try {
    const response = (addon as Promise<Response> | URL) instanceof Promise ? addon : fetch(addon);
    wasm = (await WebAssembly.instantiateStreaming(response, {env: {overflow}})).instance;
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`Could not instanstiate WASM module!\n${err.message}`);
    }
  }
  return wasm.exports as AddOn;
}