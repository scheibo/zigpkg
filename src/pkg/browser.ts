
import type {AddOn, Argument} from '.';

export async function load(addon?: Argument): Promise<AddOn> {
  if (typeof addon === 'string' && addon !== 'wasm') {
    throw new Error('Unable to load native addons in the browser!');
  }

  let wasm: WebAssembly.Instance;
  if (addon instanceof WebAssembly.Module) {
    try {
      wasm = (await WebAssembly.instantiate(addon, {env: {overflow}}));
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      throw new Error(`Could not instantiate WASM module!\n${err.message}`);
    }
  } else {
    try {
      const response = !addon || addon === 'wasm' ? fetch('zigpkg.wasm')
        : (addon as Promise<Response> | URL) instanceof URL ? fetch(addon) : addon;
      wasm = (await WebAssembly.instantiateStreaming(response, {env: {overflow}})).instance;
    } catch (err) {
      if (!(err instanceof Error)) throw err;
      const message = !addon || addon === 'wasm'
        ? 'WASM addon not found - did you run `npx install-zigpkg`?'
        : (addon as Promise<Response> | URL) instanceof URL
          ? `Could not fetch WASM module from '${(addon as URL).href}'`
          : 'Could not instantiate WASM module!';
      throw new Error(`${message}\n${err.message}`);
    }
  }

  return wasm.exports as AddOn;
}

function overflow() {
  throw new Error('Result overflow');
}